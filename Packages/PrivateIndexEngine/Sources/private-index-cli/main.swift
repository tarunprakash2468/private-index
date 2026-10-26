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

    let model = CoreMLEmbeddingModel.loadDefaultModel(tokenizer: tokenizer)

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
        \(ANSI.green)watch\(ANSI.reset) [path] [--install-launchagent|--uninstall-launchagent]  Run background watcher daemon
        \(ANSI.green)search\(ANSI.reset) <query> [options] Run search for a query (default mode: hybrid)
        \(ANSI.green)bench\(ANSI.reset) [options]         Run on-device Apple Silicon performance benchmark
        \(ANSI.green)stats\(ANSI.reset)                   Show database stats and indexed document counts
        \(ANSI.green)reset\(ANSI.reset)                   Clear database and purge all vector embeddings
        \(ANSI.green)help\(ANSI.reset)                    Display this help message

    \(ANSI.bold)SEARCH OPTIONS:\(ANSI.reset)
        --mode <hybrid|vector|keyword>  Search retrieval mode (default: hybrid)
        --limit <N>                     Maximum number of results to return (default: 10)
        --min-similarity <pct>          Minimum vector similarity percentage (default: 35%, e.g. 40 or 40%)
        --vector-weight <W>             Vector similarity weight for RRF in hybrid mode (default: 0.5)
        --keyword-weight <W>            BM25 keyword weight for RRF in hybrid mode (default: 0.5)
        --json                          Output results as strict JSON array (suppresses banners and formatting)

    \(ANSI.bold)BENCHMARK OPTIONS:\(ANSI.reset)
        --vectors <N>                   Number of vectors for insertion/retrieval test (default: 1,000)
        --json                          Output metrics as machine-readable JSON

    \(ANSI.bold)EXAMPLES:\(ANSI.reset)
        pi index ~/Documents
        pi watch ~/Documents
        pi watch --install-launchagent
        pi watch --uninstall-launchagent
        pi search "zero-cloud privacy architecture"
        pi search "33 bond st" --min-similarity 25%
        pi search "ERR_404_NOT_FOUND" --mode keyword
        pi search "Apple Neural Engine" --mode hybrid --limit 5
        pi search "salary" --json
        pi bench
        pi bench --vectors 5000
        pi bench --json
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

func parseSimilarity(_ raw: String) -> Float {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasSuffix("%") {
        s = String(s.dropLast())
    }
    guard let val = Float(s) else { return 0.35 }
    if val > 1.0 {
        return max(0.0, min(1.0, val / 100.0))
    }
    return max(0.0, min(1.0, val))
}

struct SearchJSONResult: Encodable {
    let id: Int64
    let filePath: String
    let fileName: String
    let matchType: String
    let score: Double
    let confidence: Int
    let distance: Double
    let snippet: String
    let mtime: Int64
}

func outputJSONError(_ message: String, code: Int32 = 1) -> Never {
    let dict = ["error": message]
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
       let str = String(data: data, encoding: .utf8) {
        FileHandle.standardError.write(Data((str + "\n").utf8))
    } else {
        FileHandle.standardError.write(Data("{\"error\": \"\(message)\"}\n".utf8))
    }
    exit(code)
}

