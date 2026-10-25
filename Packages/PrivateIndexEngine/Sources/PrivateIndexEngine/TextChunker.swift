import Foundation

// MARK: - TextChunker

/// A sliding-window character chunker that splits text into overlapping segments.
///
/// This chunker operates on **character count** (not byte count), correctly handling
/// multi-byte Unicode characters like emoji and CJK text.
///
/// Default parameters:
/// - Window size: 500 characters
/// - Overlap: 100 characters
/// - Stride (computed): 400 characters
public struct TextChunker: Sendable {

    // MARK: - Properties

    /// The maximum number of characters per chunk.
    public let windowSize: Int

    /// The number of characters of overlap between consecutive chunks.
    public let overlap: Int

    /// The stride (step size) between chunk start positions.
    public var stride: Int {
        windowSize - overlap
    }

    // MARK: - Initialization

    /// Creates a new `TextChunker`.
    ///
    /// - Parameters:
    ///   - windowSize: Maximum characters per chunk (default: 500). Must be > 0.
    ///   - overlap: Character overlap between consecutive chunks (default: 100). Must be ≥ 0 and < `windowSize`.
    public init(windowSize: Int = 500, overlap: Int = 100) {
        precondition(windowSize > 0, "windowSize must be > 0")
        precondition(overlap >= 0, "overlap must be ≥ 0")
        precondition(overlap < windowSize, "overlap must be < windowSize")

        self.windowSize = windowSize
        self.overlap = overlap
    }

    // MARK: - Chunking

    /// Splits `text` into overlapping character-window chunks.
    ///
    /// Behavior:
    /// - Empty string → empty array.
    /// - Text shorter than or equal to `windowSize` → single chunk (the full text).
    /// - Otherwise → sliding window with `stride` step, last chunk may be shorter.
    ///
    /// - Parameter text: The input text to chunk.
    /// - Returns: An array of chunk strings.
    public func chunk(_ text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }

        let characters = Array(text)
        let totalCount = characters.count

        // Short text: return as a single chunk
        if totalCount <= windowSize {
            return [text]
        }

        var chunks: [String] = []
        var start = 0

        while start < totalCount {
            let end = min(start + windowSize, totalCount)
            let chunk = String(characters[start..<end])
            chunks.append(chunk)

            // If we've reached the end, stop
            if end == totalCount {
                break
            }

            start += stride
        }

        return chunks
    }
}
