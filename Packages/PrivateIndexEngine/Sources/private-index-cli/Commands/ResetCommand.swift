import Foundation
import ArgumentParser
import PrivateIndexEngine

extension PrivateIndexCLI {
    struct Reset: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reset",
            abstract: "Clear database and purge all vector embeddings"
        )

        func run() throws {
            do {
                try runReset()
            } catch {
                print("\(ANSI.red)Error:\(ANSI.reset) \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }
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
