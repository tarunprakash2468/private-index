import Foundation
import CoreML
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Duration Helper

extension Duration {
    /// Converts duration to fractional seconds.
    var asSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

// MARK: - BenchmarkMetrics

/// Comprehensive, machine-readable performance metrics produced by `BenchmarkRunner`.
public struct BenchmarkMetrics: Codable, Sendable, Equatable {

    /// Host system details.
    public struct SystemInfo: Codable, Sendable, Equatable {
        public let osVersion: String
        public let architecture: String
        public let chipModel: String
        public let modelIdentifier: String

        public init(osVersion: String, architecture: String, chipModel: String, modelIdentifier: String) {
            self.osVersion = osVersion
            self.architecture = architecture
            self.chipModel = chipModel
            self.modelIdentifier = modelIdentifier
        }
    }

    /// Stage 1 text chunker throughput metrics.
    public struct ChunkerMetrics: Codable, Sendable, Equatable {
        public let corpusSizeBytes: Int
        public let chunksProduced: Int
        public let durationSeconds: Double
        public let chunksPerSecond: Double
        public let kilobytesPerSecond: Double

        public init(corpusSizeBytes: Int, chunksProduced: Int, durationSeconds: Double, chunksPerSecond: Double, kilobytesPerSecond: Double) {
            self.corpusSizeBytes = corpusSizeBytes
            self.chunksProduced = chunksProduced
            self.durationSeconds = durationSeconds
            self.chunksPerSecond = chunksPerSecond
            self.kilobytesPerSecond = kilobytesPerSecond
        }
    }

    /// Stage 1 tokenizer throughput metrics.
    public struct TokenizerMetrics: Codable, Sendable, Equatable {
        public let sentenceCount: Int
        public let durationSeconds: Double
        public let sentencesPerSecond: Double

        public init(sentenceCount: Int, durationSeconds: Double, sentencesPerSecond: Double) {
            self.sentenceCount = sentenceCount
            self.durationSeconds = durationSeconds
            self.sentencesPerSecond = sentencesPerSecond
        }
    }

    /// Stage 2 neural engine inference metrics.
    public struct ModelInferenceMetrics: Codable, Sendable, Equatable {
        public let modelName: String
        public let isCoreML: Bool
        public let warmupCount: Int
        public let inferenceCount: Int
        public let durationSeconds: Double
        public let averageLatencyMs: Double
        public let embeddingsPerSecond: Double

        public init(
            modelName: String,
            isCoreML: Bool,
            warmupCount: Int,
            inferenceCount: Int,
            durationSeconds: Double,
            averageLatencyMs: Double,
            embeddingsPerSecond: Double
        ) {
            self.modelName = modelName
            self.isCoreML = isCoreML
            self.warmupCount = warmupCount
            self.inferenceCount = inferenceCount
            self.durationSeconds = durationSeconds
            self.averageLatencyMs = averageLatencyMs
            self.embeddingsPerSecond = embeddingsPerSecond
        }
    }

    /// Stage 3 SQLite vector and keyword store metrics.
    public struct VectorStoreMetrics: Codable, Sendable, Equatable {
        public let vectorCount: Int
        public let dimensions: Int
        public let insertionDurationSeconds: Double
        public let vectorsPerSecond: Double
        public let vectorQueryIterations: Int
        public let vectorQueryP50Ms: Double
        public let vectorQueryP95Ms: Double
        public let vectorQueryAverageMs: Double
        public let keywordQueryIterations: Int
        public let keywordQueryP50Ms: Double
        public let keywordQueryP95Ms: Double
        public let keywordQueryAverageMs: Double

        public init(
            vectorCount: Int,
            dimensions: Int,
            insertionDurationSeconds: Double,
            vectorsPerSecond: Double,
            vectorQueryIterations: Int,
            vectorQueryP50Ms: Double,
            vectorQueryP95Ms: Double,
            vectorQueryAverageMs: Double,
            keywordQueryIterations: Int,
            keywordQueryP50Ms: Double,
            keywordQueryP95Ms: Double,
            keywordQueryAverageMs: Double
        ) {
            self.vectorCount = vectorCount
            self.dimensions = dimensions
            self.insertionDurationSeconds = insertionDurationSeconds
            self.vectorsPerSecond = vectorsPerSecond
            self.vectorQueryIterations = vectorQueryIterations
            self.vectorQueryP50Ms = vectorQueryP50Ms
            self.vectorQueryP95Ms = vectorQueryP95Ms
            self.vectorQueryAverageMs = vectorQueryAverageMs
            self.keywordQueryIterations = keywordQueryIterations
            self.keywordQueryP50Ms = keywordQueryP50Ms
            self.keywordQueryP95Ms = keywordQueryP95Ms
            self.keywordQueryAverageMs = keywordQueryAverageMs
        }
    }

