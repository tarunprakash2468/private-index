import Foundation

// MARK: - IndexReport

/// Performance and change metrics returned after an indexing run.
public struct IndexReport: Sendable, Equatable {
    /// Total number of files evaluated during the crawl.
    public let filesScanned: Int
    /// Number of new or modified files successfully chunked and embedded.
    public let filesIndexed: Int
    /// Number of unchanged files skipped based on mtime and size comparison.
    public let filesSkipped: Int
    /// Number of previously indexed files removed from the index because they no longer exist on disk.
    public let filesDeleted: Int
    /// Total number of text chunks created and indexed in this run.
    public let chunksIndexed: Int
    /// Total execution duration in seconds.
    public let duration: TimeInterval
    /// Number of evicted / dataless iCloud files skipped to prevent unwanted downloads.
    public let filesSkippedEvicted: Int

    public init(
        filesScanned: Int,
        filesIndexed: Int,
        filesSkipped: Int,
        filesDeleted: Int,
        chunksIndexed: Int,
        duration: TimeInterval,
        filesSkippedEvicted: Int = 0
    ) {
        self.filesScanned = filesScanned
        self.filesIndexed = filesIndexed
        self.filesSkipped = filesSkipped
        self.filesDeleted = filesDeleted
        self.chunksIndexed = chunksIndexed
        self.duration = duration
        self.filesSkippedEvicted = filesSkippedEvicted
    }
}

// MARK: - SearchResultItem

/// A user-facing search result combining semantic vector ranking and file metadata.
public struct SearchResultItem: Identifiable, Sendable, Equatable {
    public let id: Int64
    public let fileId: Int64
    public let filePath: String
    /// Cosine distance (0.0 = identical, 1.0 = orthogonal).
    public let distance: Float
    /// Normalized cosine similarity score (1.0 = identical, 0.0 = orthogonal/opposite).
    public let score: Float
    /// Text snippet indexed from this chunk.
    public let content: String

    public init(
        id: Int64,
        fileId: Int64,
        filePath: String,
        distance: Float,
        score: Float,
        content: String
    ) {
        self.id = id
        self.fileId = fileId
        self.filePath = filePath
        self.distance = distance
        self.score = score
        self.content = content
    }
}

// MARK: - IndexCoordinator

