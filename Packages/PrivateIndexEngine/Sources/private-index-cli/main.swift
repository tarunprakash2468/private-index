import Foundation
import PrivateIndexEngine

// MARK: - CLI Engine Setup

func defaultDatabaseURL() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent(".private-index", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("index.sqlite")
}

func setupEngine(
    downloadCloudFiles: Bool = true,
    minBufferBytes: Int64 = CloudDownloadManager.defaultMinBufferBytes
) throws -> (VectorStore, IndexCoordinator) {
    let dbURL = defaultDatabaseURL()
    let instance = try EngineFactory.create(
        databaseURL: dbURL,
        downloadCloudFiles: downloadCloudFiles,
        minDiskBufferBytes: minBufferBytes
    )
    return (instance.store, instance.coordinator)
}

// MARK: - Top-Level CLI Router

let args = CommandLine.arguments

guard args.count > 1 else {
    printHelp()
    exit(0)
}

let command = args[1].lowercased()

switch command {
case "watch":
    handleWatchCommand(args: args)

case "index":
    handleIndexCommand(args: args)

case "search":
    handleSearchCommand(args: args)

case "bench":
    handleBenchCommand(args: args)

case "stats", "status":
    handleStatsCommand(args: args)

case "reset":
    handleResetCommand(args: args)

case "help", "-h", "--help":
    printHelp()

default:
    print("\(ANSI.red)Unknown command:\(ANSI.reset) '\(command)'. Run `private-index-cli help` for usage.")
    exit(1)
}
