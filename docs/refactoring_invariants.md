# Private Index Engine — Refactoring Invariants & API Contracts

This document establishes the architectural invariants, public API contracts, and database schema guarantees for the `PrivateIndexEngine`. Any refactoring, modernization, or modularization within the pipeline **must** preserve these invariants.

---

## 1. Architectural Public API Boundaries & Contracts

### 1.1 `VectorStore` (and `IndexDatabase`)

`IndexDatabase` is a typealias for `VectorStore`. It manages the SQLite connection, extension registration (`sqlite-vec`), schema management, metadata tracking, and full-text & vector query execution.

- **Threading Contract**: `VectorStore` is **not** thread-safe. Concurrent access must be serialized using external synchronization or enclosed within an actor (e.g., `IndexCoordinator`).
- **Connection Model**: Uses `sqlite3_open_v2` with `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX`.
- **Extension Initialization**: Registers `sqlite-vec` directly per-connection via `sqlite3_vec_init` (bypassing deprecated auto-extension APIs on Apple platforms).
- **Core PRAGMAs**:
  - `PRAGMA journal_mode=WAL;` (Write-Ahead Logging for non-blocking concurrent reads).
  - `PRAGMA foreign_keys=ON;` (Enforces referential integrity between tables).

#### Public Types:
- `FileRecord`: Struct representing an indexed file (`id: Int64`, `path: String`, `mtime: Date`, `size: Int64`).
- `SearchResult`: Vector KNN hit (`chunkId: Int64`, `fileId: Int64`, `filePath: String`, `distance: Float`, `content: String`).
- `KeywordSearchResult`: FTS5 BM25 hit (`chunkId: Int64`, `fileId: Int64`, `filePath: String`, `score: Float`, `content: String`).
- `StoreError`: Error enum (`openFailed`, `sqlError`, `extensionRegistrationFailed`).

#### Public Method Contracts:
- `init(at url: URL? = nil) throws`: Opens file database at `url` or in-memory DB if `url` is `nil`.
- `createSchema() throws`: Creates `indexed_files`, `text_chunks`, `vec_chunks` (`vec0`), `documents_fts` (`fts5`), insert/delete triggers, and backfills unindexed chunks.
- `insertFile(path: String, mtime: Date, size: Int64) throws -> Int64`: Inserts file metadata and returns new `rowid`.
- `getFile(byPath: String) throws -> FileRecord?`: Fetches single file record by path.
- `getAllIndexedFiles() throws -> [String: FileRecord]`: Returns dictionary of all indexed files keyed by normalized file path.
- `deleteFile(id: Int64) throws`: Executes transactional cascaded deletion:
  1. Deletes from `vec_chunks` where `chunk_id` in `text_chunks`.
  2. Deletes from `documents_fts` where `rowid` in `text_chunks`.
  3. Deletes from `text_chunks` where `file_id = ?`.
  4. Deletes from `indexed_files` where `id = ?`.
- `deleteFile(path: String) throws`: Looks up file ID by path and invokes `deleteFile(id:)`.
- `reset() throws`: Truncates `documents_fts`, `vec_chunks`, `text_chunks`, and `indexed_files` inside an atomic transaction.
- `insertChunk(fileId: Int64, chunkIndex: Int, content: String, embedding: [Float]) throws -> Int64`:
  - Enforces `embedding.count == 384`.
  - Atomically inserts text into `text_chunks` and raw float bytes into `vec_chunks`.
- `search(queryVector: [Float], limit: Int = 10) throws -> [SearchResult]`:
  - Enforces `queryVector.count == 384`.
  - Executes `vec0` KNN cosine MATCH query: `ORDER BY vc.distance LIMIT ?`.
- `searchBM25(query: String, limit: Int = 10) throws -> [KeywordSearchResult]`:
  - Builds sanitized FTS5 query with `buildFTS5Query`.
  - Orders results by `bm25(documents_fts) ASC`.
- `buildFTS5Query(from rawQuery: String) -> String?`:
  - Sanitizes user input, escapes quotes, generates exact phrase, conjunction (`AND`), and disjunction (`OR`) query terms.
- `close()`: Finalizes statements and closes SQLite database connection via `sqlite3_close_v2`.

---

### 1.2 `IndexCoordinator`

`IndexCoordinator` is a Swift `actor` that orchestrates the crawling, reading, chunking, embedding, indexing, and search pipelines.

- **Concurrency & Isolation**: `IndexCoordinator` is an `actor`. All mutations and searches are isolated, serializing database access across asynchronous tasks.

