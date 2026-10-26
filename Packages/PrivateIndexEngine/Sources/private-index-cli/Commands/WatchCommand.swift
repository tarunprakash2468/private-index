import Foundation
import ArgumentParser
import PrivateIndexEngine

extension PrivateIndexCLI {
    struct Watch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "watch",
            abstract: "Run background watcher daemon (multi-folder & cloud auto-discovery)"
        )

        @Argument(help: "One or more directories to monitor (prompts interactively, defaults to All discovered locations)")
        var paths: [String] = []

        @Flag(
            name: [.customLong("no-download"), .customLong("skip-cloud-download")],
            help: "Disable automatic downloading of evicted cloud files"
        )
        var noDownload: Bool = false

        @Option(
            name: .customLong("min-free-space"),
            help: "Minimum free disk space buffer before downloading cloud files in GB (default: 10)"
        )
        var minFreeSpace: Int64 = 10

        @Flag(
            name: .customLong("install-launchagent"),
            help: "Generate and load launchd LaunchAgent to run 24/7 headlessly on login"
        )
        var installLaunchAgent: Bool = false

        @Flag(
            name: [.customLong("uninstall-launchagent"), .customLong("remove-launchagent")],
            help: "Unload and remove the background launchd LaunchAgent"
        )
        var uninstallLaunchAgent: Bool = false

        func run() async throws {
            if uninstallLaunchAgent {
                do {
                    try uninstallWatcherLaunchAgent()
                    return
                } catch {
                    print("\(ANSI.red)Error uninstalling LaunchAgent:\(ANSI.reset) \(error.localizedDescription)")
                    throw ExitCode.failure
                }
            }

            let resolvedPaths: [String]
            if !paths.isEmpty {
                resolvedPaths = paths.map { ($0 as NSString).expandingTildeInPath }
            } else {
                resolvedPaths = promptLocationSelection()
            }

            if installLaunchAgent {
                for p in resolvedPaths {
                    guard FileManager.default.fileExists(atPath: p) else {
                        print("\(ANSI.red)Error:\(ANSI.reset) Directory '\(p)' does not exist.")
                        throw ExitCode.failure
                    }
                }
                do {
                    try installWatcherLaunchAgent(paths: resolvedPaths, noDownload: noDownload)
                    return
                } catch {
                    print("\(ANSI.red)Error installing LaunchAgent:\(ANSI.reset) \(error.localizedDescription)")
                    throw ExitCode.failure
                }
            }

            let minBufferBytes = minFreeSpace * 1024 * 1024 * 1024
            let downloadPolicy = !noDownload
            do {
                try await runWatch(paths: resolvedPaths, downloadCloudFiles: downloadPolicy, minBufferBytes: minBufferBytes)
            } catch {
                print("\(ANSI.red)Watcher error:\(ANSI.reset) \(error.localizedDescription)")
                throw ExitCode.failure
            }
            dispatchMain()
        }
    }
}

func promptLocationSelection() -> [String] {
    let discovered = CloudStorageDetector.discoverLocations(includeHome: true)
    print("\(ANSI.bold)\(ANSI.cyan)Discovered locations:\(ANSI.reset)")
    for (idx, loc) in discovered.enumerated() {
        let tag = loc.isCloud ? "\(ANSI.cyan)[Cloud]\(ANSI.reset) " : "\(ANSI.dim)[Local]\(ANSI.reset) "
        print("  [\(idx + 1)] \(tag)\(ANSI.bold)\(loc.name)\(ANSI.reset): \(ANSI.dim)\(loc.url.path)\(ANSI.reset)")
    }
    print("\n\(ANSI.bold)Enter location(s) to watch\(ANSI.reset) [default: All]: ", terminator: "")
    fflush(stdout)

    if let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty {
        let lower = line.lowercased()
        if lower == "all" || lower == "a" {
            return discovered.map { $0.url.path }
        } else {
            let parts = line.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var selected: [String] = []
            for p in parts {
                if let num = Int(p), num >= 1, num <= discovered.count {
                    selected.append(discovered[num - 1].url.path)
                } else {
                    selected.append((p as NSString).expandingTildeInPath)
                }
            }
            return selected.isEmpty ? discovered.map { $0.url.path } : selected
        }
    } else {
        return discovered.map { $0.url.path }
    }
}

