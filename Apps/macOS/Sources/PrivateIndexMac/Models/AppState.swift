import Foundation
import SwiftUI
import AppKit
import ServiceManagement
import PrivateIndexEngine

// MARK: - AppState

/// Main observable state for the Private Index macOS application.
@Observable
@MainActor
public final class AppState {

    public static let shared = AppState()

    // MARK: - Search State
    public var query: String = "" {
        didSet {
            handleQueryChange()
        }
    }
    public var searchResults: [SearchResultItem] = []
    public var selectedResultID: Int64? = nil
    public var isSearching: Bool = false
    public var errorMessage: String? = nil

    // MARK: - Indexing State
    public var isIndexing: Bool = false
    public var indexProgress: Float = 0.0
    public var indexStatusMessage: String = "Ready"
    public var lastReport: IndexReport? = nil
    public var totalFilesIndexed: Int = 0

    // MARK: - Preferences
    public var monitoredDirectoryURL: URL {
        didSet {
            UserDefaults.standard.set(monitoredDirectoryURL.path, forKey: "monitoredDirectoryPath")
            restartWatcherAndIndex()
        }
    }

    public var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        if SMAppService.mainApp.status != .enabled {
                            try SMAppService.mainApp.register()
                        }
                    } else {
                        if SMAppService.mainApp.status == .enabled {
                            try SMAppService.mainApp.unregister()
                        }
                    }
                } catch {
                    print("SMAppService registration failed: \(error.localizedDescription)")
                }
            }
            UserDefaults.standard.set(newValue, forKey: "launchAtLogin")
        }
    }

    public var preventSleepDuringIndexing: Bool {
        didSet {
            UserDefaults.standard.set(preventSleepDuringIndexing, forKey: "preventSleepDuringIndexing")
        }
    }

    // MARK: - Dependencies
    private var vectorStore: VectorStore?
    private var coordinator: IndexCoordinator?
    private var directoryWatcher: DirectoryWatcher?
    private var searchTask: Task<Void, Never>?

    // MARK: - Initialization

    public init() {
        if UserDefaults.standard.object(forKey: "preventSleepDuringIndexing") != nil {
            self.preventSleepDuringIndexing = UserDefaults.standard.bool(forKey: "preventSleepDuringIndexing")
        } else {
            self.preventSleepDuringIndexing = true
        }

        // Load persisted directory or use iCloud Drive Documents
        if let savedPath = UserDefaults.standard.string(forKey: "monitoredDirectoryPath"),
           FileManager.default.fileExists(atPath: savedPath) {
            self.monitoredDirectoryURL = URL(fileURLWithPath: savedPath)
        } else {
            self.monitoredDirectoryURL = iCloudContainerManager.defaultUserDocumentsURL
        }

        setupEngine()
        setupWatcher()

        // Kick off initial background index
        Task {
            await self.startIndexing()
        }
    }

    // MARK: - Engine Setup

    private func setupEngine() {
        do {
            let dbURL = iCloudContainerManager.shared.databaseURL
            let instance = try EngineFactory.create(databaseURL: dbURL)
            self.vectorStore = instance.store
            self.coordinator = instance.coordinator

            // Count existing files
            if let files = try? instance.store.getAllIndexedFiles() {
                self.totalFilesIndexed = files.count
            }
        } catch {
            self.errorMessage = "Engine initialization failed: \(error.localizedDescription)"
        }
    }

    private func setupWatcher() {
        directoryWatcher = DirectoryWatcher(
            debounceInterval: 2.0,
            onPathsChanged: { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let watcher = self.directoryWatcher, watcher.needsFullRescan {
                        watcher.needsFullRescan = false
                        await self.startIndexing()
                    }
                }
            },
            onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.startIndexing()
                }
            }
        )
        directoryWatcher?.start(watching: monitoredDirectoryURL)
    }

    private func restartWatcherAndIndex() {
        directoryWatcher?.start(watching: monitoredDirectoryURL)
        Task {
            await startIndexing()
        }
    }

    // MARK: - Search Actions

    private func handleQueryChange() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            searchResults = []
            selectedResultID = nil
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms typing debounce
            guard !Task.isCancelled else { return }

            await performSearch(query: trimmed)
        }
    }

    public func performSearch(query: String) async {
        guard let coordinator = coordinator else { return }
        isSearching = true

        do {
            let results = try await coordinator.search(query: query, limit: 15)
            if !Task.isCancelled {
                self.searchResults = results
                if let first = results.first {
                    self.selectedResultID = first.id
                }
                self.isSearching = false
            }
        } catch {
            if !Task.isCancelled {
                self.errorMessage = "Search error: \(error.localizedDescription)"
                self.isSearching = false
            }
        }
    }

    // MARK: - Indexing Actions

    public func startIndexing() async {
        guard let coordinator = coordinator, !isIndexing else { return }
        isIndexing = true
        indexProgress = 0.0
        indexStatusMessage = "Scanning..."

        let powerAssertion = PowerAssertion(name: "Private Index macOS Indexing")
        if preventSleepDuringIndexing {
            powerAssertion.take()
        }
        defer {
            powerAssertion.release()
        }

        do {
            try iCloudContainerManager.shared.validateTargetFolder(monitoredDirectoryURL)

            let report = try await coordinator.index(directoryURL: monitoredDirectoryURL) { [weak self] progress, message in
                Task { @MainActor [weak self] in
                    self?.indexProgress = progress
                    self?.indexStatusMessage = message
                }
            }

            self.lastReport = report
            self.indexStatusMessage = "Up to date (\(report.filesIndexed) indexed, \(report.filesSkipped) skipped)"
            if let files = try? vectorStore?.getAllIndexedFiles() {
                self.totalFilesIndexed = files.count
            }
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

        let dbURL = iCloudContainerManager.shared.databaseURL
        try? FileManager.default.removeItem(at: dbURL)

        setupEngine()
        await startIndexing()
    }

    // MARK: - File Actions

    public func openFile(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    public func revealInFinder(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
