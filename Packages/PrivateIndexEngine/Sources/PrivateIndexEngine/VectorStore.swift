import Foundation
import SQLite3
import CSQLiteVec

// SQLITE_TRANSIENT tells SQLite to make its own copy of the data
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - VectorStore

/// A SQLite-backed vector store using the `sqlite-vec` extension for cosine-distance
/// nearest-neighbor search over 384-dimensional embeddings.
///
/// Thread Safety: This type is **not** thread-safe. Access from a single serial queue
/// or use external synchronization.
public final class VectorStore {

    // MARK: - Types

    /// A record of an indexed file stored in SQLite.
    public struct FileRecord: Sendable, Equatable {
        public let id: Int64
        public let path: String
        public let mtime: Date
        public let size: Int64

        public init(id: Int64, path: String, mtime: Date, size: Int64) {
            self.id = id
            self.path = path
            self.mtime = mtime
            self.size = size
        }
    }

    /// A search result containing the chunk ID, source file information, cosine distance, and text content.
    public struct SearchResult: Sendable, Equatable {
        public let chunkId: Int64
        public let fileId: Int64
        public let filePath: String
        public let distance: Float
        public let content: String

        public init(chunkId: Int64, fileId: Int64, filePath: String, distance: Float, content: String) {
            self.chunkId = chunkId
            self.fileId = fileId
            self.filePath = filePath
            self.distance = distance
            self.content = content
        }
    }

    /// Errors specific to VectorStore operations.
    public enum StoreError: Error, CustomStringConvertible {
        case openFailed(String)
        case sqlError(String)
        case extensionRegistrationFailed(String)

        public var description: String {
            switch self {
            case .openFailed(let msg):
                return "VectorStore.openFailed: \(msg)"
            case .sqlError(let msg):
                return "VectorStore.sqlError: \(msg)"
            case .extensionRegistrationFailed(let msg):
                return "VectorStore.extensionRegistrationFailed: \(msg)"
            }
        }
    }

    // MARK: - Properties

    /// The embedding dimension. Must match the Core ML model output.
    public static let embeddingDimension = 384

    private var db: OpaquePointer?

    // MARK: - Initialization

    /// Opens (or creates) the database at `url`, enables WAL mode, and registers the
    /// `sqlite-vec` extension.
    ///
    /// - Parameter url: File URL for the database. Pass `nil` to open an in-memory database.
    public init(at url: URL? = nil) throws {
        let path = url?.path ?? ":memory:"

        var dbPointer: OpaquePointer?
        let openResult = sqlite3_open_v2(
            path,
            &dbPointer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let db = dbPointer else {
            let errMsg = dbPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(dbPointer)
            throw StoreError.openFailed("\(errMsg) (code \(openResult))")
        }
        self.db = db

        // Register sqlite-vec directly on this connection (avoids deprecated
        // sqlite3_auto_extension on Apple platforms)
        var errMsg: UnsafeMutablePointer<CChar>?
        let vecResult = sqlite3_vec_init(db, &errMsg, nil)
        guard vecResult == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_close(db)
            self.db = nil
            throw StoreError.extensionRegistrationFailed(
                "sqlite3_vec_init failed: \(msg) (code \(vecResult))"
            )
        }

        // Enable WAL mode for better concurrent read performance
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        close()
    }

    // MARK: - Schema