    /// Stage 4 memory and zero-cloud network verification metrics.
    public struct ResourceMetrics: Codable, Sendable, Equatable {
        public let peakMemoryBytes: UInt64
        public let peakMemoryMB: Double
        public let activeInternetSockets: Int
        public let zeroNetworkTransmission: Bool

        public init(peakMemoryBytes: UInt64, peakMemoryMB: Double, activeInternetSockets: Int, zeroNetworkTransmission: Bool) {
            self.peakMemoryBytes = peakMemoryBytes
            self.peakMemoryMB = peakMemoryMB
            self.activeInternetSockets = activeInternetSockets
            self.zeroNetworkTransmission = zeroNetworkTransmission
        }
    }

    public let timestamp: Date
    public let system: SystemInfo
    public let chunker: ChunkerMetrics
    public let tokenizer: TokenizerMetrics
    public let inference: ModelInferenceMetrics
    public let vectorStore: VectorStoreMetrics
    public let resources: ResourceMetrics

    public init(
        timestamp: Date = Date(),
        system: SystemInfo,
        chunker: ChunkerMetrics,
        tokenizer: TokenizerMetrics,
        inference: ModelInferenceMetrics,
        vectorStore: VectorStoreMetrics,
        resources: ResourceMetrics
    ) {
        self.timestamp = timestamp
        self.system = system
        self.chunker = chunker
        self.tokenizer = tokenizer
        self.inference = inference
        self.vectorStore = vectorStore
        self.resources = resources
    }

    /// Converts metrics to formatted JSON data.
    public func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Converts metrics to a formatted JSON string.
    public func toJSONString() throws -> String {
        let data = try toJSONData()
        guard let str = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Unable to decode UTF-8 string from JSON data")
            )
        }
        return str
    }
}

// MARK: - BenchmarkRunner

/// Executes non-destructive, in-memory performance benchmarks across all core Private Index subsystems.
public final class BenchmarkRunner: @unchecked Sendable {

    /// Number of synthetic vectors to insert and evaluate in Stage 3.
    public let vectorCount: Int

    /// Optional explicit embedding model to benchmark (defaults to Core ML all-MiniLM-L6-v2).
    public let embeddingModel: EmbeddingGenerator?

    public init(vectorCount: Int = 1000, embeddingModel: EmbeddingGenerator? = nil) {
        self.vectorCount = max(10, vectorCount)
        self.embeddingModel = embeddingModel
    }

    /// Runs all 4 benchmark stages and produces a `BenchmarkMetrics` report.
    ///
    /// - Parameter onProgress: Optional callback receiving progress descriptions.
    /// - Returns: Complete benchmark metrics.
    public func run(onProgress: ((String) -> Void)? = nil) async throws -> BenchmarkMetrics {
        onProgress?("Detecting system hardware...")
        let systemInfo = Self.detectSystem()

        // MARK: Stage 1 - Chunker & Tokenizer
        onProgress?("Stage 1/4: Benchmarking Text Chunker & Bert Tokenizer...")
        let (chunkerMetrics, tokenizerMetrics, tokenizer) = try Self.benchmarkChunkerAndTokenizer()

        // MARK: Stage 2 - Neural Inference
        onProgress?("Stage 2/4: Benchmarking Neural Engine Inference...")
        let inferenceMetrics = try await Self.benchmarkInference(
            tokenizer: tokenizer,
            customModel: embeddingModel
        )

        // MARK: Stage 3 - In-Memory Vector Store & BM25
        onProgress?("Stage 3/4: Benchmarking SQLite In-Memory Vector Store (\(vectorCount) vectors)...")
        let vectorStoreMetrics = try Self.benchmarkVectorStore(vectorCount: vectorCount)

        // MARK: Stage 4 - Resource Utilization
        onProgress?("Stage 4/4: Querying Resource Utilization & Verifying Zero Network Sockets...")
        let resourceMetrics = Self.benchmarkResources()

        return BenchmarkMetrics(
            timestamp: Date(),
            system: systemInfo,
            chunker: chunkerMetrics,
            tokenizer: tokenizerMetrics,
            inference: inferenceMetrics,
            vectorStore: vectorStoreMetrics,
            resources: resourceMetrics
        )
    }

