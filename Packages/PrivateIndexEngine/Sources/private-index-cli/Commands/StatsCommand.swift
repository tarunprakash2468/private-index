import Foundation
import ArgumentParser
import PrivateIndexEngine

extension PrivateIndexCLI {
    struct Stats: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "stats",
            abstract: "Show database stats and indexed document counts",
            aliases: ["status"]
        )

        func run() throws {
            do {
                try runStats()
            } catch {
                print("\(ANSI.red)Error:\(ANSI.reset) \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
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