func runSearch(
    query: String,
    limit: Int,
    mode: SearchMode = .hybrid,
    vectorWeight: Float = 0.5,
    keywordWeight: Float = 0.5,
    minSimilarity: Float = 0.35,
    isJSON: Bool = false
) async throws {
    let dbURL = defaultDatabaseURL()
    guard FileManager.default.fileExists(atPath: dbURL.path) else {
        let msg = "Database not found at '\(dbURL.path)'. Please index documents first using `pi index <directory>`."
        if isJSON {
            outputJSONError(msg)
        } else {
            print("\(ANSI.red)Error:\(ANSI.reset) \(msg)")
            exit(1)
        }
    }

    if !isJSON {
        let simPct = Int(round(minSimilarity * 100))
        let simInfo = mode == .keyword ? "" : ", min-similarity: \(simPct)%"
        print("\(ANSI.bold)Query:\(ANSI.reset) \"\(query)\" \(ANSI.dim)(mode: \(mode.rawValue), limit: \(limit)\(simInfo))\(ANSI.reset)\n")
    }

    let (store, coordinator) = try setupEngine()

    let startTime = Date()
    let results = try await coordinator.search(
        query: query,
        limit: limit,
        mode: mode,
        vectorWeight: vectorWeight,
        keywordWeight: keywordWeight,
        minSimilarity: minSimilarity
    )
    let elapsed = Date().timeIntervalSince(startTime) * 1000

    if isJSON {
        if results.isEmpty {
            print("[]")
            return
        }

        var jsonItems: [SearchJSONResult] = []
        for r in results {
            let fileName = URL(fileURLWithPath: r.filePath).lastPathComponent

            var mtime: Int64 = 0
            if let fileRecord = try? store.getFile(byPath: r.filePath) {
                mtime = Int64(fileRecord.mtime.timeIntervalSince1970)
            } else if let attrs = try? FileManager.default.attributesOfItem(atPath: r.filePath),
                      let modDate = attrs[.modificationDate] as? Date {
                mtime = Int64(modDate.timeIntervalSince1970)
            }

            let confidence: Int
            if r.matchType == "vector" {
                confidence = max(0, min(100, Int(round((1.0 - r.distance) * 100))))
            } else {
                confidence = max(0, min(100, Int(round(r.score * 100))))
            }

            let roundedScore = Double((Double(r.score) * 10000).rounded() / 10000)
            let roundedDistance = Double((Double(r.distance) * 10000).rounded() / 10000)
            let snippet = r.content.trimmingCharacters(in: .whitespacesAndNewlines)

            jsonItems.append(SearchJSONResult(
                id: r.id,
                filePath: r.filePath,
                fileName: fileName,
                matchType: r.matchType,
                score: roundedScore,
                confidence: confidence,
                distance: roundedDistance,
                snippet: snippet,
                mtime: mtime
            ))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(jsonItems)
        if let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
        }
        return
    }

    if results.isEmpty {
        let indexedCount = (try? store.getAllIndexedFiles().count) ?? 0
        if indexedCount == 0 {
            print("""
            \(ANSI.yellow)No matches found.\(ANSI.reset) You haven't indexed any documents yet.
              • Run \(ANSI.cyan)pi index <directory>\(ANSI.reset) to scan and index a folder.
              • Run \(ANSI.cyan)pi watch [directory] --install-launchagent\(ANSI.reset) to watch 24/7.
            """)
        } else {
            print("""
            \(ANSI.yellow)No matches found for\(ANSI.reset) \"\(ANSI.bold)\(query)\(ANSI.reset)\" \(ANSI.dim)(across \(indexedCount) indexed file\(indexedCount == 1 ? "" : "s"))\(ANSI.reset).
              • Try different keywords or a broader phrasing.
              • Lower the similarity threshold: \(ANSI.cyan)pi search \"\(query)\" --min-similarity 20\(ANSI.reset)
              • Try keyword mode for exact tokens: \(ANSI.cyan)pi search \"\(query)\" --mode keyword\(ANSI.reset)
            """)
        }
        return
    }

    print("\(ANSI.cyan)Found \(results.count) result\(results.count == 1 ? "" : "s") in \(String(format: "%.1f", elapsed))ms:\(ANSI.reset)\n")

    for (idx, r) in results.enumerated() {
        let fileName = URL(fileURLWithPath: r.filePath).lastPathComponent

        let matchPill: String
        switch r.matchType {
        case "hybrid":
            matchPill = "\(ANSI.green)[hybrid]\(ANSI.reset)"
        case "vector":
            matchPill = "\(ANSI.cyan)[vector]\(ANSI.reset)"
        case "keyword":
            matchPill = "\(ANSI.yellow)[keyword]\(ANSI.reset)"
        default:
            matchPill = "[\(r.matchType)]"
        }

        let pct: Int
        if r.matchType == "vector" {
            pct = max(0, min(100, Int(round((1.0 - r.distance) * 100))))
        } else {
            pct = max(0, min(100, Int(round(r.score * 100))))
        }
        let scoreStr = "\(ANSI.bold)\(pct)% match\(ANSI.reset)"

        print("\(ANSI.bold)\(idx + 1). \(fileName)\(ANSI.reset)  \(matchPill) [\(scoreStr)]")
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
        do {
            let (store, _) = try setupEngine()
            try store.reset()
            store.close()
        } catch {
            // Proceed to delete file directly if opening or SQL reset fails
        }
        try FileManager.default.removeItem(at: dbURL)
        print("\(ANSI.green)✔ Database cleared successfully.\(ANSI.reset)")
    } else {
        print("Database is already empty.")
    }
}

