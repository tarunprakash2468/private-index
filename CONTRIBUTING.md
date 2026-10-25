# Contributing to Private Index

Thank you for your interest in contributing to **Private Index**! This document provides a complete guide to the architecture, developer setup, testing workflows, and engineering standards for the project.

---

## Architecture Overview

Private Index is a zero-cloud, privacy-preserving semantic search engine for macOS (14+) and iOS (17+). It indexes local files and iCloud Drive documents entirely on-device using the Apple Neural Engine (ANE) and an embedded vector-enabled SQLite database.

```
                                 ┌────────────────────────────────┐
                                 │       FileCrawler.swift        │
                                 │ (Filters system/hidden/evicted)│
                                 └───────────────┬────────────────┘
                                                 │ File URLs
                                                 ▼
                                 ┌────────────────────────────────┐
                                 │      DocumentReader.swift      │
                                 │ (Plain text, PDFKit, Vision OCR│
                                 └───────────────┬────────────────┘
                                                 │ Extracted Text
                                                 ▼
                                 ┌────────────────────────────────┐
                                 │       TextChunker.swift        │
                                 │  (500 char window, 100 overlap)│
                                 └───────────────┬────────────────┘
                                                 │ Text Chunks
                                                 ▼
┌───────────────────────────┐    ┌────────────────────────────────┐
│  all-MiniLM-L6-v2 Core ML │    │       VectorStore.swift        │
│ (ANE-optimized, FP16 MIL) ├────►  (SQLite with sqlite-vec ext)  │
│  Outputs (1, 384) L2 norm │    │    Stores text & vec0 virtual  │
└───────────────────────────┘    └────────────────────────────────┘
                                                 ▲
                                                 │
                                 ┌───────────────┴────────────────┐
                                 │      BertTokenizer.swift       │
                                 │ (WordPiece + 30k vocab.txt)    │
                                 └────────────────────────────────┘
```

### Core Components

1. **Embedding Model (`sentence-transformers/all-MiniLM-L6-v2`)**:
   - Converts natural language into 384-dimensional dense vectors.
   - Traced and converted to Core ML (`mlprogram`, FP16) using `scripts/convert_model.py`.
   - **Post-processing is baked into the model graph**: mean pooling (excluding attention padding) and L2 normalization execute directly inside the model graph on the Apple Neural Engine.
2. **Pure-Swift WordPiece Tokenizer (`BertTokenizer.swift`)**:
   - Zero-dependency implementation bundled with `vocab.txt` (30,522 tokens).
   - Handles text normalization, punctuation splitting, subword decomposition (`##` prefix), and `[CLS]`/`[SEP]`/`[PAD]` generation with attention masks.
3. **Vector Storage (`VectorStore.swift`)**:
   - Statically links the official `sqlite-vec.c` amalgamation with Apple's system `libsqlite3`.
   - Uses virtual table `vec0` configured with `distance_metric=cosine`.
   - Queries use `MATCH ? AND k = ?` for KNN similarity searches.
4. **iCloud Loop Prevention (`iCloudContainerManager.swift` / `IOSContainerManager.swift`)**:
   - The database (`index.sqlite`) resides inside the app's sandboxed iCloud Ubiquity Container (`iCloud.com.app.privateindex/Database/`), strictly segregated from user-facing iCloud Drive documents (`~/Library/Mobile Documents/com~apple~CloudDocs/`).
   - Prevents recursive sync loops where database writes trigger iCloud re-indexing.
5. **Dataless File Handling (`FileCrawler.swift`)**:
   - Inspects `URLResourceKey.ubiquitousItemDownloadingStatusKey` to skip evicted (`.notDownloaded`) files, preventing unexpected cloud downloads and network stalls.
6. **Unified Document Reader (`DocumentReader.swift`)**:
   - Decodes plain text, Markdown, and source code files with UTF-8, Latin-1, and CP1252 fallbacks.
   - Parses digital PDFs via Apple `PDFKit` (`page.string`).
   - Integrates on-device OCR fallback via Apple `Vision` (`VNRecognizeTextRequest`) to extract text from scanned or image-only PDF pages without cloud calls.