/// Orchestrates the semantic indexing and search pipeline.
///
/// Thread Safety: `IndexCoordinator` is an actor, isolating mutable state and serializing
/// database write and read access.
public actor IndexCoordinator {

    private let vectorStore: VectorStore
    private let fileCrawler: FileCrawler
    private let textChunker: TextChunker
    private let embeddingModel: EmbeddingGenerator

    public init(
        vectorStore: VectorStore,
        fileCrawler: FileCrawler = FileCrawler(),
        textChunker: TextChunker = TextChunker(),
        embeddingModel: EmbeddingGenerator
    ) {
        self.vectorStore = vectorStore
        self.fileCrawler = fileCrawler
        self.textChunker = textChunker
        self.embeddingModel = embeddingModel
    }

    // MARK: - Indexing

    /// Scans, chunks, embeds, and indexes files under `directoryURL`.
    ///
    /// Incremental Behavior:
    /// - Files whose `mtime` and `size` match `indexed_files` records are skipped.
    /// - Files that were previously indexed under `directoryURL` but are now deleted on disk
    ///   have their records and vector embeddings pruned.
    /// - Modified files have their old chunks removed and new chunks embedded.
    ///
    /// - Parameters:
    ///   - directoryURL: Directory to crawl.
    ///   - onProgress: Optional closure receiving progress fraction (0.0 to 1.0) and status message.
    /// - Returns: An `IndexReport` detailing files indexed, skipped, deleted, and duration.
    public func index(
        directoryURL: URL,
        onProgress: (@Sendable (Float, String) -> Void)? = nil
    ) async throws -> IndexReport {
        let startTime = Date()

        onProgress?(0.0, "Scanning directory...")
        let crawlResult = fileCrawler.crawl(rootURL: directoryURL)
        let indexableFiles = crawlResult.indexableFiles

        let scannedPathSet = Set(indexableFiles.map { $0.standardizedFileURL.path })
        let rootPrefix = directoryURL.standardizedFileURL.path

        // Load existing index records
        let existingFiles = try vectorStore.getAllIndexedFiles()

        // 1. Prune files that no longer exist under this directory root
        var deletedCount = 0
        for (path, record) in existingFiles {
            if path.hasPrefix(rootPrefix) && !scannedPathSet.contains(path) {
                try vectorStore.deleteFile(id: record.id)
                deletedCount += 1
            }
        }

        // 2. Identify new or modified files vs. unchanged files
        var filesToProcess: [(url: URL, path: String, mtime: Date, size: Int64, existingId: Int64?)] = []
        var skippedCount = 0

        for fileURL in indexableFiles {
            let path = fileURL.standardizedFileURL.path
            let resourceValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = resourceValues?.contentModificationDate ?? Date()
            let size = Int64(resourceValues?.fileSize ?? 0)

            if let existing = existingFiles[path] {
                // If modification date and size match, skip re-indexing
                if abs(existing.mtime.timeIntervalSince(mtime)) < 0.001 && existing.size == size {
                    skippedCount += 1
                    continue
                }
                filesToProcess.append((url: fileURL, path: path, mtime: mtime, size: size, existingId: existing.id))
            } else {
                filesToProcess.append((url: fileURL, path: path, mtime: mtime, size: size, existingId: nil))
            }
        }

        // 3. Process each changed or new file
        var indexedCount = 0
        var totalChunksIndexed = 0
        let totalToProcess = filesToProcess.count

        for (index, item) in filesToProcess.enumerated() {
            let progress = totalToProcess > 0 ? Float(index) / Float(totalToProcess) : 1.0
            onProgress?(progress, "Indexing \(item.url.lastPathComponent)...")

            // Read file content (plain text, markdown, source code, or PDF)
            guard let content = DocumentReader.extractText(from: item.url), !content.isEmpty else {
                continue
            }

            let chunks = textChunker.chunk(content)
            guard !chunks.isEmpty else {
                continue
            }

            // Generate embeddings for all chunks in the file
            let embeddings = try await embeddingModel.generateEmbeddings(for: chunks)

            // If replacing an existing file, delete old records first
            if let existingId = item.existingId {
                try vectorStore.deleteFile(id: existingId)
            }

            // Insert file record
            let fileId = try vectorStore.insertFile(
                path: item.path,
                mtime: item.mtime,
                size: item.size
            )

            // Insert chunks and vector embeddings
            for (chunkIdx, (chunkText, embedding)) in zip(chunks, embeddings).enumerated() {
                try vectorStore.insertChunk(
                    fileId: fileId,
                    chunkIndex: chunkIdx,
                    content: chunkText,
                    embedding: embedding
                )
                totalChunksIndexed += 1
            }

            indexedCount += 1
        }

        onProgress?(1.0, "Indexing complete")

        let duration = Date().timeIntervalSince(startTime)
        return IndexReport(
            filesScanned: indexableFiles.count,
            filesIndexed: indexedCount,
            filesSkipped: skippedCount,
            filesDeleted: deletedCount,
            chunksIndexed: totalChunksIndexed,
            duration: duration,
            filesSkippedEvicted: crawlResult.skippedEvicted.count
        )
    }

    // MARK: - Search

    /// Performs natural language semantic search across all indexed chunks.
    ///
    /// - Parameters:
    ///   - query: Freeform query text.
    ///   - limit: Maximum number of results to return (default 10).
    /// - Returns: Ranked search results with file paths, content snippets, and similarity scores.
    public func search(query: String, limit: Int = 10) async throws -> [SearchResultItem] {
        let queryVector = try await embeddingModel.generateEmbedding(for: query)
        let rawResults = try vectorStore.search(queryVector: queryVector, limit: limit)

        return rawResults.map { r in
            let score = max(0.0, 1.0 - r.distance)
            return SearchResultItem(
                id: r.chunkId,
                fileId: r.fileId,
                filePath: r.filePath,
                distance: r.distance,
                score: score,
                content: r.content
            )
        }
    }
}