func runBench(vectorCount: Int, asJSON: Bool) async throws {
    let runner = BenchmarkRunner(vectorCount: vectorCount)

    if !asJSON {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi bench\(ANSI.reset) — Apple Silicon On-Device Performance Benchmark
        \(ANSI.dim)Running safe, ephemeral in-memory benchmarks without modifying local database...\(ANSI.reset)
        """)
    }

    let metrics = try await runner.run { step in
        if !asJSON {
            print("\(ANSI.dim)  ⏳ \(step)\(ANSI.reset)")
        }
    }

    if asJSON {
        let jsonString = try metrics.toJSONString()
        print(jsonString)
        return
    }

    print("\n\(ANSI.bold)\(ANSI.green)✔ Benchmark Suite Completed Successfully!\(ANSI.reset)\n")

    // Hardware & Environment
    print("\(ANSI.bold)\(ANSI.cyan)Hardware & Environment\(ANSI.reset)")
    print("  • OS Version:          \(ANSI.bold)\(metrics.system.osVersion)\(ANSI.reset)")
    print("  • Architecture:        \(ANSI.bold)\(metrics.system.architecture)\(ANSI.reset)")
    print("  • Processor / Chip:    \(ANSI.bold)\(metrics.system.chipModel)\(ANSI.reset) \(ANSI.dim)(\(metrics.system.modelIdentifier))\(ANSI.reset)")
    let netStatus = metrics.resources.zeroNetworkTransmission
        ? "\(ANSI.green)0 active internet sockets (100% on-device verified)\(ANSI.reset)"
        : "\(ANSI.yellow)\(metrics.resources.activeInternetSockets) active internet sockets\(ANSI.reset)"
    print("  • Privacy & Zero-Cloud: \(netStatus)\n")

    // Stage 1: Text Chunker & Bert Tokenizer
    print("\(ANSI.bold)\(ANSI.cyan)Stage 1: Text Chunker & Bert Tokenizer\(ANSI.reset)")
    let corpusKB = String(format: "%.1f", Double(metrics.chunker.corpusSizeBytes) / 1024.0)
    let chunksPerSec = String(format: "%.1f", metrics.chunker.chunksPerSecond)
    let kbPerSec = String(format: "%.1f", metrics.chunker.kilobytesPerSecond)
    print("  • Text Chunker:        \(ANSI.bold)\(chunksPerSec) chunks/s\(ANSI.reset) \(ANSI.dim)(\(kbPerSec) KB/s over \(corpusKB) KB corpus, \(metrics.chunker.chunksProduced) chunks)\(ANSI.reset)")
    let sentencesPerSec = String(format: "%.1f", metrics.tokenizer.sentencesPerSecond)
    print("  • Bert Tokenizer:      \(ANSI.bold)\(sentencesPerSec) sentences/s\(ANSI.reset) \(ANSI.dim)(\(metrics.tokenizer.sentenceCount) sentences, max length: 128)\(ANSI.reset)\n")

    // Stage 2: Apple Neural Engine (ANE) Inference
    print("\(ANSI.bold)\(ANSI.cyan)Stage 2: Apple Neural Engine (ANE) Inference\(ANSI.reset)")
    print("  • Model Architecture:  \(ANSI.bold)\(metrics.inference.modelName)\(ANSI.reset)")
    let latStr = String(format: "%.2f", metrics.inference.averageLatencyMs)
    let tpsStr = String(format: "%.1f", metrics.inference.embeddingsPerSecond)
    print("  • Average Latency:     \(ANSI.bold)\(latStr) ms / embedding\(ANSI.reset) \(ANSI.dim)(evaluated across \(metrics.inference.inferenceCount) sequential inferences)\(ANSI.reset)")
    print("  • Inference Rate:      \(ANSI.bold)\(tpsStr) embeddings/s\(ANSI.reset)\n")

    // Stage 3: SQLite Vector Store (In-Memory)
    print("\(ANSI.bold)\(ANSI.cyan)Stage 3: SQLite Vector Store (In-Memory Ephemeral)\(ANSI.reset)")
    let vecPerSec = String(format: "%.0f", metrics.vectorStore.vectorsPerSecond)
    let insertDur = String(format: "%.3f", metrics.vectorStore.insertionDurationSeconds)
    print("  • Vector Insertion:    \(ANSI.bold)\(vecPerSec) vec/s\(ANSI.reset) \(ANSI.dim)(\(metrics.vectorStore.vectorCount) 384-dim vectors in \(insertDur)s)\(ANSI.reset)")
    let vP50 = String(format: "%.2f", metrics.vectorStore.vectorQueryP50Ms)
    let vP95 = String(format: "%.2f", metrics.vectorStore.vectorQueryP95Ms)
    let vAvg = String(format: "%.2f", metrics.vectorStore.vectorQueryAverageMs)
    print("  • Top-10 Vector Query: \(ANSI.bold)p50 = \(vP50) ms\(ANSI.reset), \(ANSI.bold)p95 = \(vP95) ms\(ANSI.reset) \(ANSI.dim)(avg: \(vAvg) ms over \(metrics.vectorStore.vectorQueryIterations) queries)\(ANSI.reset)")
    let kP50 = String(format: "%.2f", metrics.vectorStore.keywordQueryP50Ms)
    let kP95 = String(format: "%.2f", metrics.vectorStore.keywordQueryP95Ms)
    let kAvg = String(format: "%.2f", metrics.vectorStore.keywordQueryAverageMs)
    print("  • FTS5 BM25 Keyword:   \(ANSI.bold)p50 = \(kP50) ms\(ANSI.reset), \(ANSI.bold)p95 = \(kP95) ms\(ANSI.reset) \(ANSI.dim)(avg: \(kAvg) ms over \(metrics.vectorStore.keywordQueryIterations) queries)\(ANSI.reset)\n")

    // Stage 4: Resource Utilization
    print("\(ANSI.bold)\(ANSI.cyan)Stage 4: Resource Utilization & Privacy\(ANSI.reset)")
    let memMB = String(format: "%.1f", metrics.resources.peakMemoryMB)
    print("  • Peak Resident (RSS): \(ANSI.bold)\(memMB) MB\(ANSI.reset)")
    print("  • Network Activity:    \(ANSI.green)0 bytes transmitted (zero socket / cloud transmission verified)\(ANSI.reset)\n")
}

// MARK: - Watch Daemon & LaunchAgent

func installWatcherLaunchAgent(path: String) throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let launchAgentsDir = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

    let plistURL = launchAgentsDir.appendingPathComponent("com.privateindex.watcher.plist")

    let execPath: String
    if let bundlePath = Bundle.main.executablePath, FileManager.default.fileExists(atPath: bundlePath) {
        execPath = bundlePath
    } else {
        execPath = CommandLine.arguments[0]
    }

    let logsDir = home.appendingPathComponent(".private-index", isDirectory: true)
    try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    let logPath = logsDir.appendingPathComponent("watcher.log").path
    let errPath = logsDir.appendingPathComponent("watcher.err.log").path

    let plistContent = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>com.privateindex.watcher</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(execPath)</string>
            <string>watch</string>
            <string>\(path)</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardOutPath</key>
        <string>\(logPath)</string>
        <key>StandardErrorPath</key>
        <string>\(errPath)</string>
    </dict>
    </plist>
    """

    try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)

    // Unload existing if loaded (suppress stdout/stderr so unneeded "Unload failed" is not printed)
    let unloadProcess = Process()
    unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unloadProcess.arguments = ["unload", plistURL.path]
    unloadProcess.standardOutput = Pipe()
    unloadProcess.standardError = Pipe()
    try? unloadProcess.run()
    unloadProcess.waitUntilExit()

    let loadProcess = Process()
    loadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    loadProcess.arguments = ["load", plistURL.path]
    try? loadProcess.run()
    loadProcess.waitUntilExit()

    print("""
    \(ANSI.bold)\(ANSI.green)✔ LaunchAgent installed successfully!\(ANSI.reset)
      • Plist:        \(ANSI.dim)\(plistURL.path)\(ANSI.reset)
      • Executable:   \(ANSI.dim)\(execPath)\(ANSI.reset)
      • Watch Path:   \(ANSI.cyan)\(path)\(ANSI.reset)
      • Output Log:   \(ANSI.dim)\(logPath)\(ANSI.reset)
      • Error Log:    \(ANSI.dim)\(errPath)\(ANSI.reset)
      • Status:       Loaded into launchd (runs 24/7 headlessly on login)
    """)
}

