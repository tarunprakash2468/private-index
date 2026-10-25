import Foundation
import SwiftUI
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

            let model: EmbeddingGenerator
            if let modelURL = Bundle.main.url(forResource: "all-MiniLM-L6-v2", withExtension: "mlmodelc"),
               let coreML = try? CoreMLEmbeddingModel(modelURL: modelURL, tokenizer: tokenizer) {
                model = coreML
            } else {
                model = MockEmbeddingModel()
            }

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
}
