import Foundation
import PrivateIndexEngine

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

func handleStatsCommand(args: [String]) {
    if args.contains("-h") || args.contains("--help") || (args.count > 2 && args[2] == "help") {
        print("""
        \(ANSI.bold)\(ANSI.cyan)pi stats\(ANSI.reset) — Show database statistics and indexed document counts

        \(ANSI.bold)USAGE:\(ANSI.reset)
            pi stats
            pi status

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
}