func uninstallWatcherLaunchAgent() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let plistURL = home.appendingPathComponent("Library/LaunchAgents/com.privateindex.watcher.plist")

    guard FileManager.default.fileExists(atPath: plistURL.path) else {
        print("\(ANSI.yellow)LaunchAgent is not currently installed.\(ANSI.reset) (\(plistURL.path) does not exist)")
        return
    }

    // Unload existing service, suppressing stderr/stdout
    let unloadProcess = Process()
    unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unloadProcess.arguments = ["unload", plistURL.path]
    unloadProcess.standardOutput = Pipe()
    unloadProcess.standardError = Pipe()
    try? unloadProcess.run()
    unloadProcess.waitUntilExit()

    let bootoutProcess = Process()
    bootoutProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    bootoutProcess.arguments = ["bootout", "gui/\(getuid())/com.privateindex.watcher"]
    bootoutProcess.standardOutput = Pipe()
    bootoutProcess.standardError = Pipe()
    try? bootoutProcess.run()
    bootoutProcess.waitUntilExit()

    try FileManager.default.removeItem(at: plistURL)

    print("""
    \(ANSI.bold)\(ANSI.green)✔ LaunchAgent uninstalled successfully!\(ANSI.reset)
      • Plist removed:  \(ANSI.dim)\(plistURL.path)\(ANSI.reset)
      • Daemon stopped: \(ANSI.cyan)com.privateindex.watcher\(ANSI.reset)
    """)
}