    /// Creates the database schema if it does not already exist.
    ///
    /// Tables:
    /// - `indexed_files`: Tracks indexed file metadata (path, mtime, size).
    /// - `text_chunks`: Stores chunked text content linked to a file.
    /// - `vec_chunks`: Virtual table for vector similarity search (cosine distance).
    public func createSchema() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS indexed_files (
                id    INTEGER PRIMARY KEY AUTOINCREMENT,
                path  TEXT    NOT NULL UNIQUE,
                mtime REAL    NOT NULL,
                size  INTEGER NOT NULL
            );
        """)

        try execute("""
            CREATE TABLE IF NOT EXISTS text_chunks (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                file_id     INTEGER NOT NULL REFERENCES indexed_files(id) ON DELETE CASCADE,
                chunk_index INTEGER NOT NULL,
                content     TEXT    NOT NULL
            );
        """)

        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS vec_chunks USING vec0(
                chunk_id    INTEGER PRIMARY KEY,
                embedding   float[384] distance_metric=cosine
            );
        """)
    }

    // MARK: - File Operations

    /// Inserts a file record into `indexed_files`.
    ///
    /// - Returns: The `rowid` of the newly inserted file.
    @discardableResult
    public func insertFile(path: String, mtime: Date, size: Int64) throws -> Int64 {
        let sql = "INSERT INTO indexed_files (path, mtime, size) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        try prepareStatement(sql, into: &stmt)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, mtime.timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 3, sqlite3_int64(size))

        let stepResult = sqlite3_step(stmt)
        guard stepResult == SQLITE_DONE else {
            throw StoreError.sqlError(lastErrorMessage())
        }

        return sqlite3_last_insert_rowid(db)
    }

    /// Fetches an indexed file by its path.
    public func getFile(byPath path: String) throws -> FileRecord? {
        let sql = "SELECT id, path, mtime, size FROM indexed_files WHERE path = ? LIMIT 1;"
        var stmt: OpaquePointer?
        try prepareStatement(sql, into: &stmt)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (path as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let pathStr = String(cString: sqlite3_column_text(stmt, 1))
            let mtimeSec = sqlite3_column_double(stmt, 2)
            let size = sqlite3_column_int64(stmt, 3)
            return FileRecord(id: id, path: pathStr, mtime: Date(timeIntervalSince1970: mtimeSec), size: size)
        }
        return nil
    }

    /// Fetches all indexed files mapped by their file paths.
    public func getAllIndexedFiles() throws -> [String: FileRecord] {
        let sql = "SELECT id, path, mtime, size FROM indexed_files;"
        var stmt: OpaquePointer?
        try prepareStatement(sql, into: &stmt)
        defer { sqlite3_finalize(stmt) }

        var files: [String: FileRecord] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let pathStr = String(cString: sqlite3_column_text(stmt, 1))
            let mtimeSec = sqlite3_column_double(stmt, 2)
            let size = sqlite3_column_int64(stmt, 3)
            let record = FileRecord(id: id, path: pathStr, mtime: Date(timeIntervalSince1970: mtimeSec), size: size)
            files[pathStr] = record
        }
        return files
    }

    /// Deletes a file and all its associated text chunks and vector embeddings.
    public func deleteFile(id: Int64) throws {
        try execute("BEGIN TRANSACTION;")
        do {
            // Delete corresponding vector embeddings
            let delVecSQL = "DELETE FROM vec_chunks WHERE chunk_id IN (SELECT id FROM text_chunks WHERE file_id = ?);"
            var vecStmt: OpaquePointer?
            try prepareStatement(delVecSQL, into: &vecStmt)
            sqlite3_bind_int64(vecStmt, 1, id)
            if sqlite3_step(vecStmt) != SQLITE_DONE {
                sqlite3_finalize(vecStmt)
                throw StoreError.sqlError("vec_chunks deletion failed: \(lastErrorMessage())")
            }
            sqlite3_finalize(vecStmt)

            // Delete text chunks
            let delChunkSQL = "DELETE FROM text_chunks WHERE file_id = ?;"
            var chunkStmt: OpaquePointer?
            try prepareStatement(delChunkSQL, into: &chunkStmt)
            sqlite3_bind_int64(chunkStmt, 1, id)
            if sqlite3_step(chunkStmt) != SQLITE_DONE {
                sqlite3_finalize(chunkStmt)
                throw StoreError.sqlError("text_chunks deletion failed: \(lastErrorMessage())")
            }
            sqlite3_finalize(chunkStmt)

            // Delete file record
            let delFileSQL = "DELETE FROM indexed_files WHERE id = ?;"
            var fileStmt: OpaquePointer?
            try prepareStatement(delFileSQL, into: &fileStmt)
            sqlite3_bind_int64(fileStmt, 1, id)
            if sqlite3_step(fileStmt) != SQLITE_DONE {
                sqlite3_finalize(fileStmt)
                throw StoreError.sqlError("indexed_files deletion failed: \(lastErrorMessage())")
            }
            sqlite3_finalize(fileStmt)

            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    /// Deletes a file by path and all its associated text chunks and vector embeddings.
    public func deleteFile(path: String) throws {
        if let file = try getFile(byPath: path) {
            try deleteFile(id: file.id)
        }
    }

    // MARK: - Chunk Operations

    /// Inserts a text chunk and its embedding vector into the database.
    ///
    /// This inserts into both `text_chunks` and the `vec_chunks` virtual table
    /// within a single transaction.
    ///
    /// - Parameters:
    ///   - fileId: The `id` from `indexed_files`.
    ///   - chunkIndex: The chunk's position within the file.
    ///   - content: The chunk's text content.
    ///   - embedding: A 384-dimensional float vector (must be L2-normalized).
    /// - Returns: The `rowid` of the inserted chunk.
    @discardableResult
    public func insertChunk(
        fileId: Int64,
        chunkIndex: Int,
        content: String,
        embedding: [Float]
    ) throws -> Int64 {
        precondition(
            embedding.count == Self.embeddingDimension,
            "Embedding must have \(Self.embeddingDimension) dimensions, got \(embedding.count)"
        )

        try execute("BEGIN TRANSACTION;")

        do {
            // Insert into text_chunks
            let chunkSQL = """
                INSERT INTO text_chunks (file_id, chunk_index, content) VALUES (?, ?, ?);
            """
            var chunkStmt: OpaquePointer?
            try prepareStatement(chunkSQL, into: &chunkStmt)
            defer { sqlite3_finalize(chunkStmt) }

            sqlite3_bind_int64(chunkStmt, 1, sqlite3_int64(fileId))
            sqlite3_bind_int(chunkStmt, 2, Int32(chunkIndex))
            sqlite3_bind_text(chunkStmt, 3, (content as NSString).utf8String, -1, nil)

            let chunkStep = sqlite3_step(chunkStmt)
            guard chunkStep == SQLITE_DONE else {
                throw StoreError.sqlError("text_chunks insert: \(lastErrorMessage())")
            }

            let chunkId = sqlite3_last_insert_rowid(db)

            // Insert into vec_chunks
            let vecSQL = "INSERT INTO vec_chunks (chunk_id, embedding) VALUES (?, ?);"
            var vecStmt: OpaquePointer?
            try prepareStatement(vecSQL, into: &vecStmt)
            defer { sqlite3_finalize(vecStmt) }

            sqlite3_bind_int64(vecStmt, 1, sqlite3_int64(chunkId))

            // Bind the embedding as a blob of raw float bytes
            let blobSize = embedding.count * MemoryLayout<Float>.size
            _ = embedding.withUnsafeBufferPointer { buffer in
                sqlite3_bind_blob(
                    vecStmt,
                    2,
                    buffer.baseAddress,
                    Int32(blobSize),
                    SQLITE_TRANSIENT
                )
            }

            let vecStep = sqlite3_step(vecStmt)
            guard vecStep == SQLITE_DONE else {
                throw StoreError.sqlError("vec_chunks insert: \(lastErrorMessage())")
            }

            try execute("COMMIT;")
            return chunkId
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    // MARK: - Search

    /// Performs a cosine-distance nearest-neighbor search.
    ///
    /// - Parameters:
    ///   - queryVector: A 384-dimensional float query vector.
    ///   - limit: Maximum number of results to return (default 10).
    /// - Returns: An array of `SearchResult` ordered by increasing cosine distance.
    public func search(queryVector: [Float], limit: Int = 10) throws -> [SearchResult] {
        precondition(
            queryVector.count == Self.embeddingDimension,
            "Query vector must have \(Self.embeddingDimension) dimensions, got \(queryVector.count)"
        )

        let sql = """
            SELECT vc.chunk_id, f.id, f.path, vc.distance, tc.content
            FROM vec_chunks vc
            JOIN text_chunks tc ON tc.id = vc.chunk_id
            JOIN indexed_files f ON f.id = tc.file_id
            WHERE vc.embedding MATCH ? AND k = ?
            ORDER BY vc.distance;
        """

        var stmt: OpaquePointer?
        try prepareStatement(sql, into: &stmt)
        defer { sqlite3_finalize(stmt) }

        // Bind the query vector as a blob
        let blobSize = queryVector.count * MemoryLayout<Float>.size
        _ = queryVector.withUnsafeBufferPointer { buffer in
            sqlite3_bind_blob(
                stmt,
                1,
                buffer.baseAddress,
                Int32(blobSize),
                SQLITE_TRANSIENT
            )
        }

        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunkId = sqlite3_column_int64(stmt, 0)
            let fileId = sqlite3_column_int64(stmt, 1)
            let filePath = String(cString: sqlite3_column_text(stmt, 2))
            let distance = Float(sqlite3_column_double(stmt, 3))
            let content: String
            if let cStr = sqlite3_column_text(stmt, 4) {
                content = String(cString: cStr)
            } else {
                content = ""
            }
            results.append(SearchResult(
                chunkId: chunkId,
                fileId: fileId,
                filePath: filePath,
                distance: distance,
                content: content
            ))
        }

        return results
    }

    // MARK: - Lifecycle

    /// Closes the database connection.
    public func close() {
        if let db = db {
            sqlite3_close_v2(db)
            self.db = nil
        }
    }

    // MARK: - Private Helpers

    private func execute(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errMsg)
            throw StoreError.sqlError("\(msg) (code \(result))")
        }
    }

    private func prepareStatement(_ sql: String, into stmt: inout OpaquePointer?) throws {
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK else {
            throw StoreError.sqlError("prepare failed: \(lastErrorMessage()) (code \(result))")
        }
    }

    private func lastErrorMessage() -> String {
        if let db = db {
            return String(cString: sqlite3_errmsg(db))
        }
        return "no database connection"
    }
}
