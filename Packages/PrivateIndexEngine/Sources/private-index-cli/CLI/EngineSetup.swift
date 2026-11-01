import Foundation
import PrivateIndexEngine

func defaultDatabaseURL() -> URL {
    let cloudDB = iCloudContainerManager.shared.databaseURL
    if FileManager.default.fileExists(atPath: cloudDB.path) {
        return cloudDB
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let dir = home.appendingPathComponent(".private-index", isDirectory: true)
    let legacyDB = dir.appendingPathComponent("index.sqlite")
    if FileManager.default.fileExists(atPath: legacyDB.path) {
        return legacyDB
    }
    return cloudDB
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