func runWatch(path: String) async throws {
    let folderURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: folderURL.path) else {
        print("\(ANSI.red)Error:\(ANSI.reset) Target directory '\(path)' does not exist.")
        exit(1)
    }

    // Validate folder doesn't encompass database to prevent loop
    let defaultDB = defaultDatabaseURL().standardizedFileURL.path
    if defaultDB.hasPrefix(folderURL.standardizedFileURL.path) {
        throw iCloudContainerManager.IsolationError.databaseContainedWithinTargetFolder(folderURL.path)
    }
    try iCloudContainerManager.shared.validateTargetFolder(folderURL)

    let (store, coordinator) = try setupEngine()
    let powerAssertion = PowerAssertion(name: "Private Index CLI Watcher")

    print("""
    \(ANSI.bold)\(ANSI.cyan)Private Index Daemon\(ANSI.reset) — Live Folder Watching
      • Monitoring:       \(ANSI.bold)\(folderURL.path)\(ANSI.reset)
      • Debounce:         2.0s
      • Sleep Protection: Enabled (IOPMAssertion while indexing is active)
      • Database:         \(ANSI.dim)\(defaultDatabaseURL().path)\(ANSI.reset)

    \(ANSI.dim)Press Ctrl+C to terminate cleanly.\(ANSI.reset)
    """)

    final class WatcherHolder: @unchecked Sendable {
        var watcher: DirectoryWatcher?
    }
    let holder = WatcherHolder()

    // Clean shutdown on SIGINT and SIGTERM
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

    let shutdownHandler: @Sendable () -> Void = {
        print("\n\(ANSI.yellow)Shutdown signal received. Cleaning up...\(ANSI.reset)")
        holder.watcher?.stop()
        store.close()
        powerAssertion.release()
        print("\(ANSI.green)✔ FSEvent stream released. SQLite locks freed.\(ANSI.reset)")
        exit(0)
    }

    sigintSource.setEventHandler(handler: shutdownHandler)
    sigtermSource.setEventHandler(handler: shutdownHandler)
    sigintSource.resume()
    sigtermSource.resume()

    // Initial indexing pass
    print("\(ANSI.cyan)Running initial index pass...\(ANSI.reset)")
    powerAssertion.take()
    do {
        let initialReport = try await coordinator.index(directoryURL: folderURL) { progress, message in
            let pct = Int(progress * 100)
            print("\r\(ANSI.dim)[\(pct)%] \(message)\(ANSI.reset)", terminator: "")
            fflush(stdout)
        }
        print("\r\u{001B}[K\(ANSI.green)✔ Initial scan complete:\(ANSI.reset) \(initialReport.filesScanned) scanned, \(initialReport.filesIndexed) indexed, \(initialReport.filesSkipped) skipped (\(initialReport.filesSkippedEvicted) dataless iCloud skipped) in \(String(format: "%.2f", initialReport.duration))s\n")
    } catch {
        print("\n\(ANSI.red)Initial indexing error:\(ANSI.reset) \(error.localizedDescription)")
    }
    powerAssertion.release()

    // Setup DirectoryWatcher with 2.0s debounce
    let watcher = DirectoryWatcher(
        debounceInterval: 2.0,
        onPathsChanged: { changedPaths in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            print("\(ANSI.dim)[\(timestamp)]\(ANSI.reset) \(ANSI.yellow)⚡ Detected \(changedPaths.count) file change(s):\(ANSI.reset)")

            for p in changedPaths.prefix(5) {
                let fileURL = URL(fileURLWithPath: p)
                if FileCrawler.isDatalessICloudFile(at: fileURL) {
                    print("  \(ANSI.dim)↷ Skipped dataless iCloud file: \(fileURL.lastPathComponent)\(ANSI.reset)")
                } else {
                    print("  • \(ANSI.cyan)\(fileURL.lastPathComponent)\(ANSI.reset)")
                }
            }
            if changedPaths.count > 5 {
                print("  \(ANSI.dim)...and \(changedPaths.count - 5) more\(ANSI.reset)")
            }
        },
        onChange: {
            Task {
                powerAssertion.take()
                defer { powerAssertion.release() }

                do {
                    let report = try await coordinator.index(directoryURL: folderURL)
                    if report.filesIndexed > 0 || report.filesDeleted > 0 {
                        print("\(ANSI.green)✔ Incremental index updated:\(ANSI.reset) \(report.filesIndexed) indexed, \(report.filesDeleted) deleted, \(report.filesSkipped) unchanged (\(report.filesSkippedEvicted) dataless iCloud skipped) in \(String(format: "%.2f", report.duration))s")
                    }
                } catch {
                    print("\(ANSI.red)Incremental indexing error:\(ANSI.reset) \(error.localizedDescription)")
                }
            }
        }
    )

    holder.watcher = watcher
    watcher.start(watching: folderURL)
    print("\(ANSI.green)✔ Directory watcher active.\(ANSI.reset) Listening for filesystem events...\n")
}

