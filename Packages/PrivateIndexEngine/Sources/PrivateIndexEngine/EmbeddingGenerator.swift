import Foundation
import CoreML

// MARK: - EmbeddingGenerator Protocol

/// Defines the interface for generating dense semantic vector embeddings from text.
public protocol EmbeddingGenerator: Sendable {
    /// Dimension of the output embedding vector (e.g., 384 for all-MiniLM-L6-v2).
    var embeddingDimension: Int { get }
    /// Maximum sequence length supported by the model (e.g., 128 tokens).
    var maxSequenceLength: Int { get }

    /// Generates a normalized embedding vector for a single string of text.
    func generateEmbedding(for text: String) async throws -> [Float]

    /// Generates normalized embedding vectors for an array of text chunks.
    func generateEmbeddings(for texts: [String]) async throws -> [[Float]]
}

extension EmbeddingGenerator {
    /// Default sequential implementation for multiple texts.
    public func generateEmbeddings(for texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            let vec = try await generateEmbedding(for: text)
            results.append(vec)
        }
        return results
    }
}

// MARK: - CoreMLEmbeddingModel

/// Executes on-device inference using an ANE-optimized Core ML `.mlpackage` / `.mlmodelc`.
public final class CoreMLEmbeddingModel: EmbeddingGenerator, @unchecked Sendable {
    public let embeddingDimension: Int
    public let maxSequenceLength: Int

    private let model: MLModel
    private let tokenizer: BertTokenizer

    /// Initializes from an existing `MLModel` instance and tokenizer.
    public init(
        model: MLModel,
        tokenizer: BertTokenizer,
        dimension: Int = 384,
        maxSequenceLength: Int = 128
    ) {
        self.model = model
        self.tokenizer = tokenizer
        self.embeddingDimension = dimension
        self.maxSequenceLength = maxSequenceLength
    }

    /// Convenience initializer that compiles and loads a model from a file URL.
    public convenience init(
        modelURL: URL,
        tokenizer: BertTokenizer,
        dimension: Int = 384,
        maxSequenceLength: Int = 128
    ) throws {
        let compiledURL: URL
        if modelURL.pathExtension == "mlpackage" || modelURL.pathExtension == "mlmodel" {
            compiledURL = try MLModel.compileModel(at: modelURL)
        } else {
            compiledURL = modelURL
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all

        let model = try MLModel(contentsOf: compiledURL, configuration: config)
        self.init(model: model, tokenizer: tokenizer, dimension: dimension, maxSequenceLength: maxSequenceLength)
    }

    /// Loads the Core ML model from bundle resources, Homebrew pkgshare, or user directory, falling back to mock if unavailable.
    public static func loadDefaultModel(tokenizer: BertTokenizer) -> EmbeddingGenerator {
        let modelName = "all-MiniLM-L6-v2"
        let fileManager = FileManager.default

        // 1. Check module bundle (SwiftPM resources)
        if let url = Bundle.module.url(forResource: modelName, withExtension: "mlmodelc"),
           let model = try? CoreMLEmbeddingModel(modelURL: url, tokenizer: tokenizer) {
            return model
        }
        if let url = Bundle.module.url(forResource: modelName, withExtension: "mlpackage"),
           let model = try? CoreMLEmbeddingModel(modelURL: url, tokenizer: tokenizer) {
            return model
        }

        // 2. Check main app bundle (macOS & iOS app Contents/Resources)
        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc"),
           let model = try? CoreMLEmbeddingModel(modelURL: url, tokenizer: tokenizer) {
            return model
        }
        if let url = Bundle.main.url(forResource: modelName, withExtension: "mlpackage"),
           let model = try? CoreMLEmbeddingModel(modelURL: url, tokenizer: tokenizer) {
            return model
        }

        #if os(macOS)
        // 3. Check Homebrew pkgshare and standard locations
        let standardPaths = [
            "/opt/homebrew/share/private-index/models/\(modelName).mlmodelc",
            "/usr/local/share/private-index/models/\(modelName).mlmodelc",
            "/opt/homebrew/share/private-index/\(modelName).mlmodelc",
            "/usr/local/share/private-index/\(modelName).mlmodelc"
        ]
        for path in standardPaths {
            let url = URL(fileURLWithPath: path)
            if fileManager.fileExists(atPath: url.path),
               let model = try? CoreMLEmbeddingModel(modelURL: url, tokenizer: tokenizer) {
                return model
            }
        }

        // 4. Check user models directory (~/.private-index/models/)
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let userModelURL = homeDir.appendingPathComponent(".private-index/models/\(modelName).mlmodelc")
        if fileManager.fileExists(atPath: userModelURL.path),
           let model = try? CoreMLEmbeddingModel(modelURL: userModelURL, tokenizer: tokenizer) {
            return model
        }
        #elseif os(iOS)
        // 3. Check iOS app sandbox documents directory
        if let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelURL = docsDir.appendingPathComponent("models/\(modelName).mlmodelc")
            if fileManager.fileExists(atPath: modelURL.path),
               let model = try? CoreMLEmbeddingModel(modelURL: modelURL, tokenizer: tokenizer) {
                return model
            }
        }
        #endif

        // 5. Fallback for unit testing and offline development
        return MockEmbeddingModel()
    }

