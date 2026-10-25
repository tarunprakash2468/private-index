import Foundation
import PrivateIndexEngine

// MARK: - CLI Colors

enum ANSI {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let green = "\u{001B}[32m"
    static let cyan = "\u{001B}[36m"
    static let yellow = "\u{001B}[33m"
    static let red = "\u{001B}[31m"
}

// MARK: - CLI Engine Setup

func defaultDatabaseURL() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent(".private-index", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("index.sqlite")
}

func setupEngine() throws -> (VectorStore, IndexCoordinator) {
    let dbURL = defaultDatabaseURL()
    let store = try VectorStore(at: dbURL)
    try store.createSchema()

    let tokenizer: BertTokenizer
    if let t = try? BertTokenizer() {
        tokenizer = t
    } else {
        tokenizer = BertTokenizer(vocab: [:])
    }

    // Check for compiled Core ML model or fallback to MockEmbeddingModel
    let model: EmbeddingGenerator
    if let modelURL = Bundle.main.url(forResource: "all-MiniLM-L6-v2", withExtension: "mlmodelc"),
       let coreML = try? CoreMLEmbeddingModel(modelURL: modelURL, tokenizer: tokenizer) {
        model = coreML
    } else {
        model = MockEmbeddingModel()
    }

    let coordinator = IndexCoordinator(
        vectorStore: store,
        fileCrawler: FileCrawler(),
        textChunker: TextChunker(windowSize: 500, overlap: 100),
        embeddingModel: model
    )

    return (store, coordinator)
}

// MARK: - Commands

func printHelp() {
    print("""
    \(ANSI.bold)\(ANSI.cyan)pi\(ANSI.reset) — Private Index: On-Device Semantic Search Engine

    \(ANSI.bold)USAGE:\(ANSI.reset)
        pi <command> [arguments]
        private-index <command> [arguments]

    \(ANSI.bold)COMMANDS:\(ANSI.reset)
        \(ANSI.green)index\(ANSI.reset) <path>            Index documents in the specified directory
        \(ANSI.green)search\(ANSI.reset) <query> [--limit N]  Run semantic similarity search for a query
        \(ANSI.green)stats\(ANSI.reset)                   Show database stats and indexed document counts
        \(ANSI.green)reset\(ANSI.reset)                   Clear database and purge all vector embeddings
        \(ANSI.green)help\(ANSI.reset)                    Display this help message

    \(ANSI.bold)EXAMPLES:\(ANSI.reset)
        pi index ~/Documents
        pi search "zero-cloud privacy architecture" --limit 5
        pi stats
    """)
}

func runIndex(path: String) async throws {
    let expandedPath = (path as NSString).expandingTildeInPath
    let folderURL = URL(fileURLWithPath: expandedPath)

    guard FileManager.default.fileExists(atPath: folderURL.path) else {
        print("\(ANSI.red)Error:\(ANSI.reset) Directory '\(path)' does not exist.")
        exit(1)
    }

    print("\(ANSI.bold)Scanning & indexing:\(ANSI.reset) \(ANSI.dim)\(folderURL.path)\(ANSI.reset)")
    let (_, coordinator) = try setupEngine()

    let report = try await coordinator.index(directoryURL: folderURL) { progress, message in
        let pct = Int(progress * 100)
        let bar = String(repeating: "█", count: pct / 5) + String(repeating: "░", count: 20 - (pct / 5))
        print("\r\(ANSI.cyan)[\(bar)] \(pct)%\(ANSI.reset) \(ANSI.dim)\(message)\(ANSI.reset)", terminator: "")
        fflush(stdout)
    }

    print("\n")
    print("\(ANSI.green)✔ Indexing completed successfully!\(ANSI.reset)")
    print("""
      • Files scanned:   \(report.filesScanned)
      • Files indexed:   \(report.filesIndexed)
      • Files skipped:   \(report.filesSkipped) (unchanged)
      • Files deleted:   \(report.filesDeleted)
      • Chunks indexed:  \(report.chunksIndexed)
      • Time elapsed:    \(String(format: "%.2f", report.duration))s
    """)
}

