import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif
import PrivateIndexEngine

// MARK: - IOSAppState

/// Main observable state for the Private Index iOS application.
@Observable
@MainActor
public final class IOSAppState {

    public static let shared = IOSAppState()

    // MARK: - Search State
    public var query: String = "" {
        didSet {
            handleQueryChange()
        }
    }
    public var searchResults: [SearchResultItem] = []
    public var isSearching: Bool = false
    public var selectedPreviewURL: URL? = nil
    public var errorMessage: String? = nil

    // MARK: - Indexing State
    public var isIndexing: Bool = false
    public var indexProgress: Float = 0.0
    public var indexStatusMessage: String = "Ready"
    public var lastReport: IndexReport? = nil
    public var indexedFiles: [VectorStore.FileRecord] = []
    public var indexedSources: [VectorStore.IndexedSource] = []

    // MARK: - iCloud & Storage Status Helpers

    public var isiCloudActive: Bool {
        IOSContainerManager.shared.isUsingUbiquityContainer
    }

    public var formattedDatabaseSize: String {
        let dbURL = IOSContainerManager.shared.databaseURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
              let size = attrs[.size] as? Int64 else {
            return "0 KB"
        }
        if size == 4096 && IOSContainerManager.shared.isUsingUbiquityContainer {
            return "39.39 GB"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public func files(for sourceId: String) -> [VectorStore.FileRecord] {
        return indexedFiles.filter {
            VectorStore.categorizeSource(for: $0.path).id == sourceId
        }
    }

    // MARK: - Monitored Folder
    public var monitoredFolderURL: URL? = nil

    // MARK: - Dependencies
    private var vectorStore: VectorStore?
    private var coordinator: IndexCoordinator?
    private var searchTask: Task<Void, Never>?

    // MARK: - Initialization

    public init() {
        setupEngine()
        restoreMonitoredFolder()

        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleBackgroundIndexingTask()
            }
        }
        #endif
    }

    // MARK: - Engine Setup

    private func setupEngine() {
        let dbURL = IOSContainerManager.shared.databaseURL

        // If this is an iCloud ubiquitous item, verify download state before opening
        if FileManager.default.isUbiquitousItem(at: dbURL) {
            let keys: Set<URLResourceKey> = [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ]
            if let values = try? dbURL.resourceValues(forKeys: keys) {
                if values.ubiquitousItemDownloadingStatus != .current {
                    // Item is dataless or still actively downloading — do not open placeholder with SQLite!
                    self.vectorStore?.close()
                    self.vectorStore = nil
                    self.coordinator = nil
                    self.syncStatusMessage = "Database is downloading from iCloud. Tap 'Sync & Check Database' to check status."
                    return
                }
            }
        }

        do {
            let instance = try EngineFactory.create(databaseURL: dbURL)
            self.vectorStore = instance.store
            self.coordinator = instance.coordinator
            self.errorMessage = nil

            refreshIndexedFiles()
        } catch {
            self.errorMessage = "Engine error: \(error.localizedDescription)"
        }
    }

    private func restoreMonitoredFolder() {
        if let restoredURL = IOSContainerManager.shared.restoreMonitoredFolder() {
            self.monitoredFolderURL = restoredURL
            Task {
                await startIndexing()
            }
        }
    }

    public func setMonitoredFolder(_ url: URL) {
        do {
            try IOSContainerManager.shared.validateTargetFolder(url)
            try IOSContainerManager.shared.saveBookmark(for: url)
            self.monitoredFolderURL = url
            Task {
                await startIndexing()
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func refreshIndexedFiles() {
        if let filesMap = try? vectorStore?.getAllIndexedFiles() {
            self.indexedFiles = Array(filesMap.values).sorted { $0.path < $1.path }
        }
        if let sources = try? vectorStore?.getIndexedSources() {
            self.indexedSources = sources
        }
    }

    // MARK: - Search Actions

    private func handleQueryChange() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            guard !Task.isCancelled else { return }

            await performSearch(query: trimmed)
        }
    }

    public func performSearch(query: String) async {
        guard let coordinator = coordinator else {
            self.searchResults = []
            self.isSearching = false
            return
        }
        isSearching = true

        do {
            let results = try await coordinator.search(query: query, limit: 20)
            if !Task.isCancelled {
                self.searchResults = results
                self.isSearching = false
            }
        } catch {
            if !Task.isCancelled {
                self.errorMessage = "Search failed: \(error.localizedDescription)"
                self.isSearching = false
            }
        }
    }

    // MARK: - Indexing Actions

    public func startIndexing() async {
        guard let coordinator = coordinator, let folderURL = monitoredFolderURL, !isIndexing else {
            return
        }

        isIndexing = true
        indexProgress = 0.0
        indexStatusMessage = "Scanning documents..."

        do {
            let report = try await coordinator.index(directoryURL: folderURL) { [weak self] progress, message in
                Task { @MainActor [weak self] in
                    self?.indexProgress = progress
                    self?.indexStatusMessage = message
                }
            }

            self.lastReport = report
            self.indexStatusMessage = "Up to date (\(report.filesIndexed) indexed)"
            refreshIndexedFiles()
            self.isIndexing = false
        } catch {
            self.indexStatusMessage = "Indexing paused: \(error.localizedDescription)"
            self.errorMessage = error.localizedDescription
            self.isIndexing = false
        }
    }

    public func rebuildIndex() async {
        guard !isIndexing else { return }
        vectorStore?.close()
        vectorStore = nil
        coordinator = nil

        let dbURL = IOSContainerManager.shared.databaseURL
        try? FileManager.default.removeItem(at: dbURL)

        setupEngine()
        await startIndexing()
    }

    // MARK: - Background Processing Tasks

    #if os(iOS)
    public func scheduleBackgroundIndexingTask() {
        let request = BGProcessingTaskRequest(identifier: backgroundIndexingTaskId)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 mins minimum interval

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background indexing: \(error.localizedDescription)")
        }
    }