#### Public Types:
- `IndexReport`:
  - `filesScanned: Int`
  - `filesIndexed: Int`
  - `filesSkipped: Int`
  - `filesDeleted: Int`
  - `chunksIndexed: Int`
  - `duration: TimeInterval`
  - `filesSkippedEvicted: Int`
- `SearchMode`: Enum (`hybrid`, `vector`, `keyword`).
- `SearchResultItem`: Unified user result (`id: Int64`, `fileId: Int64`, `filePath: String`, `distance: Float`, `score: Float`, `content: String`, `matchType: String`).

#### Public Method Contracts:
- `index(directoryURL: URL, onProgress: (@Sendable (Float, String) -> Void)? = nil) async throws -> IndexReport`:
  - **Prune Phase**: Deletes previously indexed files under `directoryURL` that no longer exist on disk.
  - **Incremental Filter**: Compares disk `mtime` and `size` against `indexed_files`. Unchanged files are skipped without reading or re-embedding.
  - **Extraction & Embedding**: For each modified/new file, extracts text via `DocumentReader`, chunks via `TextChunker`, generates 384-dim dense vectors via `EmbeddingGenerator`, and inserts records in a single coordinated flow.
- `search(query: String, limit: Int = 10, mode: SearchMode = .hybrid, vectorWeight: Float = 0.5, keywordWeight: Float = 0.5, minSimilarity: Float = 0.0) async throws -> [SearchResultItem]`:
  - Mode `.vector`: Generates query embedding, performs KNN search, filters by `minSimilarity` (`1.0 - distance`), returns results with `matchType = "vector"`.
  - Mode `.keyword`: Executes FTS5 BM25 search, normalizes scores, returns results with `matchType = "keyword"`.
  - Mode `.hybrid`: Executes dense vector and BM25 searches in parallel, then applies **Reciprocal Rank Fusion (RRF)**:
    $$\text{Score}(d) = \frac{w_{\text{vector}}}{60 + \text{rank}_{\text{vector}}(d)} + \frac{w_{\text{keyword}}}{60 + \text{rank}_{\text{keyword}}(d)}$$
    Normalized against theoretical maximum $\frac{w_{\text{vector}}}{61} + \frac{w_{\text{keyword}}}{61}$.
    Pure vector matches below `minSimilarity` are pruned, while keyword/hybrid matches are preserved.

---

### 1.3 `BertTokenizer`

Pure-Swift WordPiece tokenizer compatible with `sentence-transformers/all-MiniLM-L6-v2`.

- **Vocabulary**: 30,522 WordPiece tokens loaded from bundled `vocab.txt`.
- **Special Tokens**:
  - `[PAD]` = ID 0
  - `[UNK]` = ID 100
  - `[CLS]` = ID 101
  - `[SEP]` = ID 102
- **Public API**:
  - `init() throws`: Loads `vocab.txt` from bundle/search paths.
  - `init(vocabURL: URL) throws`: Loads custom vocab file.
  - `init(vocab: [String: Int32])`: In-memory vocab map (test fixture).
  - `tokenize(_ text: String, maxLength: Int = 128) -> TokenizedInput`:
    - Normalizes text: case-insensitive and diacritic-insensitive folding (`en_US`).
    - Basic tokenization: splits on punctuation and whitespace.
    - WordPiece subword segmentation (prefixes continuation subwords with `##`).
    - Produces `inputIDs` prefixed with `[CLS]` (101), content subwords, `[SEP]` (102), and padded to `maxLength` with `[PAD]` (0).
    - Produces `attentionMask` with `1` for active tokens (including `[CLS]` and `[SEP]`) and `0` for padding.
  - `decode(_ tokenIDs: [Int32]) -> String`: Decodes tokens back to text, rejoining `##` subwords.

---

### 1.4 `DocumentReader`

Multi-format text extraction engine for plain text, source code, PDFs, and images.

- **Plain Text Extraction**: Reads text with multi-encoding fallback (`.utf8` $\to$ `.isoLatin1` $\to$ `.windowsCP1252`).
- **PDF Extraction**:
  1. *Fast Path (<1ms)*: Native PDF digital text layer extracted via PDFKit (`page.string`).
  2. *OCR Fallback*: If `page.string` is nil or shorter than 10 characters (indicating a scanned document or rasterized graphic), renders the page at 150 DPI to a CoreGraphics context and runs on-device Vision OCR (`VNRecognizeTextRequest`).
  3. Locked/encrypted PDFs return `nil`.
- **Image Text Extraction (Vision OCR)**:
  - Supported extensions: `png`, `jpg`, `jpeg`, `heic`, `webp`, `tiff`, `bmp`.
  - Directly feeds file URL to `VNImageRequestHandler` to preserve EXIF orientation and minimize memory footprint.
  - Enclosed in `@autoreleasepool` for immediate memory deallocation.
  - 2D Reading-Order Sorting: Observations are clustered into lines by vertical position ($y$ descending) and ordered left-to-right ($x$ ascending).