7. **Orchestrator (`IndexCoordinator.swift`)**:
   - Swift concurrency `actor` coordinating crawling, incremental change detection (skipping unchanged files based on `mtime` and `size`), pruning deleted files, and natural language search.

---

## Repository Layout

```
private-index/
├── README.md                          # User-facing project documentation
├── CONTRIBUTING.md                    # Developer-facing guide (this file)
├── LICENSE                            # MIT License
├── .gitignore                         # Build and OS exclusions
├── .github/
│   └── workflows/
│       └── ci.yml                     # Continuous integration for macOS & iOS
├── scripts/
│   ├── convert_model.py               # PyTorch -> Core ML model conversion
│   └── requirements.txt               # Python dependencies for model export
├── Packages/
│   └── PrivateIndexEngine/            # Core Swift Package
│       ├── Package.swift
│       ├── Sources/
│       │   ├── CSQLiteVec/            # Vendored sqlite-vec amalgamation + header
│       │   ├── PrivateIndexEngine/    # Swift engine implementation
│       │   │   ├── BertTokenizer.swift
│       │   │   ├── EmbeddingGenerator.swift
│       │   │   ├── FileCrawler.swift
│       │   │   ├── IndexCoordinator.swift
│       │   │   ├── TextChunker.swift
│       │   │   ├── VectorStore.swift
│       │   │   └── Resources/
│       │   │       └── vocab.txt      # Bundled BERT vocabulary
│       │   └── private-index-cli/     # Terminal CLI executable
│       │       └── main.swift
│       └── Tests/
│           └── PrivateIndexEngineTests/
│               ├── BertTokenizerTests.swift
│               ├── FileCrawlerTests.swift
│               ├── IndexCoordinatorTests.swift
│               ├── PerformanceBenchmarks.swift
│               ├── TextChunkerTests.swift
│               └── VectorStoreTests.swift
└── Apps/
    ├── macOS/                         # Native macOS 14+ SwiftUI App
    │   ├── Package.swift
    │   └── Sources/PrivateIndexMac/
    └── iOS/                           # Native iOS 17+ SwiftUI App
        ├── Package.swift
        └── Sources/PrivateIndexIOS/
```

---

## Developer Prerequisites

- **Operating System**: macOS 14 (Sonoma) or macOS 15+ (Sequoia) running on Apple Silicon.
- **Xcode**: Xcode 15.0+ or Xcode 16+ with command-line tools installed (`xcode-select --install`).
- **Swift**: Swift 5.10+ / Swift 6.
- **Python (Optional)**: Python 3.9+ (only needed if running the model conversion pipeline in `scripts/`).

---

## Building and Testing

### 1. PrivateIndexEngine Package

Build the engine library:
```bash
cd Packages/PrivateIndexEngine
swift build
```

Run the unit test suite and benchmarks:
```bash
swift test --scratch-path /tmp/private-index-build
```

> **Why `--scratch-path`?**
> When working inside directories synced by iCloud Drive (such as Desktop & Documents), macOS FileProvider may attach extended attributes (`com.apple.FinderInfo`) that cause codesigning rejections on test bundles. Specifying `--scratch-path /tmp/private-index-build` keeps intermediate build artifacts clean and avoids code sign failures.

### 2. Developer CLI (`private-index-cli`)

Build and run the terminal tool:
```bash
cd Packages/PrivateIndexEngine

# View available commands
swift run --scratch-path /tmp/private-index-build private-index-cli help

# Index a folder
swift run --scratch-path /tmp/private-index-build private-index-cli index ~/Documents

# Search documents
swift run --scratch-path /tmp/private-index-build private-index-cli search "machine learning privacy" --limit 5

# View index statistics
swift run --scratch-path /tmp/private-index-build private-index-cli stats

# Reset the database
swift run --scratch-path /tmp/private-index-build private-index-cli reset
```

### 3. macOS Application

Build the native macOS app:
```bash
cd Apps/macOS
swift build --scratch-path /tmp/private-index-mac-build
```