func runWatch(
    paths: [String],
    downloadCloudFiles: Bool = true,
    minBufferBytes: Int64 = CloudDownloadManager.defaultMinBufferBytes
) async throws {
    guard !paths.isEmpty else {
        print("\(ANSI.red)Error:\(ANSI.reset) No directories specified to watch.")
        exit(1)
    }

    var folderURLs: [URL] = []
    let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    let defaultDB = defaultDatabaseURL().standardizedFileURL.path

    for path in paths {
        let expanded = (path as NSString).expandingTildeInPath
        let folderURL = URL(fileURLWithPath: expanded)
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            print("\(ANSI.red)Error:\(ANSI.reset) Target directory '\(path)' does not exist.")
            exit(1)
        }

        // Validate folder doesn't encompass database to prevent loop
        // Home directory is exempted because the database resides in .private-index (hidden folder ignored by FileCrawler)
        if folderURL.standardizedFileURL.path != homePath && defaultDB.hasPrefix(folderURL.standardizedFileURL.path) {
            throw iCloudContainerManager.IsolationError.databaseContainedWithinTargetFolder(folderURL.path)
        }
        try iCloudContainerManager.shared.validateTargetFolder(folderURL)
        folderURLs.append(folderURL)
    }

    let (store, coordinator) = try setupEngine(downloadCloudFiles: downloadCloudFiles, minBufferBytes: minBufferBytes)
    let powerAssertion = PowerAssertion(name: "Private Index CLI Watcher")

    let cloudStatus = downloadCloudFiles
        ? "\(ANSI.green)Enabled (Auto-download when free space >= \(minBufferBytes / (1024 * 1024 * 1024))GB / 10%)\(ANSI.reset)"
        : "\(ANSI.yellow)Disabled (Cache Only)\(ANSI.reset)"

    let targetsList = folderURLs.map { "  • \(ANSI.bold)\($0.path)\(ANSI.reset)" }.joined(separator: "\n")

    print("""
    \(ANSI.bold)\(ANSI.cyan)Private Index Daemon\(ANSI.reset) — Live Multi-Folder Watching
    \(targetsList)
      • Debounce:         2.0s
      • Sleep Protection: Enabled (IOPMAssertion while indexing is active)
      • Cloud Downloads:  \(cloudStatus)
      • Database:         \(ANSI.dim)\(defaultDatabaseURL().path)\(ANSI.reset)

    \(ANSI.dim)Press Ctrl+C to terminate cleanly.\(ANSI.reset)
    """)

    final class WatcherHolder: @unchecked Sendable {
        var watcher: DirectoryWatcher?
    }
    let holder = WatcherHolder()

    // Clean shutdown on SIGINT and SIGTERM
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

    let shutdownHandler: @Sendable () -> Void = {
        print("\n\(ANSI.yellow)Shutdown signal received. Cleaning up...\(ANSI.reset)")
        holder.watcher?.stop()
        store.close()
        powerAssertion.release()
        print("\(ANSI.green)✔ FSEvent stream released. SQLite locks freed.\(ANSI.reset)")
        exit(0)
    }

    sigintSource.setEventHandler(handler: shutdownHandler)
    sigtermSource.setEventHandler(handler: shutdownHandler)
    sigintSource.resume()
    sigtermSource.resume()

    // Initial indexing pass
    print("\(ANSI.cyan)Running initial index pass...\(ANSI.reset)")
    powerAssertion.take()
    do {
        var totalScanned = 0
        var totalIndexed = 0
        var totalSkipped = 0
        var totalEvicted = 0
        let startTime = Date()

        for folderURL in folderURLs {
            let label = folderURL.lastPathComponent.isEmpty ? folderURL.path : folderURL.lastPathComponent
            let initialReport = try await coordinator.index(directoryURL: folderURL) { progress, message in
                let pct = Int(progress * 100)
                print("\r\(ANSI.dim)[\(label)] [\(pct)%] \(message)\(ANSI.reset)", terminator: "")
                fflush(stdout)
            }
            totalScanned += initialReport.filesScanned
            totalIndexed += initialReport.filesIndexed
            totalSkipped += initialReport.filesSkipped
            totalEvicted += initialReport.filesSkippedEvicted
        }
        let totalDuration = Date().timeIntervalSince(startTime)
        print("\r\u{001B}[K\(ANSI.green)✔ Initial scan complete:\(ANSI.reset) \(totalScanned) scanned, \(totalIndexed) indexed, \(totalSkipped) skipped (\(totalEvicted) cloud dataless processed) in \(String(format: "%.2f", totalDuration))s\n")
    } catch {
        print("\n\(ANSI.red)Initial indexing error:\(ANSI.reset) \(error.localizedDescription)")
    }
    powerAssertion.release()

    // Setup DirectoryWatcher with 2.0s debounce
    let targetsToWatch = folderURLs
    let watcher = DirectoryWatcher(
        debounceInterval: 2.0,
        onPathsChanged: { changedPaths in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            print("\(ANSI.dim)[\(timestamp)]\(ANSI.reset) \(ANSI.yellow)⚡ Detected \(changedPaths.count) file change(s):\(ANSI.reset)")

            for p in changedPaths.prefix(5) {
                let fileURL = URL(fileURLWithPath: p)
                if FileCrawler.isDatalessICloudFile(at: fileURL) {
                    if downloadCloudFiles {
                        print("  \(ANSI.cyan)⬇ Triggered cloud download: \(fileURL.lastPathComponent)\(ANSI.reset)")
                    } else {
                        print("  \(ANSI.dim)↷ Skipped dataless cloud file: \(fileURL.lastPathComponent)\(ANSI.reset)")
                    }
                } else {
                    print("  • \(ANSI.cyan)\(fileURL.lastPathComponent)\(ANSI.reset)")
                }
            }
            if changedPaths.count > 5 {
                print("  \(ANSI.dim)...and \(changedPaths.count - 5) more\(ANSI.reset)")
            }
        },
        onChange: {
            Task {
                powerAssertion.take()
                defer { powerAssertion.release() }

                do {
                    for folderURL in targetsToWatch {
                        let report = try await coordinator.index(directoryURL: folderURL)
                        if report.filesIndexed > 0 || report.filesDeleted > 0 {
                            let label = folderURL.lastPathComponent.isEmpty ? folderURL.path : folderURL.lastPathComponent
                            print("\(ANSI.green)✔ Incremental index updated [\(label)]:\(ANSI.reset) \(report.filesIndexed) indexed, \(report.filesDeleted) deleted, \(report.filesSkipped) unchanged in \(String(format: "%.2f", report.duration))s")
                        }
                    }
                } catch {
                    print("\(ANSI.red)Incremental indexing error:\(ANSI.reset) \(error.localizedDescription)")
                }
            }
        }
    )

    holder.watcher = watcher
    watcher.start(watching: targetsToWatch)
    let locWord = folderURLs.count == 1 ? "location" : "locations"
    print("\(ANSI.green)✔ Directory watcher active.\(ANSI.reset) Listening for filesystem events across \(folderURLs.count) \(locWord)...\n")
}

func runWatch(
    path: String,
    downloadCloudFiles: Bool = true,
    minBufferBytes: Int64 = CloudDownloadManager.defaultMinBufferBytes
) async throws {
    try await runWatch(paths: [path], downloadCloudFiles: downloadCloudFiles, minBufferBytes: minBufferBytes)
}
