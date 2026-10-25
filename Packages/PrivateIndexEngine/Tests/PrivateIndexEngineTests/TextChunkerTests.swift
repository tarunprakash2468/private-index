import XCTest
@testable import PrivateIndexEngine

final class TextChunkerTests: XCTestCase {

    // MARK: - Empty & Short Input

    func testEmptyInput() {
        let chunker = TextChunker()
        let result = chunker.chunk("")
        XCTAssertEqual(result, [], "Empty string should produce no chunks")
    }

    func testShortInput() {
        let chunker = TextChunker(windowSize: 500, overlap: 100)
        let text = "Hello, world!"
        let result = chunker.chunk(text)
        XCTAssertEqual(result.count, 1, "Short text should produce exactly 1 chunk")
        XCTAssertEqual(result[0], text, "Single chunk should equal the full text")
    }

    func testSingleCharacter() {
        let chunker = TextChunker(windowSize: 500, overlap: 100)
        let result = chunker.chunk("X")
        XCTAssertEqual(result, ["X"])
    }

    // MARK: - Exact Window Size

    func testExactWindowSize() {
        let chunker = TextChunker(windowSize: 10, overlap: 3)
        let text = String(repeating: "a", count: 10)
        let result = chunker.chunk(text)
        XCTAssertEqual(result.count, 1, "Text exactly at windowSize should produce 1 chunk")
        XCTAssertEqual(result[0], text)
    }

    // MARK: - Overlap Verification

    func testOverlapBetweenChunks() {
        let chunker = TextChunker(windowSize: 10, overlap: 3)
        // "0123456789ABCDEF" = 16 chars, stride = 7
        // Chunk 0: [0..10) = "0123456789"
        // Chunk 1: [7..16) = "789ABCDEF"
        let text = "0123456789ABCDEF"
        let result = chunker.chunk(text)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], "0123456789")
        XCTAssertEqual(result[1], "789ABCDEF")

        // Verify overlap: last 3 chars of chunk 0 == first 3 chars of chunk 1
        let overlapFromFirst = String(result[0].suffix(3))
        let overlapFromSecond = String(result[1].prefix(3))
        XCTAssertEqual(overlapFromFirst, overlapFromSecond, "Overlap region must match")
    }

    // MARK: - Multiple Chunks

    func testMultipleChunks() {
        // windowSize=500, overlap=100, stride=400
        // 1500 chars → chunks start at 0, 400, 800, 1200
        // Chunk 0: [0, 500)
        // Chunk 1: [400, 900)
        // Chunk 2: [800, 1300)
        // Chunk 3: [1200, 1500)
        let chunker = TextChunker(windowSize: 500, overlap: 100)
        let text = String(repeating: "x", count: 1500)
        let result = chunker.chunk(text)

        XCTAssertEqual(result.count, 4, "1500 chars with (500, 100) should produce 4 chunks")
        XCTAssertEqual(result[0].count, 500)
        XCTAssertEqual(result[1].count, 500)
        XCTAssertEqual(result[2].count, 500)
        XCTAssertEqual(result[3].count, 300, "Last chunk should contain remaining 300 chars")
    }

    func testLastChunkShorter() {
        // 15 chars, windowSize=10, overlap=3, stride=7
        // Chunk 0: [0, 10) — 10 chars
        // Chunk 1: [7, 15) — 8 chars
        let chunker = TextChunker(windowSize: 10, overlap: 3)
        let text = String(repeating: "z", count: 15)
        let result = chunker.chunk(text)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].count, 10)
        XCTAssertEqual(result[1].count, 8)
    }

    // MARK: - Unicode

    func testUnicodeCharacters() {
        // Emoji are single Swift Characters but multi-byte in UTF-8/UTF-16
        let chunker = TextChunker(windowSize: 5, overlap: 2)
        let text = "🍎🍊🍋🍇🍓🫐🥝"  // 7 characters
        let result = chunker.chunk(text)

        // stride = 3, chunks start at 0, 3, 6
        // Chunk 0: [0, 5) = "🍎🍊🍋🍇🍓"
        // Chunk 1: [3, 7) = "🍇🍓🫐🥝"
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], "🍎🍊🍋🍇🍓")
        XCTAssertEqual(result[1], "🍇🍓🫐🥝")
    }

    func testCJKCharacters() {
        let chunker = TextChunker(windowSize: 4, overlap: 1)
        let text = "日本語テスト文字"  // 8 characters
        let result = chunker.chunk(text)

        // stride = 3, chunks at 0, 3, 6
        // Chunk 0: [0, 4) = "日本語テ"
        // Chunk 1: [3, 7) = "テスト文"
        // Chunk 2: [6, 8) = "字" — wait, let me re-check
        // Actually: [6, 8) = "文字"
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0], "日本語テ")
        XCTAssertEqual(result[1], "テスト文")
        XCTAssertEqual(result[2], "文字")
    }

    // MARK: - Custom Parameters

    func testCustomParameters() {
        let chunker = TextChunker(windowSize: 3, overlap: 1)
        // "ABCDE" = 5 chars, stride = 2
        // Chunk 0: [0, 3) = "ABC"
        // Chunk 1: [2, 5) = "CDE"
        let result = chunker.chunk("ABCDE")
        XCTAssertEqual(result, ["ABC", "CDE"])
    }

    func testZeroOverlap() {
        let chunker = TextChunker(windowSize: 3, overlap: 0)
        // "ABCDEFG" = 7 chars, stride = 3
        // Chunk 0: [0, 3) = "ABC"
        // Chunk 1: [3, 6) = "DEF"
        // Chunk 2: [6, 7) = "G"
        let result = chunker.chunk("ABCDEFG")
        XCTAssertEqual(result, ["ABC", "DEF", "G"])
    }

    // MARK: - Stride Property

    func testStrideComputation() {
        let chunker = TextChunker(windowSize: 500, overlap: 100)
        XCTAssertEqual(chunker.stride, 400)

        let chunker2 = TextChunker(windowSize: 200, overlap: 50)
        XCTAssertEqual(chunker2.stride, 150)
    }
}
