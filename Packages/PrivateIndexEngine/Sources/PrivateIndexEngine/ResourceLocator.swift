import Foundation

/// Safe resource locator for PrivateIndexEngine that avoids fatalError traps when bundles are missing.
public enum ResourceLocator {
    /// The name of the SwiftPM-generated resource bundle for this module.
    public static let bundleName = "PrivateIndexEngine_PrivateIndexEngine.bundle"

    /// Safely attempts to locate the resource bundle containing vocabulary and model files.
    public static var engineBundle: Bundle? {
        let fileManager = FileManager.default

        // Candidate search paths: we resolve directly using Bundle(url:) to avoid SwiftPM's
        // auto-generated Bundle.module trap which crashes if invoked via a symlinked binary.
        var candidates: [URL?] = [
            // 1. Executable-relative (resolves symlinks, e.g. /opt/homebrew/bin/pi -> /opt/homebrew/Cellar/.../bin/pi)
            Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent(),
            Bundle.main.executableURL?.deletingLastPathComponent(),

            // 2. Class / module-relative (resolves via dyld to loaded binary/framework)
            Bundle(for: BertTokenizer.self).bundleURL,
            Bundle(for: BertTokenizer.self).bundleURL.resolvingSymlinksInPath(),
            Bundle(for: BertTokenizer.self).resourceURL,
            Bundle(for: BertTokenizer.self).bundleURL.deletingLastPathComponent(),

            // 3. Main bundle paths (e.g. app Contents/Resources or Contents/MacOS)
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.resolvingSymlinksInPath(),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
            Bundle.main.bundleURL.deletingLastPathComponent(),
            Bundle.main.bundleURL.appendingPathComponent("Resources"),
            Bundle.main.bundleURL.appendingPathComponent("bin"),

            // 4. Standard Homebrew / system locations
            URL(fileURLWithPath: "/opt/homebrew/share/private-index"),
            URL(fileURLWithPath: "/usr/local/share/private-index"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin")
        ]

        #if DEBUG
        if let envPath = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"]
            ?? ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_URL"] {
            candidates.insert(URL(fileURLWithPath: envPath), at: 0)
        }
        #endif

        for candidate in candidates {
            guard let candidate = candidate else { continue }
            let bundleURL = candidate.appendingPathComponent(bundleName)
            if fileManager.fileExists(atPath: bundleURL.path), let bundle = Bundle(url: bundleURL) {
                return bundle
            }
        }
        return nil
    }

    /// Safely finds a file URL for a named resource with an extension.
    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        // 1. Try locating in the discovered engine bundle
        if let bundle = engineBundle, let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }

        // 2. Try all loaded bundles
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }

        // 3. Try main bundle
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }

        // 4. Try standard search paths directly (e.g. loose vocab.txt in Homebrew share or bin)
        let fileName = ext.isEmpty ? name : "\(name).\(ext)"
        let searchDirs: [URL?] = [
            Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent(),
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.appendingPathComponent("Resources"),
            URL(fileURLWithPath: "/opt/homebrew/share/private-index"),
            URL(fileURLWithPath: "/usr/local/share/private-index"),
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin")
        ]
        for dir in searchDirs {
            guard let dir = dir else { continue }
            let fileURL = dir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }

        return nil
    }
}