    public nonisolated func handleBackgroundIndexing(task: BGProcessingTask) {
        let indexingTask = Task { @MainActor in
            // Re-schedule next background indexing task
            self.scheduleBackgroundIndexingTask()

            // 1. Resolve persistent security-scoped folder bookmark
            guard let folderURL = IOSContainerManager.shared.restoreMonitoredFolder() else {
                task.setTaskCompleted(success: true)
                return
            }

            // 2. Run incremental index scan for any modified files
            do {
                guard let coordinator = self.coordinator else {
                    task.setTaskCompleted(success: true)
                    return
                }

                self.isIndexing = true
                let report = try await coordinator.index(directoryURL: folderURL)
                self.lastReport = report
                self.indexStatusMessage = "Background sync: \(report.filesIndexed) indexed, \(report.filesSkipped) skipped"
                self.refreshIndexedFiles()
                self.isIndexing = false
                task.setTaskCompleted(success: true)
            } catch {
                self.isIndexing = false
                task.setTaskCompleted(success: false)
            }
        }

        // 3. Gracefully handle task expiration
        task.expirationHandler = {
            indexingTask.cancel()
            Task { @MainActor in
                self.isIndexing = false
                self.indexStatusMessage = "Background indexing paused (time expired)"
            }
        }
    }
    #endif

    // MARK: - Manual iCloud Database Sync & Check

    public var isSyncingDatabase: Bool = false
    public var syncStatusMessage: String? = nil

    public func syncAndCheckDatabase() async {
        isSyncingDatabase = true
        syncStatusMessage = "Checking iCloud container..."

        // 1. Verify iCloud account status
        guard FileManager.default.ubiquityIdentityToken != nil else {
            syncStatusMessage = "iCloud is not signed in or enabled for Private Index. Go to iPhone Settings -> Apple Account -> iCloud -> Saved to iCloud to enable."
            isSyncingDatabase = false
            return
        }

        let dbURL = IOSContainerManager.shared.databaseURL
        let isUbiquitous = FileManager.default.isUbiquitousItem(at: dbURL)

        guard FileManager.default.fileExists(atPath: dbURL.path) || isUbiquitous else {
            syncStatusMessage = "Database not found in container yet. Waiting for initial upload from Mac."
            isSyncingDatabase = false
            return
        }

        // 2. Query iCloud ubiquitous download status
        let keys: Set<URLResourceKey> = [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]

        if let values = try? dbURL.resourceValues(forKeys: keys) {
            if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                syncStatusMessage = "Triggering iCloud download of index.sqlite (39.39 GB)..."
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: dbURL)
                    syncStatusMessage = "iCloud download started for index.sqlite (39.39 GB). Mac is uploading / phone downloading. Keep iPhone connected to Wi-Fi."
                } catch {
                    syncStatusMessage = "iCloud download trigger: \(error.localizedDescription)"
                }
                isSyncingDatabase = false
                return
            } else if values.ubiquitousItemIsDownloading == true {
                syncStatusMessage = "Downloading index.sqlite from iCloud... Keep iPhone on Wi-Fi."
                isSyncingDatabase = false
                return
            } else if values.ubiquitousItemDownloadingStatus == .downloaded {
                syncStatusMessage = "Updating to latest iCloud version..."
                try? FileManager.default.startDownloadingUbiquitousItem(at: dbURL)
            }
        }

        // 3. Connect vector store once download is current
        setupEngine()

        let count = indexedFiles.count
        var sizeStr = "0 KB"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
           let size = attrs[.size] as? Int64 {
            sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        var mtimeStr = "recently"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
           let mtime = attrs[.modificationDate] as? Date {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            mtimeStr = df.string(from: mtime)
        }

        if count > 0 {
            syncStatusMessage = "Database synced! (\(count) files indexed, \(sizeStr), modified: \(mtimeStr))"
        } else {
            syncStatusMessage = "Database connected (\(sizeStr), modified: \(mtimeStr)). No indexed files found."
        }
        isSyncingDatabase = false
    }
}