Run the app locally:
```bash
swift run --scratch-path /tmp/private-index-mac-build PrivateIndexMac
```

### 4. iOS Application

Build the iOS app target against the iOS 17 Simulator SDK:
```bash
cd Apps/iOS
swift build --triple arm64-apple-ios17.0-simulator --scratch-path /tmp/private-index-ios-build
```

---

## Core ML Model Conversion Pipeline

The Core ML model conversion script is located in `scripts/convert_model.py`.

To convert or update the `all-MiniLM-L6-v2` Core ML model:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt

# Convert to FP16 ANE-optimized .mlpackage and export vocab.txt
python3 scripts/convert_model.py --output all-MiniLM-L6-v2.mlpackage --verify
```

The script:
1. Loads `sentence-transformers/all-MiniLM-L6-v2`.
2. Wraps the model in `SentenceTransformerWrapper` with baked mean-pooling and L2 normalization.
3. Traces the model with fixed static input shapes `(1, 128)` for ANE optimization.
4. Exports `all-MiniLM-L6-v2.mlpackage` and copies `vocab.txt` into the engine's resources.
5. Verifies output shapes `(1, 384)`, unit L2 norm, and cosine similarity with PyTorch (≥ 0.99).

---

## Performance Benchmarks

The benchmark suite in `PerformanceBenchmarks.swift` verifies that Private Index maintains high performance:

| Benchmark | Target Metric | Typical Apple Silicon Result |
|---|---|---|
| **Vector Insertion Throughput** | > 20,000 vec/s | **~68,500 vectors/sec** |
| **Search Query Latency (1K vectors)** | < 10 ms | **~1.8 ms to 2.0 ms** |
| **WordPiece Tokenization (100 sentences)** | < 25 ms | **~7 ms** |
| **Character Sliding Chunking (120k chars)** | < 30 ms | **~9 ms** |

Run benchmarks:
```bash
cd Packages/PrivateIndexEngine
swift test --filter PerformanceBenchmarks --scratch-path /tmp/private-index-build
```

---

## Database Schema Reference

The database uses SQLite with the `sqlite-vec` extension:

```sql
-- Tracked source file metadata
CREATE TABLE indexed_files (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    path  TEXT    NOT NULL UNIQUE,
    mtime REAL    NOT NULL,
    size  INTEGER NOT NULL
);

-- Text chunks with foreign key cascade
CREATE TABLE text_chunks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    file_id     INTEGER NOT NULL REFERENCES indexed_files(id) ON DELETE CASCADE,
    chunk_index INTEGER NOT NULL,
    content     TEXT    NOT NULL
);

-- Virtual table for cosine vector search
CREATE VIRTUAL TABLE vec_chunks USING vec0(
    chunk_id    INTEGER PRIMARY KEY,
    embedding   float[384] distance_metric=cosine
);
```

KNN query syntax:
```sql
SELECT vc.chunk_id, f.id, f.path, vc.distance, tc.content
FROM vec_chunks vc
JOIN text_chunks tc ON tc.id = vc.chunk_id
JOIN indexed_files f ON f.id = tc.file_id
WHERE vc.embedding MATCH ? AND k = ?
ORDER BY vc.distance;
```

---

## Contribution Workflow

We welcome contributions! Please follow these guidelines:

1. **Fork & Branch**: Create a descriptive branch from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
2. **Follow Coding Standards**:
   - Write clean, idiomatic Swift adhering to Swift 5.10 / Swift 6 concurrency rules.
   - Keep APIs documented with docstrings (`///`).
   - Preserve zero external third-party dependencies in `PrivateIndexEngine`.
3. **Add Tests**:
   - Any new functionality must be accompanied by XCTest unit tests in `Tests/PrivateIndexEngineTests/`.
   - Ensure all 37+ existing tests continue to pass with `swift test`.
4. **Commit Messages**:
   - Follow the **Conventional Commits** specification: `<type>: <description>`.
   - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`.
   - Keep the first line under 50 characters.
5. **Open a Pull Request**:
   - Ensure CI checks pass on GitHub Actions.
   - Describe what changed and include test verification results.
