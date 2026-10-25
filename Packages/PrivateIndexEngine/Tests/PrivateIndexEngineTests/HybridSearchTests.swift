import XCTest
@testable import PrivateIndexEngine

// MARK: - SemanticConceptMockEmbeddingModel

/// A deterministic mock embedding model for testing concept matching and vector search.
///
/// Maps text containing specific conceptual keywords to known clustered vector spaces,
/// while other text gets pseudo-random orthogonal vectors.
private final class SemanticConceptMockEmbeddingModel: EmbeddingGenerator, @unchecked Sendable {
    let embeddingDimension: Int = 384
    let maxSequenceLength: Int = 128

    // Conceptual clusters
    private let spaceConceptVector: [Float]
    private let bakingConceptVector: [Float]

    init() {
        var space = [Float](repeating: 0.0, count: 384)
        for i in 0..<50 { space[i] = 1.0 }
        let spaceNorm = sqrt(space.reduce(0) { $0 + $1 * $1 })
        self.spaceConceptVector = space.map { $0 / spaceNorm }

        var baking = [Float](repeating: 0.0, count: 384)
        for i in 50..<100 { baking[i] = 1.0 }
        let bakingNorm = sqrt(baking.reduce(0) { $0 + $1 * $1 })
        self.bakingConceptVector = baking.map { $0 / bakingNorm }
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        let lower = text.lowercased()

        if lower.contains("astronomy") || lower.contains("telescope") || lower.contains("galaxy") || lower.contains("celestial") || lower.contains("astrophysics") || lower.contains("space") {
            return spaceConceptVector
        }

        if lower.contains("baking") || lower.contains("sourdough") || lower.contains("bread") || lower.contains("flour") || lower.contains("oven") || lower.contains("yeast") {
            return bakingConceptVector
        }

        // Default: deterministic hash vector
        var vector = [Float](repeating: 0.0, count: embeddingDimension)
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        var normSq: Float = 0
        for i in 100..<embeddingDimension {
            hash = hash &* 6364136223846793005 &+ 1442695040888963407
            let val = Float(Int32(truncatingIfNeeded: hash >> 32)) / Float(Int32.max)
            vector[i] = val
            normSq += val * val
        }
        let norm = sqrt(max(normSq, 1e-12))
        return vector.map { $0 / norm }
    }
}

// MARK: - HybridSearchTests

final class HybridSearchTests: XCTestCase {

    private var tempDir: URL!
    private var vectorStore: VectorStore!
    private var coordinator: IndexCoordinator!
    private var embeddingModel: SemanticConceptMockEmbeddingModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HybridSearchTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        vectorStore = try VectorStore(at: nil)  // in-memory
        try vectorStore.createSchema()

