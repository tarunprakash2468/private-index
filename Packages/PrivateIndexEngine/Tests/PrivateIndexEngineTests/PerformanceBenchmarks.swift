import XCTest
@testable import PrivateIndexEngine

final class PerformanceBenchmarks: XCTestCase {

    private func makeNormalizedVector(seed: Int, dimension: Int = 384) -> [Float] {
        var vec = [Float](repeating: 0, count: dimension)
        var hash: UInt64 = UInt64(seed) &* 6364136223846793005 &+ 1442695040888963407
        var normSq: Float = 0
        for i in 0..<dimension {
            hash = hash &* 6364136223846793005 &+ 1442695040888963407
            let val = Float(Int32(truncatingIfNeeded: hash >> 32)) / Float(Int32.max)
            vec[i] = val
            normSq += val * val
        }
        let norm = sqrt(max(normSq, 1e-12))
        return vec.map { $0 / norm }
    }

    // MARK: - Chunking Benchmark

    func testTextChunkerThroughput() {
        let chunker = TextChunker(windowSize: 500, overlap: 100)
        let sampleParagraph = "Private Index is an on-device semantic search engine designed for Apple platforms. " +
            "It stores 384-dimensional dense vectors inside an embedded SQLite database using sqlite-vec. " +
            "Zero cloud dependencies guarantee complete privacy for user documents and iCloud Drive files.\n"
        let corpus = String(repeating: sampleParagraph, count: 500) // ~120,000 characters

        measure {
            let chunks = chunker.chunk(corpus)
            XCTAssertGreaterThan(chunks.count, 200)
        }
    }

    // MARK: - Tokenizer Benchmark

    func testBertTokenizerThroughput() throws {
        let tokenizer = try BertTokenizer()
        let sentences = (0..<100).map { i in
            "Sentence number \(i) explaining how Apple Neural Engine accelerates semantic search indexing on macOS and iOS."
        }

        measure {
            for sentence in sentences {
                let tokenized = tokenizer.tokenize(sentence, maxLength: 128)
                XCTAssertEqual(tokenized.inputIDs.count, 128)
            }
        }
    }

    // MARK: - VectorStore Insertion & Search Benchmarks

    func testVectorStoreInsertionAndSearch1K() throws {
        let store = try VectorStore(at: nil)
        try store.createSchema()

        let fileId = try store.insertFile(path: "/benchmark/file.txt", mtime: Date(), size: 100000)

        // Measure insertion of 1,000 vectors
        let vectors = (0..<1000).map { makeNormalizedVector(seed: $0) }

        let insertStart = Date()
        for (idx, vec) in vectors.enumerated() {
            try store.insertChunk(
                fileId: fileId,
                chunkIndex: idx,
                content: "Benchmark chunk content for index \(idx)",
                embedding: vec
            )
        }
        let insertElapsed = Date().timeIntervalSince(insertStart)
        print("  [Benchmark] Inserted 1,000 384-dim vectors in \(String(format: "%.3f", insertElapsed))s (\(Int(1000.0 / insertElapsed)) vec/s)")

        // Measure search query latency over 1,000 vectors
        let queryVector = makeNormalizedVector(seed: 42)
        measure {
            do {
                let results = try store.search(queryVector: queryVector, limit: 10)
                XCTAssertEqual(results.count, 10)
            } catch {
                XCTFail("Search failed: \(error)")
            }
        }

        store.close()
    }
}