    /// Static convenience helper to run the benchmark suite.
    public static func run(
        vectorCount: Int = 1000,
        embeddingModel: EmbeddingGenerator? = nil,
        onProgress: ((String) -> Void)? = nil
    ) async throws -> BenchmarkMetrics {
        let runner = BenchmarkRunner(vectorCount: vectorCount, embeddingModel: embeddingModel)
        return try await runner.run(onProgress: onProgress)
    }

    // MARK: - Stage 1 Implementation

    private static func benchmarkChunkerAndTokenizer() throws -> (BenchmarkMetrics.ChunkerMetrics, BenchmarkMetrics.TokenizerMetrics, BertTokenizer) {
        // 1. TextChunker throughput over ~120KB synthetic corpus
        let chunker = TextChunker(windowSize: 500, overlap: 100)
        let sampleParagraph = "Private Index is an on-device semantic search engine designed for Apple platforms. " +
            "It stores 384-dimensional dense vectors inside an embedded SQLite database using sqlite-vec. " +
            "Zero cloud dependencies guarantee complete privacy for user documents and iCloud Drive files.\n"
        let corpus = String(repeating: sampleParagraph, count: 500)
        let corpusSizeBytes = corpus.utf8.count

        let chunkStart = ContinuousClock.now
        let chunks = chunker.chunk(corpus)
        let chunkDuration = max(1e-6, chunkStart.duration(to: .now).asSeconds)
        let chunksPerSec = Double(chunks.count) / chunkDuration
        let kbPerSec = (Double(corpusSizeBytes) / 1024.0) / chunkDuration

        let chunkerMetrics = BenchmarkMetrics.ChunkerMetrics(
            corpusSizeBytes: corpusSizeBytes,
            chunksProduced: chunks.count,
            durationSeconds: chunkDuration,
            chunksPerSecond: chunksPerSec,
            kilobytesPerSecond: kbPerSec
        )

        // 2. BertTokenizer throughput over 100 sentences
        let tokenizer: BertTokenizer
        if let t = try? BertTokenizer() {
            tokenizer = t
        } else {
            tokenizer = BertTokenizer(vocab: [:])
        }

        let sentences = (0..<100).map { i in
            "Sentence number \(i) explaining how Apple Neural Engine accelerates semantic search indexing on macOS and iOS."
        }

        let tokenStart = ContinuousClock.now
        for s in sentences {
            _ = tokenizer.tokenize(s, maxLength: 128)
        }
        let tokenDuration = max(1e-6, tokenStart.duration(to: .now).asSeconds)
        let sentencesPerSec = Double(sentences.count) / tokenDuration

        let tokenizerMetrics = BenchmarkMetrics.TokenizerMetrics(
            sentenceCount: sentences.count,
            durationSeconds: tokenDuration,
            sentencesPerSecond: sentencesPerSec
        )

        return (chunkerMetrics, tokenizerMetrics, tokenizer)
    }

    // MARK: - Stage 2 Implementation