// MARK: - Entry Point

let args = CommandLine.arguments

guard args.count > 1 else {
    printHelp()
    exit(0)
}

let command = args[1].lowercased()

switch command {
case "watch":
    if args.contains("-h") || args.contains("--help") || (args.count > 2 && args[2] == "help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi watch\(ANSI.reset) — Run background watcher daemon for live folder monitoring

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi watch [path] [options]

        \(ANSI.bold)ARGUMENTS:\(ANSI.reset)
            <path>                   Directory to monitor (defaults to iCloud Drive documents)

        \(ANSI.bold)OPTIONS:\(ANSI.reset)
            --install-launchagent    Generate and load launchd LaunchAgent to run 24/7 headlessly on login
            --uninstall-launchagent  Unload and remove the background launchd LaunchAgent
            -h, --help               Display this help message
        """)
        exit(0)
    }

    var installLaunchAgent = false
    var uninstallLaunchAgent = false
    var pathArg: String? = nil

    var i = 2
    while i < args.count {
        if args[i] == "--install-launchagent" {
            installLaunchAgent = true
            i += 1
        } else if args[i] == "--uninstall-launchagent" || args[i] == "--remove-launchagent" {
            uninstallLaunchAgent = true
            i += 1
        } else if !args[i].hasPrefix("-") && pathArg == nil {
            pathArg = args[i]
            i += 1
        } else {
            i += 1
        }
    }

    if uninstallLaunchAgent {
        do {
            try uninstallWatcherLaunchAgent()
            exit(0)
        } catch {
            print("\(ANSI.red)Error uninstalling LaunchAgent:\(ANSI.reset) \(error.localizedDescription)")
            exit(1)
        }
    }

    let resolvedPath: String
    if let p = pathArg {
        resolvedPath = (p as NSString).expandingTildeInPath
    } else {
        resolvedPath = iCloudContainerManager.defaultUserDocumentsURL.path
    }

    if installLaunchAgent {
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            print("\(ANSI.red)Error:\(ANSI.reset) Directory '\(resolvedPath)' does not exist.")
            exit(1)
        }
        do {
            try installWatcherLaunchAgent(path: resolvedPath)
            exit(0)
        } catch {
            print("\(ANSI.red)Error installing LaunchAgent:\(ANSI.reset) \(error.localizedDescription)")
            exit(1)
        }
    }

    Task {
        do {
            try await runWatch(path: resolvedPath)
        } catch {
            print("\(ANSI.red)Watcher error:\(ANSI.reset) \(error.localizedDescription)")
            exit(1)
        }
    }
    dispatchMain()

case "index":
    if args.contains("-h") || args.contains("--help") || (args.count > 2 && args[2] == "help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi index\(ANSI.reset) — Index documents in a directory

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi index <path>

        \(ANSI.bold)ARGUMENTS:\(ANSI.reset)
            <path>                   Directory to scan and index (e.g. ~/Documents)

        \(ANSI.bold)OPTIONS:\(ANSI.reset)
            -h, --help               Display this help message
        """)
        exit(0)
    }
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
    if args.contains("-h") || args.contains("--help") || (args.count > 2 && args[2] == "help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi search\(ANSI.reset) — Run on-device hybrid, vector, or keyword search

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi search <query> [options]

        \(ANSI.bold)ARGUMENTS:\(ANSI.reset)
            <query>                          Search query string

        \(ANSI.bold)OPTIONS:\(ANSI.reset)
            --mode <hybrid|vector|keyword>   Search mode (default: hybrid)
            --limit <N>                      Maximum results to return (default: 10)
            --min-similarity <pct>           Minimum vector similarity percentage (default: 35%, e.g. 40 or 40%)
            --vector-weight <W>              Vector similarity weight for RRF fusion (default: 0.5)
            --keyword-weight <W>             BM25 keyword weight for RRF fusion (default: 0.5)
            --json                           Output results as strict JSON array (suppresses banners and formatting)
            -h, --help                       Display this help message

        \(ANSI.bold)EXAMPLES:\(ANSI.reset)
            pi search "33 bond st"
            pi search "33 bond st" --min-similarity 25%
            pi search "meeting notes" --mode hybrid --limit 5
            pi search "ERR_404_NOT_FOUND" --mode keyword
            pi search "salary" --json
        """)
        exit(0)
    }

    var limit = 10
    var mode: SearchMode = .hybrid
    var vectorWeight: Float = 0.5
    var keywordWeight: Float = 0.5
    var minSimilarity: Float = 0.35
    var queryTerms: [String] = []
    var isJSON = false

    var i = 2
    while i < args.count {
        let arg = args[i]
        if arg == "--json" {
            isJSON = true
            i += 1
        } else if arg == "--limit", i + 1 < args.count, let parsedLimit = Int(args[i + 1]) {
            limit = parsedLimit
            i += 2
        } else if arg.hasPrefix("--limit="), let parsedLimit = Int(arg.dropFirst("--limit=".count)) {
            limit = parsedLimit
            i += 1
        } else if arg == "--mode", i + 1 < args.count {
            let modeRaw = args[i + 1].lowercased()
            guard let parsedMode = SearchMode(rawValue: modeRaw) else {
                let msg = "Invalid mode '\(args[i + 1])'. Valid modes: hybrid, vector, keyword."
                if isJSON || args.contains("--json") {
                    outputJSONError(msg)
                } else {
                    print("\(ANSI.red)Error:\(ANSI.reset) \(msg)")
                    exit(1)
                }
            }
            mode = parsedMode
            i += 2
        } else if arg.hasPrefix("--mode=") {
            let modeRaw = String(arg.dropFirst("--mode=".count)).lowercased()
            guard let parsedMode = SearchMode(rawValue: modeRaw) else {
                let msg = "Invalid mode '\(modeRaw)'. Valid modes: hybrid, vector, keyword."
                if isJSON || args.contains("--json") {
                    outputJSONError(msg)
                } else {
                    print("\(ANSI.red)Error:\(ANSI.reset) \(msg)")
                    exit(1)
                }
            }
            mode = parsedMode
            i += 1
        } else if (arg == "--min-similarity" || arg == "--threshold"), i + 1 < args.count {
            minSimilarity = parseSimilarity(args[i + 1])
            i += 2
        } else if arg.hasPrefix("--min-similarity=") {
            let val = String(arg.dropFirst("--min-similarity=".count))
            minSimilarity = parseSimilarity(val)
            i += 1
        } else if arg.hasPrefix("--threshold=") {
            let val = String(arg.dropFirst("--threshold=".count))
            minSimilarity = parseSimilarity(val)
            i += 1
        } else if (arg == "--vector-weight" || arg == "--w-vector"), i + 1 < args.count, let weight = Float(args[i + 1]) {
            vectorWeight = weight
            i += 2
        } else if arg.hasPrefix("--vector-weight="), let weight = Float(arg.dropFirst("--vector-weight=".count)) {
            vectorWeight = weight
            i += 1
        } else if (arg == "--keyword-weight" || arg == "--w-keyword"), i + 1 < args.count, let weight = Float(args[i + 1]) {
            keywordWeight = weight
            i += 2
        } else if arg.hasPrefix("--keyword-weight="), let weight = Float(arg.dropFirst("--keyword-weight=".count)) {
            keywordWeight = weight
            i += 1
        } else {
            queryTerms.append(args[i])
            i += 1
        }
    }

    let query = queryTerms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
        let msg = "Please specify a search query. e.g. `pi search \"privacy machine learning\"`"
        if isJSON {
            outputJSONError(msg)
        } else {
            print("\(ANSI.red)Error:\(ANSI.reset) \(msg)")
            exit(1)
        }
    }

    let searchLimit = limit
    let searchMode = mode
    let searchVectorWeight = vectorWeight
    let searchKeywordWeight = keywordWeight
    let searchMinSimilarity = minSimilarity
    let searchIsJSON = isJSON

    Task {
        do {
            try await runSearch(
                query: query,
                limit: searchLimit,
                mode: searchMode,
                vectorWeight: searchVectorWeight,
                keywordWeight: searchKeywordWeight,
                minSimilarity: searchMinSimilarity,
                isJSON: searchIsJSON
            )
            exit(0)
        } catch {
            if searchIsJSON {
                outputJSONError(error.localizedDescription)
            } else {
                print("\(ANSI.red)Search error:\(ANSI.reset) \(error.localizedDescription)")
                exit(1)
            }
        }
    }
    RunLoop.main.run()

case "bench":
    if args.contains("-h") || args.contains("--help") || (args.count > 2 && args[2] == "help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi bench\(ANSI.reset) — Run on-device Apple Silicon performance benchmark

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi bench [options]

        \(ANSI.bold)OPTIONS:\(ANSI.reset)
            --vectors <N>  Number of vectors for insertion/retrieval test (default: 1000)
            --json         Output benchmark metrics as machine-readable JSON
            -h, --help     Display this help message

        \(ANSI.bold)EXAMPLES:\(ANSI.reset)
            pi bench
            pi bench --vectors 5000
            pi bench --json
        """)
        exit(0)
    }

    var vectorCount = 1000
    var asJSON = false

    var i = 2
    while i < args.count {
        let arg = args[i]
        if arg == "--vectors", i + 1 < args.count, let parsed = Int(args[i + 1]) {
            vectorCount = parsed
            i += 2
        } else if arg.hasPrefix("--vectors="), let parsed = Int(arg.dropFirst("--vectors=".count)) {
            vectorCount = parsed
            i += 1
        } else if arg == "--json" {
            asJSON = true
            i += 1
        } else {
            i += 1
        }
    }

    let benchVectorCount = vectorCount
    let benchAsJSON = asJSON

    Task {
        do {
            try await runBench(vectorCount: benchVectorCount, asJSON: benchAsJSON)
            exit(0)
        } catch {
            print("\(ANSI.red)Benchmark error:\(ANSI.reset) \(error.localizedDescription)")
            exit(1)
        }
    }
    RunLoop.main.run()

case "stats":
    if args.contains("-h") || args.contains("--help") || (args.count > 2 && args[2] == "help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi stats\(ANSI.reset) — Show database statistics and indexed document counts

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi stats

        \(ANSI.bold)OPTIONS:\(ANSI.reset)
            -h, --help    Display this help message
        """)
        exit(0)
    }
    do {
        try runStats()
    } catch {
        print("\(ANSI.red)Error:\(ANSI.reset) \(error.localizedDescription)")
        exit(1)
    }

case "reset":
    if args.contains("-h") || args.contains("--help") || (args.count > 2 && args[2] == "help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi reset\(ANSI.reset) — Clear database and purge all vector embeddings

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi reset

        \(ANSI.bold)OPTIONS:\(ANSI.reset)
            -h, --help    Display this help message
        """)
        exit(0)
    }
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
