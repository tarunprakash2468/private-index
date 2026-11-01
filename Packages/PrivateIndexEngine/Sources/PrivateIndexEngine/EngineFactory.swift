import Foundation

public struct EngineInstance: Sendable {
    public let store: VectorStore
    public let coordinator: IndexCoordinator

    public init(store: VectorStore, coordinator: IndexCoordinator) {
        self.store = store
        self.coordinator = coordinator
    }
}

public enum EngineFactory {
    public static func create(
        databaseURL: URL,
        readOnly: Bool = false,
        downloadCloudFiles: Bool = true,
        minDiskBufferBytes: Int64 = CloudDownloadManager.defaultMinBufferBytes,
        windowSize: Int = 500,
        overlap: Int = 100
    ) throws -> EngineInstance {
        let store = try VectorStore(at: databaseURL, readOnly: readOnly)
        if !readOnly {
            try store.createSchema()
        }

        let tokenizer: BertTokenizer
        if let t = try? BertTokenizer() {
            tokenizer = t
        } else {
            tokenizer = BertTokenizer(vocab: [:])
        }

        let model = CoreMLEmbeddingModel.loadDefaultModel(tokenizer: tokenizer)

        let coordinator = IndexCoordinator(
            vectorStore: store,
            fileCrawler: FileCrawler(downloadCloudFiles: downloadCloudFiles, minDiskBufferBytes: minDiskBufferBytes),
            textChunker: TextChunker(windowSize: windowSize, overlap: overlap),
            embeddingModel: model
        )

        return EngineInstance(store: store, coordinator: coordinator)
    }
}