    private static func benchmarkInference(
        tokenizer: BertTokenizer,
        customModel: EmbeddingGenerator?
    ) async throws -> BenchmarkMetrics.ModelInferenceMetrics {
        let model: EmbeddingGenerator
        if let custom = customModel {
            model = custom
        } else {
            model = CoreMLEmbeddingModel.loadDefaultModel(tokenizer: tokenizer)
        }

        let isCoreML = model is CoreMLEmbeddingModel
        let modelName = isCoreML
            ? "all-MiniLM-L6-v2 (Apple Neural Engine / Core ML)"
            : "\(type(of: model))"

        // Warmup inferences to prime ANE/Core ML pipeline
        let warmupCount = 2
        for i in 0..<warmupCount {
            _ = try await model.generateEmbedding(for: "Warmup inference \(i) for Apple Neural Engine pipeline.")
        }

        // Measure 50 inferences
        let inferenceCount = 50
        let testInputs = (0..<inferenceCount).map { i in
            "Apple Silicon Neural Engine accelerates private on-device semantic vector retrieval iteration \(i)"
        }

        let infStart = ContinuousClock.now
        for input in testInputs {
            _ = try await model.generateEmbedding(for: input)
        }
        let infDuration = max(1e-6, infStart.duration(to: .now).asSeconds)
        let avgLatencyMs = (infDuration / Double(inferenceCount)) * 1000.0
        let throughput = Double(inferenceCount) / infDuration

        return BenchmarkMetrics.ModelInferenceMetrics(
            modelName: modelName,
            isCoreML: isCoreML,
            warmupCount: warmupCount,
            inferenceCount: inferenceCount,
            durationSeconds: infDuration,
            averageLatencyMs: avgLatencyMs,
            embeddingsPerSecond: throughput
        )
    }

    // MARK: - Stage 3 Implementation

    private static func benchmarkVectorStore(vectorCount: Int) throws -> BenchmarkMetrics.VectorStoreMetrics {
        let store = try VectorStore(at: nil)
        try store.createSchema()

        let fileId = try store.insertFile(
            path: "/benchmark/in_memory_synthetic.txt",
            mtime: Date(),
            size: Int64(vectorCount * 512)
        )

        // Generate synthetic normalized 384-dimensional vectors
        let vectors = (0..<vectorCount).map { makeNormalizedVector(seed: $0, dimension: 384) }

        // Measure insertion throughput
        let insertStart = ContinuousClock.now
        for (idx, vec) in vectors.enumerated() {
            try store.insertChunk(
                fileId: fileId,
                chunkIndex: idx,
                content: "Synthetic benchmark chunk \(idx) for SQLite vector and FTS5 BM25 evaluation on Apple Silicon.",
                embedding: vec
            )
        }
        let insertDuration = max(1e-6, insertStart.duration(to: .now).asSeconds)
        let vectorsPerSec = Double(vectorCount) / insertDuration

        // Measure Top-10 vector query latency over 50 iterations
        let vectorQueryIterations = 50
        var vectorLatenciesMs: [Double] = []
        vectorLatenciesMs.reserveCapacity(vectorQueryIterations)

        for i in 0..<vectorQueryIterations {
            let qVec = makeNormalizedVector(seed: 10_000 + i, dimension: 384)
            let qStart = ContinuousClock.now
            let results = try store.search(queryVector: qVec, limit: 10)
            _ = results
            let qDur = qStart.duration(to: .now).asSeconds * 1000.0
            vectorLatenciesMs.append(qDur)
        }

        let sortedVecLatencies = vectorLatenciesMs.sorted()
        let vecP50 = calculatePercentile(sortedVecLatencies, percentile: 0.50)
        let vecP95 = calculatePercentile(sortedVecLatencies, percentile: 0.95)
        let vecAvg = vectorLatenciesMs.reduce(0, +) / Double(max(1, vectorLatenciesMs.count))

        // Measure FTS5 BM25 keyword query latency over 50 iterations
        let keywordQueryIterations = 50
        var keywordLatenciesMs: [Double] = []
        keywordLatenciesMs.reserveCapacity(keywordQueryIterations)

        let testKeywords = [
            "Apple Silicon",
            "benchmark chunk",
            "SQLite vector",
            "FTS5 BM25",
            "evaluation"
        ]

        for i in 0..<keywordQueryIterations {
            let term = testKeywords[i % testKeywords.count]
            let qStart = ContinuousClock.now
            let results = try store.searchBM25(query: term, limit: 10)
            _ = results
            let qDur = qStart.duration(to: .now).asSeconds * 1000.0
            keywordLatenciesMs.append(qDur)
        }

        let sortedKeyLatencies = keywordLatenciesMs.sorted()
        let keyP50 = calculatePercentile(sortedKeyLatencies, percentile: 0.50)
        let keyP95 = calculatePercentile(sortedKeyLatencies, percentile: 0.95)
        let keyAvg = keywordLatenciesMs.reduce(0, +) / Double(max(1, keywordLatenciesMs.count))

        store.close()

        return BenchmarkMetrics.VectorStoreMetrics(
            vectorCount: vectorCount,
            dimensions: 384,
            insertionDurationSeconds: insertDuration,
            vectorsPerSecond: vectorsPerSec,
            vectorQueryIterations: vectorQueryIterations,
            vectorQueryP50Ms: vecP50,
            vectorQueryP95Ms: vecP95,
            vectorQueryAverageMs: vecAvg,
            keywordQueryIterations: keywordQueryIterations,
            keywordQueryP50Ms: keyP50,
            keywordQueryP95Ms: keyP95,
            keywordQueryAverageMs: keyAvg
        )
    }

