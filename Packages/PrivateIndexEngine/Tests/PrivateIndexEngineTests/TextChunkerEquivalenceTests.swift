import XCTest
@testable import PrivateIndexEngine

final class TextChunkerEquivalenceTests: XCTestCase {

    // MARK: - 1. ASCII Paragraphs (Varied Sizes)

    func testAsciiParagraphShorterThanWindow() {
        let chunker = TextChunker(windowSize: 500, overlap: 100)
        let paragraph = """
        Private Index is an on-device semantic search engine designed specifically for macOS and Apple Silicon.
        It runs entirely offline with zero cloud transmission, ensuring absolute user privacy and data security.
        """
        XCTAssertLessThan(paragraph.count, 500)

        let chunks = chunker.chunk(paragraph)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], paragraph)
    }

    func testAsciiParagraphExactWindowSize() {
        let chunker = TextChunker(windowSize: 500, overlap: 100)
        // Generate an exact 500-character ASCII string
        let basePattern = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-" // 64 chars
        let repeated = String(repeating: basePattern, count: 8) // 512 chars
        let exact500 = String(repeated.prefix(500))
        XCTAssertEqual(exact500.count, 500)

        let chunks = chunker.chunk(exact500)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], exact500)
    }

    func testAsciiParagraphExactWindowPlusOneBoundary() {
        let chunker = TextChunker(windowSize: 500, overlap: 100) // stride = 400
        let basePattern = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-"
        let repeated = String(repeating: basePattern, count: 8)
        let exact501 = String(repeated.prefix(501))
        XCTAssertEqual(exact501.count, 501)

        let chars = Array(exact501)
        let chunks = chunker.chunk(exact501)
        XCTAssertEqual(chunks.count, 2)

        // Chunk 0: [0..<500] (length 500)
        XCTAssertEqual(chunks[0].count, 500)
        XCTAssertEqual(chunks[0], String(chars[0..<500]))

        // Chunk 1: [400..<501] (length 101)
        XCTAssertEqual(chunks[1].count, 101)
        XCTAssertEqual(chunks[1], String(chars[400..<501]))

        // Verify overlap boundary: last 100 of chunk 0 == first 100 of chunk 1
        let overlap0 = String(chunks[0].suffix(100))
        let overlap1 = String(chunks[1].prefix(100))
        XCTAssertEqual(overlap0, overlap1)
        XCTAssertEqual(overlap0, String(chars[400..<500]))
    }

    func testAsciiParagraphMultiWindow() {
        let chunker = TextChunker(windowSize: 500, overlap: 100) // stride = 400
        // Create 1450-character text
        let base = "The quick brown fox jumps over the lazy dog. " // 45 chars
        let paragraph = String(repeating: base, count: 33).prefix(1450)
        let text = String(paragraph)
        XCTAssertEqual(text.count, 1450)

        let chars = Array(text)
        let chunks = chunker.chunk(text)

        // 1450 characters with window 500, stride 400:
        // Chunk 0: [0..<500] (len 500)
        // Chunk 1: [400..<900] (len 500)
        // Chunk 2: [800..<1300] (len 500)
        // Chunk 3: [1200..<1450] (len 250)
        XCTAssertEqual(chunks.count, 4)

        XCTAssertEqual(chunks[0], String(chars[0..<500]))
        XCTAssertEqual(chunks[1], String(chars[400..<900]))
        XCTAssertEqual(chunks[2], String(chars[800..<1300]))
        XCTAssertEqual(chunks[3], String(chars[1200..<1450]))

        // Assert exact overlap regions
        XCTAssertEqual(String(chunks[0].suffix(100)), String(chunks[1].prefix(100)))
        XCTAssertEqual(String(chunks[1].suffix(100)), String(chunks[2].prefix(100)))
        XCTAssertEqual(String(chunks[2].suffix(100)), String(chunks[3].prefix(100)))
    }

    // MARK: - 2. Multi-byte UTF-8 & Emoji Sequences

    func testFamilyEmojiGraphemeClusterBoundaries() {
        // Family emojis with Zero Width Joiner (ZWJ) count as 1 Swift Character
        let family1 = "👨‍👩‍👧‍👦" // Man, Woman, Girl, Boy
        let family2 = "👩‍👩‍👧‍👦" // Woman, Woman, Girl, Boy
        let family3 = "👨‍👦"     // Man, Boy
        let family4 = "👩‍👧‍👦"   // Woman, Girl, Boy

        XCTAssertEqual(family1.count, 1)
        XCTAssertEqual(family2.count, 1)
        XCTAssertEqual(family3.count, 1)
        XCTAssertEqual(family4.count, 1)

        let text = "\(family1)A\(family2)B\(family3)C\(family4)D" // 8 characters
        XCTAssertEqual(text.count, 8)

        let chunker = TextChunker(windowSize: 5, overlap: 2) // stride = 3
        // Chunks:
        // Chunk 0: [0..<5] = family1, A, family2, B, family3
        // Chunk 1: [3..<8] = B, family3, C, family4, D
        let chunks = chunker.chunk(text)
        XCTAssertEqual(chunks.count, 2)

        XCTAssertEqual(chunks[0], "\(family1)A\(family2)B\(family3)")
        XCTAssertEqual(chunks[1], "B\(family3)C\(family4)D")

        // Overlap region: "B" + family3
        XCTAssertEqual(String(chunks[0].suffix(2)), "B\(family3)")
        XCTAssertEqual(String(chunks[1].prefix(2)), "B\(family3)")
    }

    func testFlagEmojiSequences() {
        // Flag emojis consist of Regional Indicator symbol pairs (1 Swift Character each)
        let flags = "🇺🇸🇬🇧🇯🇵🇩🇪🇫🇷🇨🇦🇦🇺🇧🇷" // 8 flag characters
        XCTAssertEqual(flags.count, 8)

        let chunker = TextChunker(windowSize: 4, overlap: 1) // stride = 3
        // Chunk 0: [0..<4] = 🇺🇸🇬🇧🇯🇵🇩🇪
        // Chunk 1: [3..<7] = 🇩🇪🇫🇷🇨🇦🇦🇺
        // Chunk 2: [6..<8] = 🇦🇺🇧🇷
        let chunks = chunker.chunk(flags)
        XCTAssertEqual(chunks.count, 3)

        XCTAssertEqual(chunks[0], "🇺🇸🇬🇧🇯🇵🇩🇪")
        XCTAssertEqual(chunks[1], "🇩🇪🇫🇷🇨🇦🇦🇺")
        XCTAssertEqual(chunks[2], "🇦🇺🇧🇷")

        XCTAssertEqual(String(chunks[0].suffix(1)), String(chunks[1].prefix(1)))
        XCTAssertEqual(String(chunks[1].suffix(1)), String(chunks[2].prefix(1)))
    }

    func testSurrogatePairsAndAstralPlaneSymbols() {
        // Mathematical alphanumeric symbols & musical symbols beyond BMP (surrogate pairs in UTF-16)
        let musicalClef = "𝄞" // U+1D11E (Musical Symbol G Clef)
        let bassClef = "𝄢"    // U+1D122 (Musical Symbol F Clef)
        let gothicLetter = "𐍈" // U+10348 (Gothic Letter Hwair)
        let mathBoldF = "𝐅"   // U+1D405 (Mathematical Bold Capital F)
        let mathBoldM = "𝐦"   // U+1D426 (Mathematical Bold Small M)
        let mathBoldA = "𝐚"   // U+1D41A (Mathematical Bold Small A)

        let formula = "\(musicalClef) \(mathBoldF)=\(mathBoldM)\(mathBoldA) \(bassClef) \(gothicLetter)"
        // Characters: 𝄞 (1), ' ' (1), 𝐅 (1), '=' (1), 𝐦 (1), 𝐚 (1), ' ' (1), 𝄢 (1), ' ' (1), 𐍈 (1) = 10 chars
        XCTAssertEqual(formula.count, 10)

        let chunker = TextChunker(windowSize: 6, overlap: 2) // stride = 4
        // Chunk 0: [0..<6] = "𝄞 𝐅=𝐦𝐚"
        // Chunk 1: [4..<10] = "𝐦𝐚 𝄢 𐍈"
        let chunks = chunker.chunk(formula)
        XCTAssertEqual(chunks.count, 2)

        XCTAssertEqual(chunks[0], "\(musicalClef) \(mathBoldF)=\(mathBoldM)\(mathBoldA)")
        XCTAssertEqual(chunks[1], "\(mathBoldM)\(mathBoldA) \(bassClef) \(gothicLetter)")
        XCTAssertEqual(String(chunks[0].suffix(2)), "\(mathBoldM)\(mathBoldA)")
        XCTAssertEqual(String(chunks[1].prefix(2)), "\(mathBoldM)\(mathBoldA)")
    }

    func testComplexEmojiWithSkinToneModifiers() {
        let coderWoman = "👩🏽‍💻" // Woman + Medium Skin Tone + ZWJ + Laptop (1 char)
        let astronaut = "🧑🏿‍🚀"  // Adult + Dark Skin Tone + ZWJ + Rocket (1 char)
        let superhero = "🦹🏼‍♂️"  // Supervillain + Medium-Light Skin Tone + ZWJ + Male Sign (1 char)

        XCTAssertEqual(coderWoman.count, 1)
        XCTAssertEqual(astronaut.count, 1)
        XCTAssertEqual(superhero.count, 1)

        let text = "\(coderWoman) develops CoreML on Apple Silicon while \(astronaut) searches in orbit \(superhero)"
        let chunker = TextChunker(windowSize: 30, overlap: 10)
        let chunks = chunker.chunk(text)

        XCTAssertGreaterThan(chunks.count, 1)
        // Verify every chunk is valid UTF-8 and contains intact grapheme clusters
        for chunk in chunks {
            XCTAssertFalse(chunk.contains("\u{FFFD}"), "Chunk must not contain replacement characters")
        }
        // First chunk must start with coderWoman
        XCTAssertTrue(chunks[0].hasPrefix(coderWoman))
        // Last chunk must end with superhero
        XCTAssertTrue(chunks.last!.hasSuffix(superhero))
    }

    // MARK: - 3. CJK Character Strings

    func testChineseTextChunking() {
        let chineseText = """
        自然语言处理与向量检索系统。深度学习与人工智能技术在现代本地知识库中发挥着至关重要的作用。
        通过端到端嵌入模型与倒排索引结合，可以在保证用户隐私的同时实现毫秒级搜索响应。
        """
        // Clean newlines for deterministic character count
        let text = chineseText.replacingOccurrences(of: "\n", with: "")
        let chars = Array(text)
        let count = chars.count

        let chunker = TextChunker(windowSize: 30, overlap: 10) // stride = 20
        let chunks = chunker.chunk(text)

        let expectedChunkCount = Int(ceil(Double(count - 30) / 20.0)) + 1
        XCTAssertEqual(chunks.count, expectedChunkCount)

        // Verify each chunk content equals exact character subrange
        var start = 0
        for (i, chunk) in chunks.enumerated() {
            let end = min(start + 30, count)
            let expectedChunk = String(chars[start..<end])
            XCTAssertEqual(chunk, expectedChunk, "Chunk \(i) mismatch")
            if i > 0 {
                // Overlap verification: previous suffix(10) == current prefix(10)
                let prevSuffix = String(chunks[i - 1].suffix(10))
                let currPrefix = String(chunk.prefix(10))
                XCTAssertEqual(prevSuffix, currPrefix, "Overlap mismatch between chunk \(i-1) and \(i)")
            }
            start += 20
        }
    }

    func testJapaneseTextChunking() {
        let japaneseText = "形態素解析と単語分割を行い、ベクトル検索インデックスを生成します。高速な推論が可能です。"
        let chars = Array(japaneseText)
        let count = chars.count
        XCTAssertEqual(count, 44)

        let chunker = TextChunker(windowSize: 20, overlap: 5) // stride = 15
        // Chunk 0: [0..<20] (len 20)
        // Chunk 1: [15..<35] (len 20)
        // Chunk 2: [30..<44] (len 14)
        let chunks = chunker.chunk(japaneseText)
        XCTAssertEqual(chunks.count, 3)

        XCTAssertEqual(chunks[0], String(chars[0..<20]))
        XCTAssertEqual(chunks[1], String(chars[15..<35]))
        XCTAssertEqual(chunks[2], String(chars[30..<44]))

        // Overlap:
        XCTAssertEqual(String(chunks[0].suffix(5)), String(chunks[1].prefix(5)))
        XCTAssertEqual(String(chunks[1].suffix(5)), String(chunks[2].prefix(5)))
    }

    func testKoreanTextChunking() {
        let koreanText = "온디바이스 인공지능 벡터 검색 엔진은 사용자의 소중한 개인정보를 클라우드로 전송하지 않고 기기 내부에서 안전하게 보호합니다."
        let chars = Array(koreanText)
        let count = chars.count

        let chunker = TextChunker(windowSize: 25, overlap: 5) // stride = 20
        let chunks = chunker.chunk(koreanText)

        let expectedCount = Int(ceil(Double(count - 25) / 20.0)) + 1
        XCTAssertEqual(chunks.count, expectedCount)

        var start = 0
        for (i, chunk) in chunks.enumerated() {
            let end = min(start + 25, count)
            XCTAssertEqual(chunk, String(chars[start..<end]))
            if i > 0 {
                XCTAssertEqual(String(chunks[i - 1].suffix(5)), String(chunk.prefix(5)))
            }
            start += 20
        }
    }

    func testMixedCjkAsciiEmojiText() {
        let mixed = "Apple M3 Pro 🚀 性能测试：日本語・中文・한국어 自然言語処理 100% 成功！"
        let chars = Array(mixed)
        let chunker = TextChunker(windowSize: 15, overlap: 5) // stride = 10
        let chunks = chunker.chunk(mixed)

        XCTAssertGreaterThan(chunks.count, 1)

        var start = 0
        for (i, chunk) in chunks.enumerated() {
            let end = min(start + 15, chars.count)
            XCTAssertEqual(chunk, String(chars[start..<end]))
            if i > 0 {
                XCTAssertEqual(String(chunks[i - 1].suffix(5)), String(chunk.prefix(5)))
            }
            start += 10
        }
    }

    // MARK: - 4. Edge Cases

    func testEmptyTextProducesEmptyArray() {
        let chunker = TextChunker(windowSize: 500, overlap: 100)
        XCTAssertEqual(chunker.chunk(""), [])
    }

    func testSingleCharacterInput() {
        let chunker = TextChunker(windowSize: 100, overlap: 20)
        XCTAssertEqual(chunker.chunk("A"), ["A"])
        XCTAssertEqual(chunker.chunk("🎉"), ["🎉"])
        XCTAssertEqual(chunker.chunk("한"), ["한"])
    }

    func testCustomWindow100AndOverlap20() {
        let chunker = TextChunker(windowSize: 100, overlap: 20)
        XCTAssertEqual(chunker.windowSize, 100)
        XCTAssertEqual(chunker.overlap, 20)
        XCTAssertEqual(chunker.stride, 80)

        // 250 character string
        let content = String(repeating: "abcdefghijklmnopqrstuvwxyz1234", count: 9).prefix(250)
        let text = String(content)
        XCTAssertEqual(text.count, 250)

        let chars = Array(text)
        let chunks = chunker.chunk(text)

        // Stride = 80:
        // Chunk 0: [0..<100] (len 100)
        // Chunk 1: [80..<180] (len 100)
        // Chunk 2: [160..<250] (len 90)
        XCTAssertEqual(chunks.count, 3)

        XCTAssertEqual(chunks[0], String(chars[0..<100]))
        XCTAssertEqual(chunks[1], String(chars[80..<180]))
        XCTAssertEqual(chunks[2], String(chars[160..<250]))

        // Overlap regions must be exactly 20 characters
        XCTAssertEqual(chunks[0].suffix(20), chunks[1].prefix(20))
        XCTAssertEqual(chunks[1].suffix(20), chunks[2].prefix(20))
    }

    func testZeroOverlapPartition() {
        let chunker = TextChunker(windowSize: 50, overlap: 0)
        XCTAssertEqual(chunker.stride, 50)

        let text = String(repeating: "0123456789", count: 12) // 120 chars
        XCTAssertEqual(text.count, 120)

        let chars = Array(text)
        let chunks = chunker.chunk(text)

        // Chunk 0: [0..<50] (len 50)
        // Chunk 1: [50..<100] (len 50)
        // Chunk 2: [100..<120] (len 20)
        XCTAssertEqual(chunks.count, 3)

        XCTAssertEqual(chunks[0], String(chars[0..<50]))
        XCTAssertEqual(chunks[1], String(chars[50..<100]))
        XCTAssertEqual(chunks[2], String(chars[100..<120]))

        // With 0 overlap, rejoining all chunks must produce the exact original string
        let rejoined = chunks.joined()
        XCTAssertEqual(rejoined, text)
    }

    func testHighOverlapStrideOne() {
        let chunker = TextChunker(windowSize: 5, overlap: 4) // stride = 1
        XCTAssertEqual(chunker.stride, 1)

        let text = "ABCDEFG" // 7 chars
        let chunks = chunker.chunk(text)
        // Chunk 0: [0..<5] = "ABCDE"
        // Chunk 1: [1..<6] = "BCDEF"
        // Chunk 2: [2..<7] = "CDEFG"
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks, ["ABCDE", "BCDEF", "CDEFG"])
    }
}
