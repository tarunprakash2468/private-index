import Foundation
import ArgumentParser
import PrivateIndexEngine

@main
struct PrivateIndexCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pi",
        abstract: "Private Index: On-Device Semantic Search Engine",
        subcommands: [
            Index.self,
            Watch.self,
            Search.self,
            Bench.self,
            Stats.self,
            Reset.self,
        ]
    )

    public static func main() async {
        let args = CommandLine.arguments
        if args.count <= 1 {
            print(PrivateIndexCLI.helpMessage())
            Darwin.exit(0)
        }
        do {
            var command = try await asyncParseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            if args.contains("--json") {
                let msg = PrivateIndexCLI.message(for: error)
                outputJSONError(msg)
            } else {
                PrivateIndexCLI.exit(withError: error)
            }
        }
    }
}
