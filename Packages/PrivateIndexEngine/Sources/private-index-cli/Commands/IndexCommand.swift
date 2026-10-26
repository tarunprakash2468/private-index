import Foundation
import PrivateIndexEngine

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

func handleIndexCommand(args: [String]) {
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
}