    // MARK: - Stage 4 Implementation

    private static func benchmarkResources() -> BenchmarkMetrics.ResourceMetrics {
        let peakBytes = queryPeakMemoryRSS()
        let peakMB = Double(peakBytes) / (1024.0 * 1024.0)
        let activeSockets = countActiveInternetSockets()
        let zeroTransmission = (activeSockets == 0)

        return BenchmarkMetrics.ResourceMetrics(
            peakMemoryBytes: peakBytes,
            peakMemoryMB: peakMB,
            activeInternetSockets: activeSockets,
            zeroNetworkTransmission: zeroTransmission
        )
    }

    // MARK: - System Detection & Helpers

    public static func detectSystem() -> BenchmarkMetrics.SystemInfo {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"

        var architecture = "arm64"
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x86_64"
        #endif
        if let machine = getSysctlString(name: "hw.machine"), !machine.isEmpty {
            architecture = machine
        }

        let modelIdentifier = getSysctlString(name: "hw.model") ?? "Apple Silicon"
        let brandString = getSysctlString(name: "machdep.cpu.brand_string")
        let chipModel = (brandString != nil && !brandString!.isEmpty) ? brandString! : modelIdentifier

        return BenchmarkMetrics.SystemInfo(
            osVersion: osVersion,
            architecture: architecture,
            chipModel: chipModel,
            modelIdentifier: modelIdentifier
        )
    }

    public static func getSysctlString(name: String) -> String? {
        #if canImport(Darwin)
        var size: Int = 0
        let err = sysctlbyname(name, nil, &size, nil, 0)
        guard err == 0, size > 0 else { return nil }
        var data = [CChar](repeating: 0, count: size)
        let result = sysctlbyname(name, &data, &size, nil, 0)
        guard result == 0 else { return nil }
        return String(cString: data).trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    public static func queryPeakMemoryRSS() -> UInt64 {
        #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return UInt64(info.resident_size_max)
        }
        #endif
        return 0
    }

    public static func countActiveInternetSockets() -> Int {
        #if os(macOS)
        let pid = getpid()
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return 0 }
        let count = Int(bufferSize) / MemoryLayout<proc_fdinfo>.stride
        var fdList = [proc_fdinfo](repeating: proc_fdinfo(), count: count)
        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdList, bufferSize)
        guard actualSize > 0 else { return 0 }

        let actualCount = Int(actualSize) / MemoryLayout<proc_fdinfo>.stride
        var internetSocketCount = 0

        for i in 0..<min(count, actualCount) {
            let fd = fdList[i]
            if fd.proc_fdtype == PROX_FDTYPE_SOCKET {
                var sockInfo = socket_fdinfo()
                let ret = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &sockInfo, Int32(MemoryLayout<socket_fdinfo>.size))
                if ret > 0 {
                    let family = sockInfo.psi.soi_family
                    if family == AF_INET || family == AF_INET6 {
                        internetSocketCount += 1
                    }
                }
            }
        }
        return internetSocketCount
        #else
        return 0
        #endif
    }

    public static func calculatePercentile(_ sortedArray: [Double], percentile: Double) -> Double {
        guard !sortedArray.isEmpty else { return 0.0 }
        if sortedArray.count == 1 { return sortedArray[0] }
        let index = Double(sortedArray.count - 1) * max(0.0, min(1.0, percentile))
        let lower = Int(floor(index))
        let upper = Int(ceil(index))
        if lower == upper {
            return sortedArray[lower]
        }
        let fraction = index - Double(lower)
        return sortedArray[lower] + fraction * (sortedArray[upper] - sortedArray[lower])
    }

    public static func makeNormalizedVector(seed: Int, dimension: Int = 384) -> [Float] {
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
}
