import Foundation
import ArgumentParser
import PrivateIndexEngine

extension PrivateIndexCLI {
    struct Index: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "index",
            abstract: "Index documents in the specified directory"
        )

        @Argument(help: "Directory to scan and index (e.g. ~/Documents)")
        var path: String

        func run() async throws {
            do {
                try await runIndex(path: path)
            } catch {
                print("\(ANSI.red)Indexing error:\(ANSI.reset) \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
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
