import XCTest
@testable import PrivateIndexEngine

final class BenchmarkRunnerTests: XCTestCase {

    func testBenchmarkRunnerEndToEnd() async throws {
        let runner = BenchmarkRunner(vectorCount: 100)
        let metrics = try await runner.run()

        // System Detection
        XCTAssertFalse(metrics.system.osVersion.isEmpty)
        XCTAssertFalse(metrics.system.architecture.isEmpty)
        XCTAssertFalse(metrics.system.chipModel.isEmpty)
        XCTAssertFalse(metrics.system.modelIdentifier.isEmpty)

        // Stage 1: Chunker & Tokenizer
        XCTAssertGreaterThan(metrics.chunker.corpusSizeBytes, 100_000)
        XCTAssertGreaterThan(metrics.chunker.chunksProduced, 50)
        XCTAssertGreaterThan(metrics.chunker.durationSeconds, 0)
        XCTAssertGreaterThan(metrics.chunker.chunksPerSecond, 0)
        XCTAssertGreaterThan(metrics.chunker.kilobytesPerSecond, 0)

        XCTAssertEqual(metrics.tokenizer.sentenceCount, 100)
        XCTAssertGreaterThan(metrics.tokenizer.durationSeconds, 0)
        XCTAssertGreaterThan(metrics.tokenizer.sentencesPerSecond, 0)

        // Stage 2: Neural Inference
        XCTAssertFalse(metrics.inference.modelName.isEmpty)
        XCTAssertEqual(metrics.inference.warmupCount, 2)
        XCTAssertEqual(metrics.inference.inferenceCount, 50)
        XCTAssertGreaterThan(metrics.inference.durationSeconds, 0)
        XCTAssertGreaterThan(metrics.inference.averageLatencyMs, 0)
        XCTAssertGreaterThan(metrics.inference.embeddingsPerSecond, 0)

        // Stage 3: SQLite Vector Store & BM25
        XCTAssertEqual(metrics.vectorStore.vectorCount, 100)
        XCTAssertEqual(metrics.vectorStore.dimensions, 384)
        XCTAssertGreaterThan(metrics.vectorStore.insertionDurationSeconds, 0)
        XCTAssertGreaterThan(metrics.vectorStore.vectorsPerSecond, 0)

        XCTAssertEqual(metrics.vectorStore.vectorQueryIterations, 50)
        XCTAssertGreaterThan(metrics.vectorStore.vectorQueryP50Ms, 0)
        XCTAssertGreaterThanOrEqual(metrics.vectorStore.vectorQueryP95Ms, metrics.vectorStore.vectorQueryP50Ms)
        XCTAssertGreaterThan(metrics.vectorStore.vectorQueryAverageMs, 0)

        XCTAssertEqual(metrics.vectorStore.keywordQueryIterations, 50)
        XCTAssertGreaterThan(metrics.vectorStore.keywordQueryP50Ms, 0)
        XCTAssertGreaterThanOrEqual(metrics.vectorStore.keywordQueryP95Ms, metrics.vectorStore.keywordQueryP50Ms)
        XCTAssertGreaterThan(metrics.vectorStore.keywordQueryAverageMs, 0)

        // Stage 4: Resource Utilization
        XCTAssertGreaterThan(metrics.resources.peakMemoryBytes, 0)
        XCTAssertGreaterThan(metrics.resources.peakMemoryMB, 0)
        XCTAssertTrue(metrics.resources.zeroNetworkTransmission)
        XCTAssertEqual(metrics.resources.activeInternetSockets, 0)
    }