        embeddingModel = SemanticConceptMockEmbeddingModel()
        coordinator = IndexCoordinator(
            vectorStore: vectorStore,
            fileCrawler: FileCrawler(),
            textChunker: TextChunker(windowSize: 300, overlap: 50),
            embeddingModel: embeddingModel
        )
    }

    override func tearDownWithError() throws {
        vectorStore?.close()
        vectorStore = nil
        coordinator = nil
        embeddingModel = nil
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Requirement 4.1: Exact Symbol / Keyword Matching

    func testExactSymbolAndKeywordMatchingWithNovelTerms() async throws {
        let uuidFile = tempDir.appendingPathComponent("UUIDConfig.swift")
        let errorCodeFile = tempDir.appendingPathComponent("SystemErrors.swift")
        let functionFile = tempDir.appendingPathComponent("TransactionService.swift")

        let novelUUID = "d3b07384-d113-4674-bc48-c2b48d88e0b9"
        let novelErrorCode = "ERR_AUTH_EXPIRED_TOKEN_9021"
        let novelFunction = "executeDistributedTransactionCoordinator"

        try "let sessionIdentifier = \"\(novelUUID)\"".write(to: uuidFile, atomically: true, encoding: .utf8)
        try "enum AuthError: String { case code = \"\(novelErrorCode)\" }".write(to: errorCodeFile, atomically: true, encoding: .utf8)
        try "func \(novelFunction)() throws -> Bool { return true }".write(to: functionFile, atomically: true, encoding: .utf8)

        let report = try await coordinator.index(directoryURL: tempDir)
        XCTAssertEqual(report.filesIndexed, 3)

        // 1. Exact UUID matching
        let uuidKeywordResults = try await coordinator.search(query: novelUUID, limit: 5, mode: .keyword)
        XCTAssertFalse(uuidKeywordResults.isEmpty, "Keyword search should find novel UUID")
        XCTAssertEqual(uuidKeywordResults[0].filePath, uuidFile.standardizedFileURL.path)
        XCTAssertEqual(uuidKeywordResults[0].matchType, "keyword")

        let uuidHybridResults = try await coordinator.search(query: novelUUID, limit: 5, mode: .hybrid)
        XCTAssertFalse(uuidHybridResults.isEmpty, "Hybrid search should find novel UUID")
        XCTAssertEqual(uuidHybridResults[0].filePath, uuidFile.standardizedFileURL.path)

        // 2. Exact error code matching
        let errorKeywordResults = try await coordinator.search(query: novelErrorCode, limit: 5, mode: .keyword)
        XCTAssertFalse(errorKeywordResults.isEmpty, "Keyword search should find novel error code")
        XCTAssertEqual(errorKeywordResults[0].filePath, errorCodeFile.standardizedFileURL.path)

        let errorHybridResults = try await coordinator.search(query: novelErrorCode, limit: 5, mode: .hybrid)
        XCTAssertFalse(errorHybridResults.isEmpty, "Hybrid search should find novel error code")
        XCTAssertEqual(errorHybridResults[0].filePath, errorCodeFile.standardizedFileURL.path)

        // 3. Exact function name matching
        let funcKeywordResults = try await coordinator.search(query: novelFunction, limit: 5, mode: .keyword)
        XCTAssertFalse(funcKeywordResults.isEmpty, "Keyword search should find novel function name")
        XCTAssertEqual(funcKeywordResults[0].filePath, functionFile.standardizedFileURL.path)

        let funcHybridResults = try await coordinator.search(query: novelFunction, limit: 5, mode: .hybrid)
        XCTAssertFalse(funcHybridResults.isEmpty, "Hybrid search should find novel function name")
        XCTAssertEqual(funcHybridResults[0].filePath, functionFile.standardizedFileURL.path)
    }

    // MARK: - Requirement 4.2: Semantic Concept Matching

    func testSemanticConceptMatching() async throws {
        let astronomyFile = tempDir.appendingPathComponent("DeepSky.txt")
        let bakingFile = tempDir.appendingPathComponent("Recipe.txt")

        // astronomyFile contains "astronomy telescope astrophysics"
        try "Observational astronomy utilizes large telescope arrays to study astrophysics.".write(
            to: astronomyFile,
            atomically: true,
            encoding: .utf8
        )
        // bakingFile contains "baking sourdough flour oven"
        try "Artisanal baking of sourdough bread requires high heat in an oven with wheat flour.".write(
            to: bakingFile,
            atomically: true,
            encoding: .utf8
        )

        _ = try await coordinator.index(directoryURL: tempDir)

        // Search with conceptual query: "celestial galaxy space" (no exact words from astronomyFile, but maps to space concept)
        let vectorResults = try await coordinator.search(query: "celestial galaxy space", limit: 5, mode: .vector)
        XCTAssertFalse(vectorResults.isEmpty, "Vector search should retrieve conceptual matches")
        XCTAssertEqual(vectorResults[0].filePath, astronomyFile.standardizedFileURL.path)
        XCTAssertEqual(vectorResults[0].matchType, "vector")
        XCTAssertLessThan(vectorResults[0].distance, 0.01)

        // In keyword mode, there are 0 matches since none of the words match literally
        let keywordResults = try await coordinator.search(query: "celestial galaxy space", limit: 5, mode: .keyword)
        XCTAssertTrue(keywordResults.isEmpty, "Keyword search should find 0 hits without exact term matches")

        // In hybrid mode, the semantic match is preserved and returned
        let hybridResults = try await coordinator.search(query: "celestial galaxy space", limit: 5, mode: .hybrid)
        XCTAssertFalse(hybridResults.isEmpty, "Hybrid search should return semantic matches even without keyword hits")
        XCTAssertEqual(hybridResults[0].filePath, astronomyFile.standardizedFileURL.path)
        XCTAssertEqual(hybridResults[0].matchType, "vector")
    }

    // MARK: - Requirement 4.3: Hybrid Mode Ranks Document with Both Hits at Top

    func testHybridModeRanksDocumentWithBothSemanticAndKeywordHitsAtTop() async throws {
        let fileBoth = tempDir.appendingPathComponent("DocBoth.txt")
        let fileSemanticOnly = tempDir.appendingPathComponent("DocSemanticOnly.txt")
        let fileKeywordOnly = tempDir.appendingPathComponent("DocKeywordOnly.txt")

        let targetSymbol = "TOKEN_XYZ_8841_ALPHA"

        // fileBoth: Conceptual space relevance + exact keyword symbol
        try "Astrophysics and telescope astronomy observation data packet: \(targetSymbol)".write(
            to: fileBoth,
            atomically: true,
            encoding: .utf8
        )

        // fileSemanticOnly: Conceptual space relevance, NO keyword symbol
        try "Astrophysics and telescope astronomy deep space exploration survey.".write(
            to: fileSemanticOnly,
            atomically: true,
            encoding: .utf8
        )

        // fileKeywordOnly: NO space relevance (baking concept), BUT exact keyword symbol
        try "Sourdough baking flour recipe tracking reference identifier: \(targetSymbol)".write(
            to: fileKeywordOnly,
            atomically: true,
            encoding: .utf8
        )

        _ = try await coordinator.index(directoryURL: tempDir)

        // Query combining semantic space concept (celestial) + exact keyword symbol
        let query = "celestial \(targetSymbol)"
        let results = try await coordinator.search(query: query, limit: 10, mode: .hybrid)

        XCTAssertGreaterThanOrEqual(results.count, 3, "All three documents should be retrieved")

        // Top document MUST be fileBoth because it matches BOTH dense vector and BM25 full-text
        XCTAssertEqual(
            results[0].filePath,
            fileBoth.standardizedFileURL.path,
            "Hybrid mode must rank document with both semantic and keyword hits at the very top"
        )
        XCTAssertEqual(results[0].matchType, "hybrid", "Match type should be 'hybrid' when present in both lists")

        // The top score must be strictly greater than subsequent scores
        XCTAssertGreaterThan(
            results[0].score,
            results[1].score,
            "Document matching both vector and keyword should have a higher RRF score than single-source matches"
        )
    }

    // MARK: - Requirement 4.4: Configurable Weighting

    func testConfigurableWeightingShiftsRanking() async throws {
        let fileVectorBiased = tempDir.appendingPathComponent("VectorBiased.txt")
        let fileKeywordBiased = tempDir.appendingPathComponent("KeywordBiased.txt")

        let symbol = "KEYWORD_SPECIAL_CODE_77"

        // Vector-biased file: matches space concept, but no keyword symbol
        try "Deep space astronomy telescope sky catalog.".write(
            to: fileVectorBiased,
            atomically: true,
            encoding: .utf8
        )

        // Keyword-biased file: matches exact keyword symbol, but unrelated concept
        try "Accounting balance register entry: \(symbol)".write(
            to: fileKeywordBiased,
            atomically: true,
            encoding: .utf8
        )

        _ = try await coordinator.index(directoryURL: tempDir)

        // Query: "celestial" triggers the space vector concept without literal word match in fileVectorBiased
        let query = "celestial \(symbol)"

        // 1. High vector weight (0.99 vector, 0.01 keyword) -> VectorBiased ranks top
        let vectorHeavyResults = try await coordinator.search(
            query: query,
            limit: 5,
            mode: .hybrid,
            vectorWeight: 0.99,
            keywordWeight: 0.01
        )
        XCTAssertEqual(vectorHeavyResults[0].filePath, fileVectorBiased.standardizedFileURL.path)

        // 2. High keyword weight (0.01 vector, 0.99 keyword) -> KeywordBiased ranks top
        let keywordHeavyResults = try await coordinator.search(
            query: query,
            limit: 5,
            mode: .hybrid,
            vectorWeight: 0.01,
            keywordWeight: 0.99
        )
        XCTAssertEqual(keywordHeavyResults[0].filePath, fileKeywordBiased.standardizedFileURL.path)
    }

    // MARK: - Requirement 1: FTS5 Index Synchronization & Reset

    func testFTS5SynchronizationAndReset() throws {
        let fileId = try vectorStore.insertFile(path: "/docs/readme.md", mtime: Date(), size: 100)
        let dummyVector = [Float](repeating: 0.01, count: 384)

        let chunkId = try vectorStore.insertChunk(
            fileId: fileId,
            chunkIndex: 0,
            content: "UniqueKeywordForSyncTest content snippet",
            embedding: dummyVector
        )
        XCTAssertGreaterThan(chunkId, 0)

        // Verify FTS table immediately finds it via trigger
        let results = try vectorStore.searchBM25(query: "UniqueKeywordForSyncTest", limit: 5)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].chunkId, chunkId)
        XCTAssertEqual(results[0].filePath, "/docs/readme.md")

        // Deleting file must purge from FTS table
        try vectorStore.deleteFile(id: fileId)
        let postDeleteResults = try vectorStore.searchBM25(query: "UniqueKeywordForSyncTest", limit: 5)
        XCTAssertTrue(postDeleteResults.isEmpty, "FTS entry must be removed when file is deleted")

        // Re-insert and test store.reset()
        let fileId2 = try vectorStore.insertFile(path: "/docs/reset_test.md", mtime: Date(), size: 200)
        _ = try vectorStore.insertChunk(
            fileId: fileId2,
            chunkIndex: 0,
            content: "TermToResetImmediately",
            embedding: dummyVector
        )
        XCTAssertFalse(try vectorStore.searchBM25(query: "TermToResetImmediately").isEmpty)

        try vectorStore.reset()
        XCTAssertTrue(try vectorStore.searchBM25(query: "TermToResetImmediately").isEmpty, "Reset must clear all FTS entries")
        XCTAssertTrue(try vectorStore.getAllIndexedFiles().isEmpty, "Reset must clear indexed files")
    }
}
