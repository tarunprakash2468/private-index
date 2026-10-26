import Foundation
import PrivateIndexEngine

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

func handleResetCommand(args: [String]) {
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
}
