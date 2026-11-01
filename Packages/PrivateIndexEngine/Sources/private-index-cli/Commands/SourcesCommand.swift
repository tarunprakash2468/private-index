import Foundation
import ArgumentParser
import PrivateIndexEngine

extension PrivateIndexCLI {
    struct Sources: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "sources",
            abstract: "List all indexed sources, folders, and cloud locations",
            aliases: ["locations"]
        )

        @Flag(name: .customLong("json"), help: "Output as JSON")
        var json: Bool = false

        func run() throws {
            let (store, _) = try setupEngine(readOnly: true)
            defer { store.close() }

            let sources = try store.getIndexedSources()

            if json {
                struct JSONSource: Encodable {
                    let id: String
                    let name: String
                    let rootPath: String
                    let fileCount: Int
                    let totalBytes: Int64
                }
                let items = sources.map {
                    JSONSource(id: $0.id, name: $0.name, rootPath: $0.rootPath, fileCount: $0.fileCount, totalBytes: $0.totalBytes)
                }
                let data = try JSONEncoder().encode(items)
                if let str = String(data: data, encoding: .utf8) {
                    print(str)
                }
                return
            }

            guard !sources.isEmpty else {
                print("\(ANSI.dim)No sources indexed yet. Use `pi index <folder>` to index documents.\(ANSI.reset)")
                return
            }

            let totalFiles = sources.reduce(0) { $0 + $1.fileCount }
            let totalBytes = sources.reduce(0) { $0 + $1.totalBytes }
            let totalSizeStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

            print("\(ANSI.bold)\(ANSI.cyan)Private Index Synced Sources\(ANSI.reset) (\(totalFiles) files, \(totalSizeStr))\n")

            for source in sources {
                let sizeStr = ByteCountFormatter.string(fromByteCount: source.totalBytes, countStyle: .file)
                let displayPath = (source.rootPath as NSString).abbreviatingWithTildeInPath
                print("  \(ANSI.bold)• \(source.name)\(ANSI.reset) (\(source.fileCount) files, \(sizeStr))")
                print("    \(ANSI.dim)\(displayPath)\(ANSI.reset)\n")
            }
        }
    }
}