    public func generateEmbedding(for text: String) async throws -> [Float] {
        let tokenized = tokenizer.tokenize(text, maxLength: maxSequenceLength)

        let inputIDsArray = try createMultiArray(from: tokenized.inputIDs, shape: [1, NSNumber(value: maxSequenceLength)])
        let attentionMaskArray = try createMultiArray(from: tokenized.attentionMask, shape: [1, NSNumber(value: maxSequenceLength)])

        let featureProvider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDsArray),
            "attention_mask": MLFeatureValue(multiArray: attentionMaskArray),
        ])

        let prediction = try await model.prediction(from: featureProvider)

        // Find the output MultiArray (first feature or specific name)
        guard let outputFeatureName = prediction.featureNames.first,
              let outputValue = prediction.featureValue(for: outputFeatureName),
              let multiArray = outputValue.multiArrayValue else {
            throw EmbeddingError.invalidOutput("Could not extract multiArray output from Core ML prediction")
        }

        return extractFloatArray(from: multiArray, expectedCount: embeddingDimension)
    }

    private func createMultiArray(from values: [Int32], shape: [NSNumber]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: shape, dataType: .int32)
        let ptr = array.dataPointer.bindMemory(to: Int32.self, capacity: values.count)
        for (i, val) in values.enumerated() {
            ptr[i] = val
        }
        return array
    }

    private func extractFloatArray(from multiArray: MLMultiArray, expectedCount: Int) -> [Float] {
        var result = [Float](repeating: 0, count: expectedCount)
        let totalCount = multiArray.count
        let count = min(totalCount, expectedCount)

        switch multiArray.dataType {
        case .float32:
            let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: totalCount)
            for i in 0..<count {
                result[i] = ptr[i]
            }
        case .float16:
            let ptr = multiArray.dataPointer.bindMemory(to: UInt16.self, capacity: totalCount)
            for i in 0..<count {
                let float16Val = Float16(bitPattern: ptr[i])
                result[i] = Float(float16Val)
            }
        case .double:
            let ptr = multiArray.dataPointer.bindMemory(to: Double.self, capacity: totalCount)
            for i in 0..<count {
                result[i] = Float(ptr[i])
            }
        default:
            for i in 0..<count {
                result[i] = multiArray[i].floatValue
            }
        }

        return result
    }

    public enum EmbeddingError: Error, CustomStringConvertible {
        case invalidOutput(String)

        public var description: String {
            switch self {
            case .invalidOutput(let msg): return "CoreMLEmbeddingModel.EmbeddingError: \(msg)"
            }
        }
    }
}

// MARK: - MockEmbeddingModel

/// Deterministic, zero-weight embedding generator for fast unit testing and offline development.
///
/// Produces normalized 384-dimensional vectors deterministically computed from the input text's hash.
public final class MockEmbeddingModel: EmbeddingGenerator, @unchecked Sendable {
    public let embeddingDimension: Int
    public let maxSequenceLength: Int

    public init(dimension: Int = 384, maxSequenceLength: Int = 128) {
        self.embeddingDimension = dimension
        self.maxSequenceLength = maxSequenceLength
    }

    public func generateEmbedding(for text: String) async throws -> [Float] {
        var vector = [Float](repeating: 0, count: embeddingDimension)

        // Seed a deterministic pseudo-random generator with the string's hash
        var hash: UInt64 = 5381
        for byte in text.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }

        // Generate values
        var normSq: Float = 0
        for i in 0..<embeddingDimension {
            hash = hash &* 6364136223846793005 &+ 1442695040888963407
            let val = Float(Int32(truncatingIfNeeded: hash >> 32)) / Float(Int32.max)
            vector[i] = val
            normSq += val * val
        }

        // L2 normalize
        let norm = sqrt(max(normSq, 1e-12))
        for i in 0..<embeddingDimension {
            vector[i] /= norm
        }

        return vector
    }
}
