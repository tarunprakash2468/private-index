import XCTest
@testable import PrivateIndexEngine

final class BertTokenizerTests: XCTestCase {

    private var tokenizer: BertTokenizer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tokenizer = try BertTokenizer()
    }

    override func tearDownWithError() throws {
        tokenizer = nil
        try super.tearDownWithError()
    }

    func testSpecialTokenIDs() {
        XCTAssertEqual(tokenizer.padTokenID, 0)
        XCTAssertEqual(tokenizer.unkTokenID, 100)
        XCTAssertEqual(tokenizer.clsTokenID, 101)
        XCTAssertEqual(tokenizer.sepTokenID, 102)
    }

    func testBasicTokenization() {
        let input = "Hello, world!"
        let tokenized = tokenizer.tokenize(input, maxLength: 8)

        // inputIDs: [CLS, hello, ,, world, !, SEP, PAD, PAD]
        XCTAssertEqual(tokenized.inputIDs.count, 8)
        XCTAssertEqual(tokenized.attentionMask.count, 8)

        XCTAssertEqual(tokenized.inputIDs[0], tokenizer.clsTokenID)
        // Check attention mask: 6 active tokens (CLS + 4 word tokens + SEP), 2 pad tokens
        XCTAssertEqual(tokenized.attentionMask, [1, 1, 1, 1, 1, 1, 0, 0])
        XCTAssertEqual(tokenized.inputIDs[5], tokenizer.sepTokenID)
        XCTAssertEqual(tokenized.inputIDs[6], tokenizer.padTokenID)
        XCTAssertEqual(tokenized.inputIDs[7], tokenizer.padTokenID)
    }

    func testWordPieceSubwords() {
        // "embeddings" should break into "em", "##bed", "##ding", "##s" or similar
        let input = "embeddings"
        let tokenized = tokenizer.tokenize(input, maxLength: 10)

        XCTAssertEqual(tokenized.inputIDs[0], tokenizer.clsTokenID)
        XCTAssertTrue(tokenized.attentionMask[1] == 1)
        // None of the active tokens should be UNK
        for id in tokenized.inputIDs where id != tokenizer.padTokenID {
            XCTAssertNotEqual(id, tokenizer.unkTokenID)
        }
    }

    func testEmptyString() {
        let tokenized = tokenizer.tokenize("", maxLength: 5)

        XCTAssertEqual(tokenized.inputIDs.count, 5)
        // [CLS, SEP, PAD, PAD, PAD]
        XCTAssertEqual(tokenized.inputIDs[0], tokenizer.clsTokenID)
        XCTAssertEqual(tokenized.inputIDs[1], tokenizer.sepTokenID)
        XCTAssertEqual(tokenized.inputIDs[2], tokenizer.padTokenID)
        XCTAssertEqual(tokenized.inputIDs[3], tokenizer.padTokenID)
        XCTAssertEqual(tokenized.inputIDs[4], tokenizer.padTokenID)
        XCTAssertEqual(tokenized.attentionMask, [1, 1, 0, 0, 0])
    }

    func testTruncation() {
        let longText = String(repeating: "apple orange banana ", count: 50)
        let tokenized = tokenizer.tokenize(longText, maxLength: 16)

        XCTAssertEqual(tokenized.inputIDs.count, 16)
        XCTAssertEqual(tokenized.attentionMask.count, 16)
        XCTAssertEqual(tokenized.inputIDs[0], tokenizer.clsTokenID)
        XCTAssertEqual(tokenized.inputIDs[15], tokenizer.sepTokenID)
        XCTAssertFalse(tokenized.attentionMask.contains(0), "Fully saturated tokens should have all 1s")
    }

    func testDecoding() {
        let input = "Private semantic search"
        let tokenized = tokenizer.tokenize(input, maxLength: 16)
        let decoded = tokenizer.decode(tokenized.inputIDs)

        // Decoded should match lowercased input (BERT is uncased)
        XCTAssertTrue(decoded.contains("private"))
        XCTAssertTrue(decoded.contains("semantic"))
        XCTAssertTrue(decoded.contains("search"))
    }
}
