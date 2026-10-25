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

    public init(
        filesScanned: Int,
        filesIndexed: Int,
        filesSkipped: Int,
        filesDeleted: Int,
        chunksIndexed: Int,
        duration: TimeInterval
    ) {
        self.filesScanned = filesScanned
        self.filesIndexed = filesIndexed
        self.filesSkipped = filesSkipped
        self.filesDeleted = filesDeleted
        self.chunksIndexed = chunksIndexed
        self.duration = duration
    }
}

// MARK: - SearchMode

/// The search retrieval and ranking mode.
public enum SearchMode: String, Sendable, CaseIterable {
    /// Combined Reciprocal Rank Fusion (RRF) over vector similarity and BM25 keyword search.
    case hybrid
    /// Pure semantic cosine similarity across Core ML dense vector embeddings.
    case vector
    /// Pure full-text keyword matching using SQLite FTS5 BM25 ranking.
    case keyword
}

// MARK: - SearchResultItem

/// A user-facing search result combining semantic vector ranking, keyword matching, and file metadata.
public struct SearchResultItem: Identifiable, Sendable, Equatable {
    public let id: Int64
    public let fileId: Int64
    public let filePath: String
    /// Cosine distance (0.0 = identical, 1.0 = orthogonal).
    public let distance: Float
    /// Ranking score: combined RRF fusion score in hybrid mode, normalized cosine similarity in vector mode, or BM25 relevance in keyword mode.
    public let score: Float
    /// Text snippet indexed from this chunk.
    public let content: String
    /// The match source: "hybrid", "vector", or "keyword".
    public let matchType: String

    public init(
        id: Int64,
        fileId: Int64,
        filePath: String,
        distance: Float,
        score: Float,
        content: String,
        matchType: String = "hybrid"
    ) {
        self.id = id
        self.fileId = fileId
        self.filePath = filePath
        self.distance = distance
        self.score = score
        self.content = content
        self.matchType = matchType
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
            duration: duration
        )
    }

    // MARK: - Search

    /// Searches indexed documents using hybrid, vector, or keyword retrieval.
    ///
    /// Modes:
    /// - `.hybrid` (default): Executes dense Core ML vector search and SQLite FTS5 BM25 keyword search,
    ///   combining them with Reciprocal Rank Fusion:
    ///   Score(d) = (w_vector / (60 + rank_vector(d))) + (w_keyword / (60 + rank_keyword(d)))
    /// - `.vector`: Pure semantic cosine similarity ranking.
    /// - `.keyword`: Pure SQLite FTS5 BM25 full-text ranking.
    ///
    /// - Parameters:
    ///   - query: Freeform query text.
    ///   - limit: Maximum number of results to return (default 10).
    ///   - mode: Search mode: `.hybrid` (default), `.vector`, or `.keyword`.
    ///   - vectorWeight: Weight for vector similarity in RRF (default 0.5).
    ///   - keywordWeight: Weight for BM25 keyword matching in RRF (default 0.5).
    /// - Returns: Ranked search results with file paths, content snippets, scores, and match types.
    public func search(
        query: String,
        limit: Int = 10,
        mode: SearchMode = .hybrid,
        vectorWeight: Float = 0.5,
        keywordWeight: Float = 0.5
    ) async throws -> [SearchResultItem] {
        switch mode {
        case .vector:
            return try await searchVector(query: query, limit: limit)

        case .keyword:
            return try searchKeyword(query: query, limit: limit)

        case .hybrid:
            return try await searchHybrid(
                query: query,
                limit: limit,
                vectorWeight: vectorWeight,
                keywordWeight: keywordWeight
            )
        }
    }

    private func searchVector(query: String, limit: Int) async throws -> [SearchResultItem] {
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
                content: r.content,
                matchType: "vector"
            )
        }
    }

    private func searchKeyword(query: String, limit: Int) throws -> [SearchResultItem] {
        let rawResults = try vectorStore.searchBM25(query: query, limit: limit)
        // Normalize BM25 scores relative to the top hit (or 1.0 if empty/single)
        let bestScore = rawResults.first.map { abs($0.score) } ?? 1.0

        return rawResults.map { r in
            let normalizedScore = bestScore > 0 ? min(1.0, abs(r.score) / bestScore) : 1.0
            return SearchResultItem(
                id: r.chunkId,
                fileId: r.fileId,
                filePath: r.filePath,
                distance: 0.0,
                score: normalizedScore,
                content: r.content,
                matchType: "keyword"
            )
        }
    }

    private func searchHybrid(
        query: String,
        limit: Int,
        vectorWeight: Float,
        keywordWeight: Float
    ) async throws -> [SearchResultItem] {
        let candidateLimit = max(limit * 3, 50)

        // 1. Dense Vector Search
        let queryVector = try await embeddingModel.generateEmbedding(for: query)
        let vectorResults = try vectorStore.search(queryVector: queryVector, limit: candidateLimit)

        // 2. BM25 Full-Text Search
        let keywordResults = try vectorStore.searchBM25(query: query, limit: candidateLimit)

        // If both returned nothing, return empty
        if vectorResults.isEmpty && keywordResults.isEmpty {
            return []
        }

        // 3. Reciprocal Rank Fusion (RRF)
        struct Candidate {
            let chunkId: Int64
            let fileId: Int64
            let filePath: String
            var distance: Float
            let content: String
            var vectorRank: Int?
            var keywordRank: Int?
        }

        var candidates: [Int64: Candidate] = [:]

        for (idx, r) in vectorResults.enumerated() {
            let rank = idx + 1 // 1-based rank
            candidates[r.chunkId] = Candidate(
                chunkId: r.chunkId,
                fileId: r.fileId,
                filePath: r.filePath,
                distance: r.distance,
                content: r.content,
                vectorRank: rank,
                keywordRank: nil
            )
        }

        for (idx, r) in keywordResults.enumerated() {
            let rank = idx + 1 // 1-based rank
            if var existing = candidates[r.chunkId] {
                existing.keywordRank = rank
                candidates[r.chunkId] = existing
            } else {
                candidates[r.chunkId] = Candidate(
                    chunkId: r.chunkId,
                    fileId: r.fileId,
                    filePath: r.filePath,
                    distance: 1.0,
                    content: r.content,
                    vectorRank: nil,
                    keywordRank: rank
                )
            }
        }

        struct ScoredCandidate {
            let candidate: Candidate
            let fusionScore: Float
            let matchType: String
        }

        var scored: [ScoredCandidate] = []
        for candidate in candidates.values {
            var score: Float = 0.0
            if let vRank = candidate.vectorRank {
                score += vectorWeight / Float(60 + vRank)
            }
            if let kRank = candidate.keywordRank {
                score += keywordWeight / Float(60 + kRank)
            }

            let matchType: String
            if candidate.vectorRank != nil && candidate.keywordRank != nil {
                matchType = "hybrid"
            } else if candidate.vectorRank != nil {
                matchType = "vector"
            } else {
                matchType = "keyword"
            }

            scored.append(ScoredCandidate(
                candidate: candidate,
                fusionScore: score,
                matchType: matchType
            ))
        }

        scored.sort { a, b in
            if a.fusionScore != b.fusionScore {
                return a.fusionScore > b.fusionScore
            }
            return a.candidate.distance < b.candidate.distance
        }

        let top = scored.prefix(limit)
        return top.map { s in
            SearchResultItem(
                id: s.candidate.chunkId,
                fileId: s.candidate.fileId,
                filePath: s.candidate.filePath,
                distance: s.candidate.distance,
                score: s.fusionScore,
                content: s.candidate.content,
                matchType: s.matchType
            )
        }
    }
}
