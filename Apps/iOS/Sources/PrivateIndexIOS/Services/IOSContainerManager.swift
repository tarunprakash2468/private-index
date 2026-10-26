import Foundation
import PrivateIndexEngine

// MARK: - IOSContainerManager

/// Manages iCloud ubiquity container isolation, database placement, and security-scoped
/// bookmark persistence for the iOS app.
public final class IOSContainerManager: @unchecked Sendable {

    public static let shared = IOSContainerManager()

    public static let ubiquityContainerIdentifier = iCloudContainerManager.ubiquityContainerIdentifier
    private let bookmarkStorageKey = "com.privateindex.ios.monitoredFolderBookmark"

    private var activeSecurityScopedURL: URL?

    public init() {}

    deinit {
        stopAccessingSecurityScopedResource()
    }

    // MARK: - Ubiquity Container & Database Delegation

    /// Resolves the app container (iCloud ubiquity container or sandboxed local documents directory).
    public var containerURL: URL {
        iCloudContainerManager.shared.containerURL
    }

    /// The isolated database path, strictly separated from user documents.
    public var databaseURL: URL {
        iCloudContainerManager.shared.databaseURL
    }

    /// Validates that the selected folder doesn't encompass the database file to prevent indexing loops.
    public func validateTargetFolder(_ folderURL: URL) throws {
        try iCloudContainerManager.shared.validateTargetFolder(folderURL)
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

    // MARK: - Errors

    public enum BookmarkError: Error, LocalizedError {
        case accessDenied

        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Permission to access the selected folder was denied by iOS."
            }
        }
    }
}
