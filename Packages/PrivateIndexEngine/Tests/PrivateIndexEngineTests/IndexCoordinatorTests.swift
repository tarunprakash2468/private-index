import XCTest
@testable import PrivateIndexEngine

final class IndexCoordinatorTests: XCTestCase {

    private var tempDir: URL!
    private var vectorStore: VectorStore!
    private var coordinator: IndexCoordinator!
    private var embeddingModel: MockEmbeddingModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexCoordinatorTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        vectorStore = try VectorStore(at: nil)  // in-memory database
        try vectorStore.createSchema()

        embeddingModel = MockEmbeddingModel()
        coordinator = IndexCoordinator(
            vectorStore: vectorStore,
            fileCrawler: FileCrawler(),
            textChunker: TextChunker(windowSize: 200, overlap: 50),
            embeddingModel: embeddingModel
        )
    }

    override func tearDownWithError() throws {
        vectorStore?.close()
        vectorStore = nil
        coordinator = nil
        embeddingModel = nil
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testIndexAndSearchEndToEnd() async throws {
        let file1 = tempDir.appendingPathComponent("swift_guide.md")
        let file2 = tempDir.appendingPathComponent("ane_hardware.txt")

        try "Swift is a modern, fast, and safe programming language for Apple platforms.".write(
            to: file1,
            atomically: true,
            encoding: .utf8
        )
        try "The Apple Neural Engine accelerates tensor computation and deep learning on-device.".write(
            to: file2,
            atomically: true,
            encoding: .utf8
        )

        let report = try await coordinator.index(directoryURL: tempDir)
        XCTAssertEqual(report.filesScanned, 2)
        XCTAssertEqual(report.filesIndexed, 2)
        XCTAssertEqual(report.filesSkipped, 0)
        XCTAssertEqual(report.filesDeleted, 0)
        XCTAssertGreaterThan(report.chunksIndexed, 0)

        // Exact query matching chunk content will produce distance near 0 with MockEmbeddingModel
        let results = try await coordinator.search(
            query: "Swift is a modern, fast, and safe programming language for Apple platforms.",
            limit: 5,
            mode: .vector
        )

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results[0].filePath, file1.standardizedFileURL.path)
        XCTAssertLessThan(results[0].distance, 0.01)
        XCTAssertGreaterThan(results[0].score, 0.99)
        XCTAssertEqual(results[0].matchType, "vector")

        // Hybrid search with default mode should also rank the exact file top with hybrid matchType
        let hybridResults = try await coordinator.search(
            query: "Swift is a modern, fast, and safe programming language for Apple platforms.",
            limit: 5
        )
        XCTAssertFalse(hybridResults.isEmpty)
        XCTAssertEqual(hybridResults[0].filePath, file1.standardizedFileURL.path)
        XCTAssertEqual(hybridResults[0].matchType, "hybrid")
        XCTAssertGreaterThan(hybridResults[0].score, 0.0)
    }

    func testIncrementalIndexingSkipsUnchangedFiles() async throws {
        let file1 = tempDir.appendingPathComponent("doc1.txt")
        let file2 = tempDir.appendingPathComponent("doc2.txt")

        try "Content of document one".write(to: file1, atomically: true, encoding: .utf8)
        try "Content of document two".write(to: file2, atomically: true, encoding: .utf8)

        // First index run
        let initialReport = try await coordinator.index(directoryURL: tempDir)
        XCTAssertEqual(initialReport.filesIndexed, 2)
        XCTAssertEqual(initialReport.filesSkipped, 0)

        // Second index run without file changes
        let secondReport = try await coordinator.index(directoryURL: tempDir)
        XCTAssertEqual(secondReport.filesIndexed, 0, "No files should be re-indexed")
        XCTAssertEqual(secondReport.filesSkipped, 2, "Both unchanged files should be skipped")
        XCTAssertEqual(secondReport.filesDeleted, 0)
    }

    func testIncrementalIndexingDetectsModifiedFiles() async throws {
        let file1 = tempDir.appendingPathComponent("stable.txt")
        let file2 = tempDir.appendingPathComponent("dynamic.txt")

        try "Stable content".write(to: file1, atomically: true, encoding: .utf8)
        try "Initial dynamic content".write(to: file2, atomically: true, encoding: .utf8)

        _ = try await coordinator.index(directoryURL: tempDir)

        // Give a slight delay to ensure a different modification timestamp
        try await Task.sleep(nanoseconds: 50_000_000)

        // Modify file2
        try "Updated dynamic content with new information".write(to: file2, atomically: true, encoding: .utf8)

        let updateReport = try await coordinator.index(directoryURL: tempDir)
        XCTAssertEqual(updateReport.filesIndexed, 1, "Only modified file should be indexed")
        XCTAssertEqual(updateReport.filesSkipped, 1, "Unmodified file should be skipped")
        XCTAssertEqual(updateReport.filesDeleted, 0)
    }

    func testDeletedFilePrunedFromIndex() async throws {
        let file1 = tempDir.appendingPathComponent("keep.txt")
        let file2 = tempDir.appendingPathComponent("remove.txt")

        try "Keep this file".write(to: file1, atomically: true, encoding: .utf8)
        try "Delete this file".write(to: file2, atomically: true, encoding: .utf8)

        _ = try await coordinator.index(directoryURL: tempDir)

        // Delete file2 from disk
        try FileManager.default.removeItem(at: file2)

        let pruneReport = try await coordinator.index(directoryURL: tempDir)
        XCTAssertEqual(pruneReport.filesDeleted, 1, "Deleted file should be pruned from database")
        XCTAssertEqual(pruneReport.filesSkipped, 1, "Remaining file should be skipped")

        // Search for deleted file content should no longer return it
        let searchResults = try await coordinator.search(query: "Delete this file", limit: 10)
        let foundDeleted = searchResults.contains { $0.filePath == file2.standardizedFileURL.path }
        XCTAssertFalse(foundDeleted, "Deleted file should not appear in search results")
    }
}