---

### 1.5 `FileCrawler`

Directory crawler for discovering indexable content while respecting filesystem safety constraints.

- **Cycle Detection**: Canonical path tracking (`resolvingSymlinksInPath().standardizedFileURL.path`) prevents infinite loops across directory symlinks.
- **Depth Guard**: `maxDepth` limit (default 20) stops runaway recursive crawls.
- **Excluded Directories**:
  - System/temp: `__MACOSX`, `.Trash`, `.Spotlight-V100`, `.fseventsd`, `.TemporaryItems`.
  - Version control: `.git`, `.svn`, `.hg`.
  - Dependencies/builds: `node_modules`, `.build`, `venv`, `dist`, `out`, `Pods`, `DerivedData`, `target`.
- **iCloud Dataless Safety**: Checks `ubiquitousItemDownloadingStatus == .notDownloaded` via `isDatalessICloudFile(at:)` to prevent blocking network downloads unless explicitly enabled and permitted by disk buffer checks.

---

## 2. Database Schema Requirements & SQL Contracts

The SQLite database must strictly adhere to the following schema, tables, triggers, and virtual table definitions:

```sql
-- 1. Metadata for tracked files
CREATE TABLE IF NOT EXISTS indexed_files (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    path  TEXT    NOT NULL UNIQUE,
    mtime REAL    NOT NULL,
    size  INTEGER NOT NULL
);

-- 2. Chunk text storage
CREATE TABLE IF NOT EXISTS text_chunks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id     INTEGER NOT NULL REFERENCES indexed_files(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    content     TEXT    NOT NULL
);

-- 3. Virtual vector table (sqlite-vec extension)
CREATE VIRTUAL TABLE IF NOT EXISTS vec_chunks USING vec0(
    chunk_id    INTEGER PRIMARY KEY,
    embedding   float[384] distance_metric=cosine
);

-- 4. Virtual full-text keyword search table (SQLite FTS5)
CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
    file_path,
    content,
    tokenize = 'porter unicode61'
);

-- 5. Trigger: automatically keep FTS index synchronized on chunk insert
CREATE TRIGGER IF NOT EXISTS text_chunks_ai AFTER INSERT ON text_chunks BEGIN
    INSERT INTO documents_fts (rowid, file_path, content)
    SELECT new.id, f.path, new.content
    FROM indexed_files f
    WHERE f.id = new.file_id;
END;

-- 6. Trigger: automatically keep FTS index synchronized on chunk delete
CREATE TRIGGER IF NOT EXISTS text_chunks_ad AFTER DELETE ON text_chunks BEGIN
    DELETE FROM documents_fts WHERE rowid = old.id;
END;
```

### Critical Deletion Invariant
While `text_chunks` defines an `ON DELETE CASCADE` foreign key referencing `indexed_files(id)`, SQLite virtual tables (`vec0` and `fts5`) **do not support foreign key cascade actions**.
Therefore, any deletion of files or chunks **must** explicitly delete entries from `vec_chunks` and `documents_fts` within an atomic transaction:
```sql
DELETE FROM vec_chunks WHERE chunk_id IN (SELECT id FROM text_chunks WHERE file_id = ?);
DELETE FROM documents_fts WHERE rowid IN (SELECT id FROM text_chunks WHERE file_id = ?);
DELETE FROM text_chunks WHERE file_id = ?;
DELETE FROM indexed_files WHERE id = ?;
```

---

## 3. Verification & Parity Test Harnesses

Every refactoring pass must verify adherence to these invariants by executing:

1. **CLI Parity Verification**:
   ```bash
   ./scripts/verify_cli_parity.sh
   ```
   Validates CLI exit codes, command signatures (`index`, `watch`, `search`, `bench`, `stats`, `reset`), `--json` formatting, and error handling.

2. **Chunker Equivalence Suite**:
   ```bash
   swift test --package-path Packages/PrivateIndexEngine --filter TextChunkerEquivalenceTests
   ```
   Ensures grapheme cluster preservation, CJK string windowing, zero-overlap partitioning, and sliding window boundaries remain identical.

3. **Complete Unit & Benchmark Test Suite**:
   ```bash
   xattr -d com.apple.FinderInfo Packages/PrivateIndexEngine/.build/out/Products/Debug/PrivateIndexEngineTests.xctest 2>/dev/null || true
   swift test --package-path Packages/PrivateIndexEngine
   ```
