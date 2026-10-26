<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Private Index App Icon" />
</p>

# Private Index

> **Zero-cloud, privacy-preserving semantic search for macOS and iOS.**  
> Find documents and notes by *meaning*, entirely on-device, with the speed of the Apple Neural Engine.

---

## What is Private Index?

Traditional search engines rely on exact keyword matches or upload your personal documents to cloud servers to run machine learning models. 

**Private Index** changes that:
- **Hybrid Search**: Combines semantic embeddings with SQLite FTS5 BM25 keyword search using Reciprocal Rank Fusion (RRF) to retrieve both conceptual matches and exact symbols (UUIDs, error codes, function names).
- **Search by Meaning**: Find documents by describing what you remember ("recipes with rosemary and garlic", "rust error handling patterns", "tax deduction notes 2024") without needing exact filenames or keywords.
- **100% On-Device AI**: Powered by Apple Neural Engine (ANE) acceleration. Your documents, embeddings, and search queries never leave your Mac or iPhone.
- **Zero Cloud & Air-Gapped**: Works completely offline. No tracking, no telemetry, no subscriptions, no accounts.
- **Seamless iCloud Integration**: Automatically indexes your iCloud Drive documents with built-in sync loop protection.

---

## Platforms & Features

### 🖥️ macOS Experience (macOS 14+ Sonoma & Sequoia)

- **Spotlight-Style Search HUD**: Press `⌘ + Shift + Space` anywhere to bring up a floating glassmorphic search panel.
- **Keystroke Search**: Real-time semantic retrieval in under 2 milliseconds.
- **Semantic Match Indicators**: Visual match pills (`98% match`, `85% match`) show you how closely each document relates to your query.
- **Quick Actions**: Tap `↵` to immediately open a file, or `⌘↵` to reveal it in Finder.
- **Menu Bar Companion**: Fast access to indexing status, manual scan triggers, and settings right from your menu bar.
- **Automatic Background Sync**: Live file system watcher updates the index automatically whenever you save, edit, or delete documents.

### 📱 iOS Experience (iOS 17+)

- **Modern Touch-First Design**: Multi-tab interface featuring dedicated Search, Documents, and Settings views.
- **QuickLook File Previews**: Tap any search result to preview documents immediately with native iOS QuickLook without switching apps.
- **Files App Integration**: Select any iCloud Drive or local folder to index using native iOS document pickers with persistent security-scoped access.
- **Mobile-Optimized Indexing**: Intelligent background scheduling prevents thermal throttling and saves battery life.

### ⚡ Developer Terminal CLI (`pi`)

Prefer the terminal? Install Private Index CLI via Homebrew:

```bash
# Tap repository and install
brew tap tarunprakash2468/private-index https://github.com/tarunprakash2468/private-index
brew install private-index
```

Run commands with the sleek **`pi`** shorthand (or `private-index`):

```bash
# Index a directory
pi index ~/Documents

# Live folder watching daemon (2.0s debounce & sleep protection)
pi watch ~/Documents

# Run headlessly 24/7 on login via macOS launchd LaunchAgent
pi watch --install-launchagent ~/Documents

# Search documents using Hybrid Search (default: Core ML vector + FTS5 BM25 with RRF)
pi search "zero-cloud privacy architecture" --limit 5

# Search with specific mode: hybrid, vector, or keyword
pi search "ERR_AUTH_TOKEN_401" --mode keyword
pi search "neural network acceleration" --mode vector
pi search "on-device inference" --mode hybrid --vector-weight 0.7 --keyword-weight 0.3

# Check index statistics
pi stats
```

*Tab autocompletions for **Zsh**, **Bash**, and **Fish** are automatically configured when installed via Homebrew.*

---

## Supported File Formats

Private Index indexes over 30 plain-text, markdown, and code formats:

| Category | Extensions |
|---|---|
| **Documents & PDFs** | `.pdf` (Digital PDFs via `PDFKit` + Scanned/Image-Only PDFs via native Apple `Vision` OCR) |
| **Notes & Text** | `.txt`, `.text`, `.md`, `.markdown`, `.mdown`, `.mkd`, `.adoc`, `.rst`, `.tex` |
| **Code & Scripts** | `.swift`, `.py`, `.js`, `.ts`, `.jsx`, `.tsx`, `.c`, `.h`, `.cpp`, `.rs`, `.go`, `.java`, `.kt`, `.rb`, `.sh`, `.zsh`, `.bash`, `.lua`, `.sql` |
| **Config & Data** | `.json`, `.yaml`, `.yml`, `.toml`, `.csv`, `.tsv`, `.ini`, `.cfg`, `.conf`, `.plist`, `.env`, `.xml`, `.html`, `.css` |

---

## Privacy & Security Guarantee

1. **Strictly Air-Gapped**: Private Index contains zero networking code for search and inference.
2. **Ubiquity Isolation**: The search database (`index.sqlite`) resides in the app's sandboxed iCloud Ubiquity Container (`iCloud.com.app.privateindex/Database/`), physically separated from your document files to prevent circular sync loops.
3. **Dataless File Protection**: Uses Apple's file system attributes to detect iCloud evicted files (`.notDownloaded`) and skips them, ensuring the app never triggers unwanted cellular data or battery drain.

---

## Quick Start

### macOS Application

```bash
cd Apps/macOS
swift run PrivateIndexMac
```

- Press `⌘ + Shift + Space` to summon the search window.
- Open **Settings** to choose which folder to index (defaults to your personal iCloud Drive Documents).

### Developer CLI (`pi`)

```bash
# Install via Homebrew
brew tap tarunprakash2468/private-index https://github.com/tarunprakash2468/private-index
brew install private-index

# Benchmark on-device performance
pi bench
pi bench --vectors 5000 --json

# Or run from source
cd Packages/PrivateIndexEngine
swift run private-index-cli help
```

---

## Developers & Contributors

Interested in the technical architecture, Core ML conversion pipeline, SQLite vector virtual tables, or contributing code?

👉 **See our comprehensive [CONTRIBUTING.md](CONTRIBUTING.md) guide** for:
- Architecture diagrams & data flow deep-dives
- Building and testing `PrivateIndexEngine`
- Running performance benchmarks (68k+ vectors/sec insertion, ~2ms search latency)
- Coding standards and Pull Request instructions

---

## License

This project is open-source software licensed under the [MIT License](LICENSE).