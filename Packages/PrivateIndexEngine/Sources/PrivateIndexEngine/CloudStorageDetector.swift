import Foundation

// MARK: - DiscoveredLocation

public struct DiscoveredLocation: Sendable, Equatable, Identifiable {
    public var id: String { url.standardizedFileURL.path }
    public let name: String
    public let url: URL
    public let isCloud: Bool

    public init(name: String, url: URL, isCloud: Bool) {
        self.name = name
        self.url = url
        self.isCloud = isCloud
    }
}

// MARK: - CloudDownloadManager

public struct CloudDownloadManager: Sendable {
    public static let defaultMinBufferBytes: Int64 = 10 * 1024 * 1024 * 1024 // 10 GB

    /// Verifies that downloading `fileSize` bytes will leave at least `minBufferBytes`
    /// (and at least 10% of total volume capacity) free on the volume hosting `url`.
    public static func hasSufficientDiskSpace(
        forFileSize fileSize: Int64,
        at url: URL,
        minBufferBytes: Int64 = defaultMinBufferBytes
    ) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]),
        let available = values.volumeAvailableCapacityForImportantUsage else {
            return false
        }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let dynamicMinBuffer = max(minBufferBytes, total / 10)
        return (available - fileSize) >= dynamicMinBuffer
    }
}

// MARK: - CloudStorageDetector

public struct CloudStorageDetector: Sendable {
    public init() {}

    /// Discovers all available user and cloud storage locations on macOS.
    ///
    /// Locations checked:
    /// - Current user home directory (`~`)
    /// - iCloud Drive documents (`~/Library/Mobile Documents/com~apple~CloudDocs`)
    /// - FileProvider cloud storage providers (`~/Library/CloudStorage/` — Google Drive, OneDrive, Dropbox, Box)
    /// - Home directory cloud aliases/symlinks (`~/Google Drive`, `~/OneDrive`, `~/Dropbox`)
    public static func discoverLocations(includeHome: Bool = true) -> [DiscoveredLocation] {
        var locations: [DiscoveredLocation] = []
        var seenCanonicalPaths = Set<String>()

        // 1. Home directory
        if includeHome {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let canonical = home.resolvingSymlinksInPath().standardizedFileURL.path
            locations.append(DiscoveredLocation(name: "Home (~/)", url: home, isCloud: false))
            seenCanonicalPaths.insert(canonical)
        }

        // 2. iCloud Drive documents
        let iCloudDocs = iCloudContainerManager.defaultUserDocumentsURL
        if FileManager.default.fileExists(atPath: iCloudDocs.path) {
            let canonical = iCloudDocs.resolvingSymlinksInPath().standardizedFileURL.path
            if !seenCanonicalPaths.contains(canonical) {
                locations.append(DiscoveredLocation(name: "iCloud Drive", url: iCloudDocs, isCloud: true))
                seenCanonicalPaths.insert(canonical)
            }
        }

        // 3. ~/Library/CloudStorage/ (Google Drive, OneDrive, Dropbox, Box, etc.)
        let cloudStoragePath = ("~/Library/CloudStorage" as NSString).expandingTildeInPath
        let cloudStorageURL = URL(fileURLWithPath: cloudStoragePath, isDirectory: true)

        if let contents = try? FileManager.default.contentsOfDirectory(at: cloudStorageURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in contents {
                let name = item.lastPathComponent
                if name.hasPrefix(".") { continue }

                let canonical = item.resolvingSymlinksInPath().standardizedFileURL.path
                if seenCanonicalPaths.contains(canonical) { continue }

                let displayName: String
                let lower = name.lowercased()
                if lower.contains("googledrive") {
                    displayName = "Google Drive"
                } else if lower.contains("onedrive") {
                    displayName = "OneDrive"
                } else if lower.contains("dropbox") {
                    displayName = "Dropbox"
                } else if lower.contains("box") {
                    displayName = "Box"
                } else {
                    displayName = name
                }

                locations.append(DiscoveredLocation(name: displayName, url: item, isCloud: true))
                seenCanonicalPaths.insert(canonical)
            }
        }

        // 4. Known home directory symlinks / aliases
        let homeAliases = [
            ("Google Drive", "~/Google Drive"),
            ("OneDrive", "~/OneDrive"),
            ("Dropbox", "~/Dropbox")
        ]
        for (name, path) in homeAliases {
            let expanded = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                let url = URL(fileURLWithPath: expanded)
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
                if !seenCanonicalPaths.contains(canonical) {
                    locations.append(DiscoveredLocation(name: name, url: url, isCloud: true))
                    seenCanonicalPaths.insert(canonical)
                }
            }
        }

        return locations
    }
}
