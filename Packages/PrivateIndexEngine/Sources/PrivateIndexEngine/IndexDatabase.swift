import Foundation

// MARK: - IndexDatabase

/// SQLite database engine combining vector similarity search via `sqlite-vec`
/// and BM25 full-text keyword search via SQLite FTS5.
///
/// `IndexDatabase` is unified with `VectorStore` to provide single-connection access
/// to document chunking, dense vector representations, and inverted keyword indexes.
public typealias IndexDatabase = VectorStore
