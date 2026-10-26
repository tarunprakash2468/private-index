import Foundation

// MARK: - IOSContainerManager

/// Manages iCloud ubiquity container isolation, database placement, and security-scoped
/// bookmark persistence for the iOS app.
public final class IOSContainerManager: @unchecked Sendable {

    public static let shared = IOSContainerManager()

    public static let ubiquityContainerIdentifier = "iCloud.com.app.privateindex"
    private let bookmarkStorageKey = "com.privateindex.ios.monitoredFolderBookmark"

    private var activeSecurityScopedURL: URL?

    public init() {}

    deinit {
        stopAccessingSecurityScopedResource()
    }

    // MARK: - Ubiquity Container & Database

    /// Resolves the app container (iCloud ubiquity container or sandboxed local documents directory).
    public var containerURL: URL {
        if let ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: Self.ubiquityContainerIdentifier) {
            return ubiquityURL
        }
        // Fallback for Simulator or devices without iCloud active
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appContainer = documents.appendingPathComponent("PrivateIndexContainer", isDirectory: true)
        try? FileManager.default.createDirectory(at: appContainer, withIntermediateDirectories: true)
        return appContainer
    }

    /// The isolated database path, strictly separated from user documents.
    public var databaseURL: URL {
        let dbDir = containerURL.appendingPathComponent("Database", isDirectory: true)
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        return dbDir.appendingPathComponent("index.sqlite")
    }

    // MARK: - Security-Scoped Bookmarks

    /// Persists security-scoped access for a user-selected folder from the Files app.
    public func saveBookmark(for url: URL) throws {
        stopAccessingSecurityScopedResource()

        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied
        }

        self.activeSecurityScopedURL = url

        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        UserDefaults.standard.set(bookmarkData, forKey: bookmarkStorageKey)
    }

    /// Restores previously persisted folder access on app launch.
    public func restoreMonitoredFolder() -> URL? {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkStorageKey) else {
            return nil
        }

        var isStale = false
        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withoutUI,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if resolvedURL.startAccessingSecurityScopedResource() {
                self.activeSecurityScopedURL = resolvedURL
                if isStale {
                    try? saveBookmark(for: resolvedURL)
                }
                return resolvedURL
            }
        } catch {
            return nil
        }

        return nil
    }

    /// Releases security-scoped access.
    public func stopAccessingSecurityScopedResource() {
        if let activeURL = activeSecurityScopedURL {
            activeURL.stopAccessingSecurityScopedResource()
            self.activeSecurityScopedURL = nil
        }
    }

    // MARK: - Loop Prevention

    public enum BookmarkError: Error, LocalizedError {
        case accessDenied
        case databaseContainedWithinTargetFolder(String)

        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Permission to access the selected folder was denied by iOS."
            case .databaseContainedWithinTargetFolder(let path):
                return "The folder '\(path)' contains the internal database. Please select a documents folder."
            }
        }
    }

    /// Validates that the selected folder doesn't encompass the database file to prevent indexing loops.
    public func validateTargetFolder(_ folderURL: URL) throws {
        let standardizedFolder = folderURL.standardizedFileURL.path
        let standardizedDB = databaseURL.standardizedFileURL.path

        if standardizedDB.hasPrefix(standardizedFolder) {
            throw BookmarkError.databaseContainedWithinTargetFolder(folderURL.path)
        }
    }
}
