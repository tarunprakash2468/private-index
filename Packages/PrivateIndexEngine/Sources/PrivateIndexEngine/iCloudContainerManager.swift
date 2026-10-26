import Foundation

// MARK: - iCloudContainerManager

/// Manages isolation and path resolution for the app's sandboxed iCloud Ubiquity Container.
///
/// Ensures the SQLite database (`index.sqlite`) resides in the app's private ubiquity container
/// (`iCloud.com.app.privateindex`) or sandboxed Application Support directory, strictly isolated
/// from the user-facing iCloud Drive documents folder (`~/Library/Mobile Documents/com~apple~CloudDocs/`).
public final class iCloudContainerManager: @unchecked Sendable {

    public static let shared = iCloudContainerManager()

    /// The App's iCloud Ubiquity Container identifier.
    public static let ubiquityContainerIdentifier = "iCloud.com.app.privateindex"

    /// The path to the user's personal iCloud Drive documents folder.
    public static var defaultUserDocumentsURL: URL {
        let cloudDocsPath = ("~/Library/Mobile Documents/com~apple~CloudDocs" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: cloudDocsPath) {
            return URL(fileURLWithPath: cloudDocsPath)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    // MARK: - Storage URLs

    /// Resolves the app container URL (either iCloud ubiquity container or local Application Support fallback).
    public var containerURL: URL {
        if let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: Self.ubiquityContainerIdentifier) {
            return ubiquityURL
        }
        // Fallback for development, simulator, or machines without iCloud logged in
        #if os(macOS)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let localContainer = appSupport.appendingPathComponent("PrivateIndex", isDirectory: true)
        #else
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localContainer = documents.appendingPathComponent("PrivateIndexContainer", isDirectory: true)
        #endif
        try? FileManager.default.createDirectory(at: localContainer, withIntermediateDirectories: true)
        return localContainer
    }

    /// The isolated database file URL.
    public var databaseURL: URL {
        let dbDir = containerURL.appendingPathComponent("Database", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        return dbDir.appendingPathComponent("index.sqlite")
    }

    // MARK: - Validation & Loop Prevention

    public enum IsolationError: Error, LocalizedError, Equatable {
        case databaseContainedWithinTargetFolder(String)

        public var errorDescription: String? {
            switch self {
            case .databaseContainedWithinTargetFolder(let path):
                return "The selected directory '\(path)' contains the internal database. Please choose a different documents folder."
            }
        }
    }

    /// Verifies that the specified target folder does not encompass the database file or container,
    /// preventing recursive indexing loops.
    public func validateTargetFolder(_ folderURL: URL) throws {
        let standardizedFolder = folderURL.standardizedFileURL.path

        #if os(macOS)
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

        // Exempt the user's home directory since the internal database resides inside a hidden dot directory (.private-index)
        // which is already excluded from crawling by FileCrawler.
        if standardizedFolder == homePath {
            return
        }
        #endif

        let standardizedDB = databaseURL.standardizedFileURL.path
        let standardizedContainer = containerURL.standardizedFileURL.path

        if standardizedDB.hasPrefix(standardizedFolder) || standardizedContainer.hasPrefix(standardizedFolder) {
            throw IsolationError.databaseContainedWithinTargetFolder(folderURL.path)
        }
    }
}
