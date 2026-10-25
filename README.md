# Private Index

A zero-cloud, privacy-preserving semantic search engine for macOS (14+) and iOS (17+) that indexes local and iCloud Drive documents entirely on-device using Apple Neural Engine (ANE) acceleration and SQLite vector search.

---

## Architecture Overview

```
                                 ┌────────────────────────────────┐
                                 │       FileCrawler.swift        │
                                 │ (Filters system/hidden/evicted)│
                                 └───────────────┬────────────────┘
                                                 │ File URLs
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
```

1. **Embedding Model**: `sentence-transformers/all-MiniLM-L6-v2` (384-dimensional dense vectors), converted to an FP16 Core ML `.mlpackage` targeting the Apple Neural Engine. Mean-pooling and L2 normalization are baked directly into the model graph.
2. **Vector Storage**: SQLite embedded storage using the official `sqlite-vec` C extension compiled statically (`vec0` virtual table, cosine distance metric).
3. **iCloud Isolation**: The database (`index.sqlite`) resides inside the app's sandboxed iCloud Ubiquity Container (`iCloud.com.app.privateindex`), strictly segregated from user-facing iCloud Drive folders to prevent sync loops.
4. **Ingestion & Chunking**: Sliding-window chunker with 500-character windows and 100-character overlaps.
5. **Dataless File Handling**: Uses `URLResourceKey.ubiquitousItemDownloadingStatusKey` to skip evicted (`.notDownloaded`) files, avoiding unexpected network bandwidth and cloud fetch latency.

---

## Repository Layout

```
private-index/
├── .gitignore
├── LICENSE
├── README.md
├── scripts/
│   ├── convert_model.py       # PyTorch -> Core ML (MIL + mean pool + L2 norm)
│   └── requirements.txt      # Python dependencies for model export
├── Packages/
│   └── PrivateIndexEngine/   # Core Swift Package
│       ├── Package.swift
│       ├── Sources/
│       │   ├── CSQLiteVec/   # Vendored sqlite-vec amalgamation + header
│       │   └── PrivateIndexEngine/
│       │       ├── VectorStore.swift
│       │       ├── TextChunker.swift
│       │       └── FileCrawler.swift
│       └── Tests/
│           └── PrivateIndexEngineTests/
│               ├── FileCrawlerTests.swift
│               ├── TextChunkerTests.swift
│               └── VectorStoreTests.swift
└── Apps/
    ├── macOS/                # Future macOS App Target
    └── iOS/                  # Future iOS App Target
```

---

## Building and Testing

### Swift Package

```bash
cd Packages/PrivateIndexEngine

# Build package
swift build

# Run unit tests
swift test --scratch-path /tmp/private-index-build
```

> **Note**: Building inside directories managed by iCloud Drive (such as Desktop & Documents) may attach macOS FileProvider metadata (`com.apple.FinderInfo`) to debug bundles. Specifying `--scratch-path /tmp/private-index-build` ensures clean codesigning.

### Core ML Conversion Pipeline

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt

# Convert sentence-transformers/all-MiniLM-L6-v2 to Core ML
python3 scripts/convert_model.py --output all-MiniLM-L6-v2.mlpackage
```

---

## License

MIT