    func testBenchmarkJSONSerialization() throws {
        let system = BenchmarkMetrics.SystemInfo(
            osVersion: "macOS 15.0",
            architecture: "arm64",
            chipModel: "Apple M3 Pro",
            modelIdentifier: "Mac15,6"
        )
        let chunker = BenchmarkMetrics.ChunkerMetrics(
            corpusSizeBytes: 120_000,
            chunksProduced: 300,
            durationSeconds: 0.01,
            chunksPerSecond: 30_000,
            kilobytesPerSecond: 12_000
        )
        let tokenizer = BenchmarkMetrics.TokenizerMetrics(
            sentenceCount: 100,
            durationSeconds: 0.005,
            sentencesPerSecond: 20_000
        )
        let inference = BenchmarkMetrics.ModelInferenceMetrics(
            modelName: "all-MiniLM-L6-v2 (Apple Neural Engine / Core ML)",
            isCoreML: true,
            warmupCount: 2,
            inferenceCount: 50,
            durationSeconds: 0.05,
            averageLatencyMs: 1.0,
            embeddingsPerSecond: 1000
        )
        let vectorStore = BenchmarkMetrics.VectorStoreMetrics(
            vectorCount: 1000,
            dimensions: 384,
            insertionDurationSeconds: 0.03,
            vectorsPerSecond: 33_333,
            vectorQueryIterations: 50,
            vectorQueryP50Ms: 0.25,
            vectorQueryP95Ms: 0.40,
            vectorQueryAverageMs: 0.28,
            keywordQueryIterations: 50,
            keywordQueryP50Ms: 0.15,
            keywordQueryP95Ms: 0.22,
            keywordQueryAverageMs: 0.16
        )
        let resources = BenchmarkMetrics.ResourceMetrics(
            peakMemoryBytes: 50 * 1024 * 1024,
            peakMemoryMB: 50.0,
            activeInternetSockets: 0,
            zeroNetworkTransmission: true
        )

        let original = BenchmarkMetrics(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            system: system,
            chunker: chunker,
            tokenizer: tokenizer,
            inference: inference,
            vectorStore: vectorStore,
            resources: resources
        )

        let jsonString = try original.toJSONString()
        XCTAssertTrue(jsonString.contains("\"osVersion\" : \"macOS 15.0\""))
        XCTAssertTrue(jsonString.contains("\"chipModel\" : \"Apple M3 Pro\""))
        XCTAssertTrue(jsonString.contains("\"zeroNetworkTransmission\" : true"))
        XCTAssertTrue(jsonString.contains("\"activeInternetSockets\" : 0"))
        XCTAssertTrue(jsonString.contains("\"embeddingsPerSecond\" : 1000"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert json string to data")
            return
        }

        let decoded = try decoder.decode(BenchmarkMetrics.self, from: jsonData)
        XCTAssertEqual(decoded.system, original.system)
        XCTAssertEqual(decoded.chunker, original.chunker)
        XCTAssertEqual(decoded.tokenizer, original.tokenizer)
        XCTAssertEqual(decoded.inference, original.inference)
        XCTAssertEqual(decoded.vectorStore, original.vectorStore)
        XCTAssertEqual(decoded.resources, original.resources)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, original.timestamp.timeIntervalSince1970, accuracy: 1.0)
    }

    func testBenchmarkRunnerWithMockEmbeddingModel() async throws {
        let mockModel = MockEmbeddingModel()
        let runner = BenchmarkRunner(vectorCount: 20, embeddingModel: mockModel)
        let metrics = try await runner.run()

        XCTAssertFalse(metrics.inference.isCoreML)
        XCTAssertEqual(metrics.vectorStore.vectorCount, 20)
        XCTAssertEqual(metrics.inference.inferenceCount, 50)
        XCTAssertGreaterThan(metrics.inference.embeddingsPerSecond, 0)
    }

    func testBenchmarkRunnerStaticHelper() async throws {
        var progressMessages: [String] = []
        let metrics = try await BenchmarkRunner.run(vectorCount: 25) { msg in
            progressMessages.append(msg)
        }

        XCTAssertEqual(metrics.vectorStore.vectorCount, 25)
        XCTAssertFalse(progressMessages.isEmpty)
        XCTAssertTrue(progressMessages.contains(where: { $0.contains("Stage 1/4") }))
        XCTAssertTrue(progressMessages.contains(where: { $0.contains("Stage 4/4") }))
    }

    func testPercentileCalculation() {
        let sample: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0]
        let p50 = BenchmarkRunner.calculatePercentile(sample, percentile: 0.50)
        XCTAssertEqual(p50, 3.0, accuracy: 1e-6)

        let p0 = BenchmarkRunner.calculatePercentile(sample, percentile: 0.0)
        XCTAssertEqual(p0, 1.0, accuracy: 1e-6)

        let p100 = BenchmarkRunner.calculatePercentile(sample, percentile: 1.0)
        XCTAssertEqual(p100, 5.0, accuracy: 1e-6)

        XCTAssertEqual(BenchmarkRunner.calculatePercentile([], percentile: 0.5), 0.0)
        XCTAssertEqual(BenchmarkRunner.calculatePercentile([42.0], percentile: 0.95), 42.0)
    }
}
