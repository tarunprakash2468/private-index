# Private Index — Raycast Extension

Search your local documents, notes, code, and PDFs semantically right from [Raycast](https://www.raycast.com/), powered entirely by on-device AI.

<p align="center">
  <img src="assets/extension-icon.png" width="128" height="128" alt="Private Index Raycast Icon" />
</p>

---

## Features

- **⚡ Search-as-you-type**: Instant hybrid semantic + keyword document retrieval in <2ms.
- **🏷️ Rich Visual Indicators**: File type icons, parent directories, match type badges (`[hybrid]`, `[vector]`, `[keyword]`), and confidence percentages (`95% match`).
- **📖 Markdown Detail Pane**: Full text preview in a clean markdown callout alongside metadata (file path, size, modified date, raw score).
- **⌨️ Fast Keyboard Actions**:
  - <kbd>↵</kbd> Open file in default macOS application
  - <kbd>⌘</kbd> <kbd>↵</kbd> Reveal file in Finder
  - <kbd>Space</kbd> macOS Quick Look preview for PDFs, text, and images
  - <kbd>⌘</kbd> <kbd>C</kbd> Copy text snippet to clipboard
  - <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>C</kbd> Copy full file path to clipboard

---

## Prerequisites

The Raycast extension uses the native `pi` CLI binary to perform on-device Core ML and SQLite vector searches.

Install the CLI via Homebrew:
```bash
brew tap tarunprakash2468/private-index https://github.com/tarunprakash2468/private-index
brew install private-index
```

Ensure your documents are indexed:
```bash
# Index your documents folder or run the live watcher
pi index ~/Documents
pi watch
```

---

## Extension Preferences

You can customize the extension via Raycast's Extension Settings (<kbd>⌘</kbd> <kbd>,</kbd>):

| Setting | Type | Default | Description |
|---|---|---|---|
| **Executable Path** | Text | `/opt/homebrew/bin/pi` | Full path to the `pi` CLI binary. |
| **Search Mode** | Dropdown | `hybrid` | Retrieval mode: `hybrid` (Semantic + BM25), `vector` (Semantic embeddings), or `keyword` (FTS5 BM25). |
| **Minimum Similarity** | Text | `35%` | Vector similarity threshold for semantic matches (e.g. `35%` or `0.35`). |
| **Result Limit** | Text | `15` | Maximum number of results to display in Raycast. |

---

## Development & Local Installation

To build and run this extension locally in Raycast:

```bash
# 1. Navigate to extension directory
cd extensions/raycast-private-index

# 2. Install dependencies
npm install

# 3. Build the extension
npm run build

# 4. Start development mode (loads into Raycast)
npm run dev
```
