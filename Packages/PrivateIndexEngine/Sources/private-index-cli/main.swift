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
        \(ANSI.green)watch\(ANSI.reset) [path] [--install-launchagent]  Run background watcher daemon for live folder monitoring
        \(ANSI.green)search\(ANSI.reset) <query> [--limit N]  Run semantic similarity search for a query
        \(ANSI.green)stats\(ANSI.reset)                   Show database stats and indexed document counts
        \(ANSI.green)reset\(ANSI.reset)                   Clear database and purge all vector embeddings
        \(ANSI.green)help\(ANSI.reset)                    Display this help message

    \(ANSI.bold)EXAMPLES:\(ANSI.reset)
        pi index ~/Documents
        pi watch ~/Documents
        pi watch --install-launchagent
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

    // Unload existing if loaded, then load new
    let unloadProcess = Process()
    unloadProcess.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    unloadProcess.arguments = ["unload", plistURL.path]
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
    if args.contains("-h") || args.contains("--help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi watch\(ANSI.reset) — Run background watcher daemon for live folder monitoring

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi watch [path] [options]

        \(ANSI.bold)ARGUMENTS:\(ANSI.reset)
            <path>                   Directory to monitor (defaults to iCloud Drive documents)

        \(ANSI.bold)OPTIONS:\(ANSI.reset)
            --install-launchagent    Generate and load launchd LaunchAgent to run 24/7 headlessly on login
            -h, --help               Display this help message
        """)
        exit(0)
    }

    var installLaunchAgent = false
    var pathArg: String? = nil

    var i = 2
    while i < args.count {
        if args[i] == "--install-launchagent" {
            installLaunchAgent = true
            i += 1
        } else if !args[i].hasPrefix("-") && pathArg == nil {
            pathArg = args[i]
            i += 1
        } else {
            i += 1
        }
    }

    let resolvedPath: String
    if let p = pathArg {
        resolvedPath = (p as NSString).expandingTildeInPath
    } else {
        resolvedPath = iCloudContainerManager.defaultUserDocumentsURL.path
    }

    if installLaunchAgent {
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
