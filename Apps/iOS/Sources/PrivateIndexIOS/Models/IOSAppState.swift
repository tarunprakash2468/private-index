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
        do {
            let dbURL = IOSContainerManager.shared.databaseURL
            let store = try VectorStore(at: dbURL)
            try store.createSchema()
            self.vectorStore = store

            let tokenizer: BertTokenizer
            if let t = try? BertTokenizer() {
                tokenizer = t
            } else {
                tokenizer = BertTokenizer(vocab: [:])
            }

            let model = CoreMLEmbeddingModel.loadDefaultModel(tokenizer: tokenizer)

            self.coordinator = IndexCoordinator(
                vectorStore: store,
                fileCrawler: FileCrawler(),
                textChunker: TextChunker(windowSize: 500, overlap: 100),
                embeddingModel: model
            )

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
        guard let coordinator = coordinator else { return }
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

        let dbURL = IOSContainerManager.shared.databaseURL

        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            syncStatusMessage = "Database not found in container. Index a folder or allow Mac to sync."
            isSyncingDatabase = false
            return
        }

        // Check if iCloud has a newer dataless version or active download
        let keys: Set<URLResourceKey> = [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]

        if let values = try? dbURL.resourceValues(forKeys: keys) {
            if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                syncStatusMessage = "Downloading latest index.sqlite from iCloud..."
                try? FileManager.default.startDownloadingUbiquitousItem(at: dbURL)
                try? await Task.sleep(nanoseconds: 500_000_000)
            } else if values.ubiquitousItemIsDownloading == true {
                syncStatusMessage = "iCloud is currently downloading the latest index.sqlite..."
            }
        }

        // Reconnect vector store to pick up any changes synced from Mac
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

        syncStatusMessage = "Database synced! (\(count) files indexed, \(sizeStr), modified: \(mtimeStr))"
        isSyncingDatabase = false
    }
}
