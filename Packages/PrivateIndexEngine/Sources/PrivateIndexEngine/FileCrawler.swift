import Foundation

// MARK: - FileCrawler

/// Recursively scans a directory for indexable text files.
///
/// The crawler filters out hidden files, system directories, binaries, SQLite
/// databases, and common build/dependency directories. It safely traverses directory
/// symlinks with cycle detection and maximum directory depth guardrails. It also
/// checks iCloud download status to avoid blocking on evicted/dataless files that
/// would trigger an expensive network download.
public struct FileCrawler: Sendable {

    // MARK: - Configuration Limits

    /// Default maximum directory recursion depth limit.
    public static let defaultMaxDepth: Int = 20

    /// The maximum directory recursion depth for this crawler instance.
    public let maxDepth: Int

    // MARK: - Supported File Types

    /// File extensions that are considered indexable content.
    public static let supportedExtensions: Set<String> = [
        // Documents
        "pdf",
        // Images
        "png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp",
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

    /// Directory names that should always be skipped during traversal.
    public static let excludedDirectories: Set<String> = [
        // System & Temporary
        "__MACOSX", ".Trash", ".Spotlight-V100", ".fseventsd",
        ".DocumentRevisions-V100", ".TemporaryItems",
        // Version Control
        ".git", ".svn", ".hg",
        // Package Managers & Build Artifacts
        "node_modules", ".build",
        // Python
        "venv", ".venv", "env", ".env", "site-packages", "__pycache__",
        // Web / Frontend
        "dist", "out", ".next", ".nuxt", ".turbo",
        // iOS / Mobile
        "Pods", "Carthage", "DerivedData",
        // Rust / Go / Java
        "target", "vendor", ".gradle",
        // IDEs
        ".idea", ".vscode",
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

        public init(
            indexableFiles: [URL],
            skippedEvicted: [URL],
            skippedOther: [URL]
        ) {
            self.indexableFiles = indexableFiles
            self.skippedEvicted = skippedEvicted
            self.skippedOther = skippedOther
        }
    }

    // MARK: - Initialization

    public init(maxDepth: Int = Self.defaultMaxDepth) {
        self.maxDepth = maxDepth
    }

    // MARK: - Dataless / Evicted iCloud Check

    /// Checks whether the file at `url` is evicted/dataless in iCloud without triggering download.
    public static func isDatalessICloudFile(at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
              let status = values.ubiquitousItemDownloadingStatus else {
            return false
        }
        return status == .notDownloaded
    }

    // MARK: - Crawling

    /// Scans `rootURL` recursively, categorizing files.
    ///
    /// Directory symlinks are safely followed with cycle detection (via canonical path
    /// tracking) and guarded by a maximum directory depth limit.
    ///
    /// - Parameters:
    ///   - rootURL: The directory to scan.
    ///   - maxDepth: Optional override for the maximum traversal depth. If `nil`, `self.maxDepth` is used.
    /// - Returns: A `CrawlResult` with categorized file URLs.
    public func crawl(rootURL: URL, maxDepth: Int? = nil) -> CrawlResult {
        let depthLimit = maxDepth ?? self.maxDepth
        guard depthLimit > 0 else {
            return CrawlResult(indexableFiles: [], skippedEvicted: [], skippedOther: [])
        }

        var indexable: [URL] = []
        var evicted: [URL] = []
        var other: [URL] = []

        let resolvedRoot = rootURL.resolvingSymlinksInPath()
        var isRootDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedRoot.path, isDirectory: &isRootDir),
              isRootDir.boolValue else {
            return CrawlResult(indexableFiles: [], skippedEvicted: [], skippedOther: [])
        }

        var visitedCanonicalPaths = Set<String>()
        visitedCanonicalPaths.insert(resolvedRoot.standardizedFileURL.path)

        struct DirectoryEntry {
            let url: URL
            let depth: Int
        }

        var queue: [DirectoryEntry] = [DirectoryEntry(url: resolvedRoot, depth: 0)]
        var queueIndex = 0

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .nameKey,
            .ubiquitousItemDownloadingStatusKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]

        while queueIndex < queue.count {
            let current = queue[queueIndex]
            queueIndex += 1

            let contents: [URL]
            do {
                contents = try FileManager.default.contentsOfDirectory(
                    at: current.url,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: []
                )
            } catch {
                other.append(current.url)
                continue
            }

            for fileURL in contents {
                let resourceValues: URLResourceValues
                do {
                    resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
                } catch {
                    other.append(fileURL)
                    continue
                }

                let name = resourceValues.name ?? fileURL.lastPathComponent

                // Skip hidden files and directories prefixed with `.`
                if name.hasPrefix(".") {
                    other.append(fileURL)
                    continue
                }

                // Skip excluded directories
                if Self.excludedDirectories.contains(name) {
                    other.append(fileURL)
                    continue
                }

                let isDirectory = resourceValues.isDirectory ?? false
                let isSymbolicLink = resourceValues.isSymbolicLink ?? false

                // 1. Symbolic Link Handling
                if isSymbolicLink {
                    let resolvedURL = fileURL.resolvingSymlinksInPath()
                    var isTargetDir: ObjCBool = false
                    let targetExists = FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isTargetDir)

                    if targetExists && isTargetDir.boolValue {
                        let targetName = resolvedURL.lastPathComponent
                        if targetName.hasPrefix(".") || Self.excludedDirectories.contains(targetName) {
                            other.append(fileURL)
                            continue
                        }

                        // Check if target directory is marked hidden
                        if let targetValues = try? resolvedURL.resourceValues(forKeys: [.isHiddenKey]),
                           targetValues.isHidden == true {
                            other.append(fileURL)
                            continue
                        }

                        let canonicalPath = resolvedURL.standardizedFileURL.path
                        if visitedCanonicalPaths.contains(canonicalPath) {
                            // Cycle detected: prevent infinite recursion
                            continue
                        }
                        visitedCanonicalPaths.insert(canonicalPath)

                        if current.depth < depthLimit {
                            queue.append(DirectoryEntry(url: resolvedURL, depth: current.depth + 1))
                        }
                        continue
                    } else if !targetExists {
                        // Broken symlink
                        other.append(fileURL)
                        continue
                    }

                    // For symlinks to files, check if the target or symlink is hidden
                    if resourceValues.isHidden == true {
                        if let targetValues = try? resolvedURL.resourceValues(forKeys: [.isHiddenKey]),
                           targetValues.isHidden == true {
                            other.append(fileURL)
                            continue
                        }
                    }
                } else {
                    // Skip hidden files and directories
                    if resourceValues.isHidden == true {
                        other.append(fileURL)
                        continue
                    }
                }

                // 2. Regular Directory
                if isDirectory && !isSymbolicLink {
                    let canonicalPath = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
                    if visitedCanonicalPaths.contains(canonicalPath) {
                        continue
                    }
                    visitedCanonicalPaths.insert(canonicalPath)

                    if current.depth < depthLimit {
                        queue.append(DirectoryEntry(url: fileURL, depth: current.depth + 1))
                    }
                    continue
                }

                // 3. Regular File (or symlink to regular file)
                let isRegularFile = resourceValues.isRegularFile == true || isSymbolicLink
                guard isRegularFile else {
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
                let checkURL = isSymbolicLink ? fileURL.resolvingSymlinksInPath() : fileURL
                if Self.isDatalessICloudFile(at: checkURL) {
                    evicted.append(fileURL)
                    continue
                }

                indexable.append(fileURL)
            }
        }

        return CrawlResult(
            indexableFiles: indexable,
            skippedEvicted: evicted,
            skippedOther: other
        )
    }
}