func runSearch(query: String, limit: Int) async throws {
    print("\(ANSI.bold)Query:\(ANSI.reset) \"\(query)\" \(ANSI.dim)(limit: \(limit))\(ANSI.reset)\n")
    let (_, coordinator) = try setupEngine()

    let startTime = Date()
    let results = try await coordinator.search(query: query, limit: limit)
    let elapsed = Date().timeIntervalSince(startTime) * 1000

    if results.isEmpty {
        print("\(ANSI.yellow)No semantic matches found.\(ANSI.reset) Have you indexed any documents?")
        return
    }

    print("\(ANSI.cyan)Found \(results.count) results in \(String(format: "%.1f", elapsed))ms:\(ANSI.reset)\n")

    for (idx, r) in results.enumerated() {
        let pct = Int(r.score * 100)
        let scoreColor = pct >= 85 ? ANSI.green : (pct >= 70 ? ANSI.cyan : ANSI.dim)
        let fileName = URL(fileURLWithPath: r.filePath).lastPathComponent

        print("\(ANSI.bold)\(idx + 1). \(fileName)\(ANSI.reset)  [\(scoreColor)\(pct)% match\(ANSI.reset)]")
        print("   \(ANSI.dim)\(r.filePath)\(ANSI.reset)")

        // Snippet indented
        let snippet = r.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = snippet.count > 160 ? String(snippet.prefix(160)) + "..." : snippet
        print("   \(preview)\n")
    }
}

func runStats() throws {
    let dbURL = defaultDatabaseURL()
    let (store, _) = try setupEngine()

    let allFiles = try store.getAllIndexedFiles()

    var sizeStr = "0 KB"
    if let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
       let size = attrs[.size] as? Int64 {
        sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    print("""
    \(ANSI.bold)\(ANSI.cyan)Private Index Database Statistics\(ANSI.reset)
      • Database path:  \(ANSI.dim)\(dbURL.path)\(ANSI.reset)
      • Database size:  \(sizeStr)
      • Indexed files:  \(allFiles.count)
      • Dimensions:     384 (Cosine Distance)
    """)
}

func runReset() throws {
    let dbURL = defaultDatabaseURL()
    if FileManager.default.fileExists(atPath: dbURL.path) {
        try FileManager.default.removeItem(at: dbURL)
        print("\(ANSI.green)✔ Database cleared successfully.\(ANSI.reset)")
    } else {
        print("Database is already empty.")
    }
}

// MARK: - Entry Point

let args = CommandLine.arguments

guard args.count > 1 else {
    printHelp()
    exit(0)
}

let command = args[1].lowercased()

switch command {
case "index":
    guard args.count > 2 else {
        print("\(ANSI.red)Error:\(ANSI.reset) Please specify a path to index. e.g. `private-index-cli index ~/Documents`")
        exit(1)
    }
    let targetPath = args[2]
    Task {
        do {
            try await runIndex(path: targetPath)
            exit(0)
        } catch {
            print("\(ANSI.red)Indexing error:\(ANSI.reset) \(error.localizedDescription)")
            exit(1)
        }
    }
    RunLoop.main.run()

case "search":
    guard args.count > 2 else {
        print("\(ANSI.red)Error:\(ANSI.reset) Please specify a search query. e.g. `private-index-cli search \"privacy machine learning\"`")
        exit(1)
    }

    var limit = 10
    var queryTerms: [String] = []

    var i = 2
    while i < args.count {
        if args[i] == "--limit", i + 1 < args.count, let parsedLimit = Int(args[i + 1]) {
            limit = parsedLimit
            i += 2
        } else {
            queryTerms.append(args[i])
            i += 1
        }
    }

    let query = queryTerms.joined(separator: " ")
    let searchLimit = limit

    Task {
        do {
            try await runSearch(query: query, limit: searchLimit)
            exit(0)
        } catch {
            print("\(ANSI.red)Search error:\(ANSI.reset) \(error.localizedDescription)")
            exit(1)
        }
    }
    RunLoop.main.run()

case "stats":
    do {
        try runStats()
    } catch {
        print("\(ANSI.red)Error:\(ANSI.reset) \(error.localizedDescription)")
        exit(1)
    }

case "reset":
    do {
        try runReset()
    } catch {
        print("\(ANSI.red)Error:\(ANSI.reset) \(error.localizedDescription)")
        exit(1)
    }

case "help", "-h", "--help":
    printHelp()

default:
    print("\(ANSI.red)Unknown command:\(ANSI.reset) '\(command)'. Run `private-index-cli help` for usage.")
    exit(1)
}
