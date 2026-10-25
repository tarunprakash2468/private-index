import XCTest
@testable import PrivateIndexEngine

final class EmbeddingGeneratorTests: XCTestCase {
    func testMockEmbeddingGeneration() async throws {
        let mock = MockEmbeddingModel(dimension: 384)
        let embedding = try await mock.generateEmbedding(for: "zero-cloud privacy architecture")

        XCTAssertEqual(embedding.count, 384)

        // Verify L2 norm is approximately 1.0 (normalized vector)
        let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1.0, accuracy: 1e-4)
    }

    func testLoadDefaultModelFallback() {
        let tokenizer = BertTokenizer(vocab: [:])
        let model = CoreMLEmbeddingModel.loadDefaultModel(tokenizer: tokenizer)

        // When compiled weights are absent in test environment, it must safely fallback to MockEmbeddingModel
        XCTAssertNotNil(model)
        XCTAssertEqual(model.embeddingDimension, 384)
    }
}
