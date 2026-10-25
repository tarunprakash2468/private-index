import XCTest
@testable import PrivateIndexEngine

final class VectorStoreTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a normalized 384-dim vector with a specific pattern.
    /// Sets `value` at `index` and 0.0 elsewhere, then L2-normalizes.
    private func makeUnitVector(index: Int, dimension: Int = 384) -> [Float] {
        var vec = [Float](repeating: 0.0, count: dimension)
        vec[index] = 1.0
        return vec
    }

    /// Creates a 384-dim vector with specific values at given indices, then normalizes.
    private func makeVector(values: [(Int, Float)], dimension: Int = 384) -> [Float] {
        var vec = [Float](repeating: 0.0, count: dimension)
        for (idx, val) in values {
            vec[idx] = val
        }
        // L2 normalize
        let norm = sqrt(vec.reduce(0) { $0 + $1 * $1 })
        if norm > 0 {
            vec = vec.map { $0 / norm }
        }
        return vec
    }

    // MARK: - Schema Creation

    func testSchemaCreation() throws {
        let store = try VectorStore(at: nil)  // in-memory
        try store.createSchema()

        // Verify tables exist by querying sqlite_master
        // (We'll do a simple search query that would fail if tables don't exist)
        let results = try store.search(
            queryVector: [Float](repeating: 0.01, count: 384),
            limit: 1
        )
        XCTAssertEqual(results.count, 0, "Empty database should return no results")
        store.close()
    }

    // MARK: - Insert & Retrieve

    func testInsertAndRetrieve() throws {
        let store = try VectorStore(at: nil)
        try store.createSchema()

        let fileId = try store.insertFile(
            path: "/test/document.txt",
            mtime: Date(),
            size: 1024
        )
        XCTAssertGreaterThan(fileId, 0, "File ID should be > 0")

        let embedding = makeUnitVector(index: 0)
        let chunkId = try store.insertChunk(
            fileId: fileId,
            chunkIndex: 0,
            content: "Test chunk content",
            embedding: embedding
        )
        XCTAssertGreaterThan(chunkId, 0, "Chunk ID should be > 0")

        // Search with the same vector — should find it
        let results = try store.search(queryVector: embedding, limit: 5)
        XCTAssertEqual(results.count, 1, "Should find exactly 1 result")
        XCTAssertEqual(results[0].chunkId, chunkId)
        XCTAssertEqual(results[0].content, "Test chunk content")
        // Distance should be ~0 for identical vectors
        XCTAssertLessThan(results[0].distance, 0.01, "Distance to self should be near 0")

        store.close()
    }

    // MARK: - Cosine Distance Ranking

    func testCosineSearchRanking() throws {
        let store = try VectorStore(at: nil)
        try store.createSchema()

        let fileId = try store.insertFile(path: "/test/file.txt", mtime: Date(), size: 100)

        // v1: unit vector along dimension 0 → [1, 0, 0, ..., 0]
        let v1 = makeUnitVector(index: 0)
        try store.insertChunk(fileId: fileId, chunkIndex: 0, content: "chunk-v1", embedding: v1)

        // v2: unit vector along dimension 1 → [0, 1, 0, ..., 0] (orthogonal to v1)
        let v2 = makeUnitVector(index: 1)
        try store.insertChunk(fileId: fileId, chunkIndex: 1, content: "chunk-v2", embedding: v2)

        // v3: mostly aligned with v1 → normalized([0.9, 0.1, 0, ..., 0])
        let v3 = makeVector(values: [(0, 0.9), (1, 0.1)])
        try store.insertChunk(fileId: fileId, chunkIndex: 2, content: "chunk-v3", embedding: v3)

        // Search with query = v1 direction
        let query = makeUnitVector(index: 0)
        let results = try store.search(queryVector: query, limit: 3)

        XCTAssertEqual(results.count, 3, "Should return all 3 results")

        // Ranking: v1 (identical, distance ≈ 0), v3 (closely aligned), v2 (orthogonal, distance ≈ 1)
        XCTAssertEqual(results[0].content, "chunk-v1", "v1 should be ranked first (closest)")
        XCTAssertEqual(results[1].content, "chunk-v3", "v3 should be ranked second")
        XCTAssertEqual(results[2].content, "chunk-v2", "v2 should be ranked third (most distant)")

        // Verify distance ordering
        XCTAssertLessThan(results[0].distance, results[1].distance)
        XCTAssertLessThan(results[1].distance, results[2].distance)

        // v1 distance should be near 0
        XCTAssertLessThan(results[0].distance, 0.01)

        // v2 distance should be near 1.0 (orthogonal → cosine distance = 1)
        XCTAssertGreaterThan(results[2].distance, 0.9)

        store.close()
    }

    // MARK: - Empty Search

    func testEmptySearch() throws {
        let store = try VectorStore(at: nil)
        try store.createSchema()

        let results = try store.search(
            queryVector: makeUnitVector(index: 0),
            limit: 10
        )
        XCTAssertEqual(results.count, 0, "Empty database should return no results")

        store.close()
    }

    // MARK: - Multiple Files

    func testMultipleFiles() throws {
        let store = try VectorStore(at: nil)
        try store.createSchema()

        let file1 = try store.insertFile(path: "/doc/a.txt", mtime: Date(), size: 500)
        let file2 = try store.insertFile(path: "/doc/b.txt", mtime: Date(), size: 300)

        XCTAssertNotEqual(file1, file2, "File IDs should be unique")

        let v1 = makeUnitVector(index: 0)
        let v2 = makeUnitVector(index: 1)

        try store.insertChunk(fileId: file1, chunkIndex: 0, content: "File A chunk", embedding: v1)
        try store.insertChunk(fileId: file2, chunkIndex: 0, content: "File B chunk", embedding: v2)

        // Search near v1 should return File A first
        let results = try store.search(queryVector: v1, limit: 2)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].content, "File A chunk")

        store.close()
    }

    // MARK: - Limit Enforcement

    func testSearchLimit() throws {
        let store = try VectorStore(at: nil)
        try store.createSchema()

        let fileId = try store.insertFile(path: "/test/file.txt", mtime: Date(), size: 100)

        // Insert 5 chunks
        for i in 0..<5 {
            let vec = makeUnitVector(index: i)
            try store.insertChunk(
                fileId: fileId,
                chunkIndex: i,
                content: "chunk-\(i)",
                embedding: vec
            )
        }

        // Search with limit 2
        let results = try store.search(queryVector: makeUnitVector(index: 0), limit: 2)
        XCTAssertEqual(results.count, 2, "Should return at most `limit` results")

        store.close()
    }
}
