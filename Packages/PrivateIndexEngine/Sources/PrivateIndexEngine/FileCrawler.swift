import Foundation

// MARK: - FileCrawler

/// Recursively scans a directory for indexable text files.
///
/// The crawler filters out hidden files, system directories, binaries, and SQLite
/// databases. It also checks iCloud download status to avoid blocking on
/// evicted/dataless files that would trigger an expensive network download.
public struct FileCrawler: Sendable {

    // MARK: - Supported File Types

    /// File extensions that are considered indexable plain-text content.
    public static let supportedExtensions: Set<String> = [
        // Documents
        "pdf",
        // Plain text
        "txt", "text",
        // Markdown
        "md", "markdown", "mdown", "mkd",
        // Source code
        "swift", "py", "js", "ts", "jsx", "tsx",
        "c", "h", "cpp", "hpp", "cc", "cxx",
        "rs", "go", "java", "kt", "kts",
        "rb", "php", "scala", "hs", "ex", "exs",
        "lua", "r", "m", "mm",
        // Shell
        "sh", "zsh", "bash", "fish",
        // Web / Markup
        "css", "html", "htm", "xml", "svg",
        // Data / Config
        "json", "yaml", "yml", "toml",
        "csv", "tsv", "ini", "cfg", "conf",
        "plist", "env",
        // Documentation
        "tex", "rst", "adoc",
        // Database
        "sql",
        // Logs
        "log",
    ]

    /// Directory names that should always be skipped.
    private static let excludedDirectories: Set<String> = [
        "__MACOSX", ".Trash", ".Spotlight-V100", ".fseventsd",
        ".DocumentRevisions-V100", ".TemporaryItems",
        "node_modules", ".git", ".svn", ".hg",
        "__pycache__", ".build", "DerivedData",
    ]

    // MARK: - Result

    /// The result of a directory crawl.
    public struct CrawlResult: Sendable {
        /// Files that are available locally and have a supported extension.
        public let indexableFiles: [URL]
        /// Files that were skipped because they are evicted/dataless in iCloud.
        public let skippedEvicted: [URL]
        /// Files that were skipped for other reasons (hidden, unsupported extension, etc.)
        public let skippedOther: [URL]
    }

    // MARK: - Initialization

    public init() {}

    // MARK: - Crawling

    /// Scans `rootURL` recursively, categorizing files.
    ///
    /// - Parameter rootURL: The directory to scan.
    /// - Returns: A `CrawlResult` with categorized file URLs.
    public func crawl(rootURL: URL) -> CrawlResult {
        var indexable: [URL] = []
        var evicted: [URL] = []
        var other: [URL] = []

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isHiddenKey,
            .nameKey,
            .ubiquitousItemDownloadingStatusKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.producesRelativePathURLs]
        ) else {
            return CrawlResult(indexableFiles: [], skippedEvicted: [], skippedOther: [])
        }

        for case let fileURL as URL in enumerator {
            let resourceValues: URLResourceValues
            do {
                resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
            } catch {
                other.append(fileURL)
                continue
            }

            let name = resourceValues.name ?? fileURL.lastPathComponent

            // Skip hidden files and directories (prefixed with `.` or isHidden)
            if name.hasPrefix(".") || (resourceValues.isHidden == true) {
                if resourceValues.isDirectory == true {
                    enumerator.skipDescendants()
                }
                other.append(fileURL)
                continue
            }

            // Skip excluded system directories
            if resourceValues.isDirectory == true {
                if Self.excludedDirectories.contains(name) {
                    enumerator.skipDescendants()
                    other.append(fileURL)
                }
                // Directories themselves are not files to index
                continue
            }

            // Only process regular files
            guard resourceValues.isRegularFile == true else {
                other.append(fileURL)
                continue
            }

            // Skip SQLite database files
            let ext = fileURL.pathExtension.lowercased()
            if ext.hasPrefix("sqlite") {
                other.append(fileURL)
                continue
            }

            // Check file extension against our allowlist
            guard Self.supportedExtensions.contains(ext) else {
                other.append(fileURL)
                continue
            }

            // Check iCloud download status to avoid blocking on evicted files
            if let downloadStatus = resourceValues.ubiquitousItemDownloadingStatus {
                if downloadStatus == .notDownloaded {
                    evicted.append(fileURL)
                    continue
                }
            }

            indexable.append(fileURL)
        }

        return CrawlResult(
            indexableFiles: indexable,
            skippedEvicted: evicted,
            skippedOther: other
        )
    }
}
