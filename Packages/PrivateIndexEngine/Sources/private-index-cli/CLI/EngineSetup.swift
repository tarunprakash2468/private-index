import Foundation
import PrivateIndexEngine

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
