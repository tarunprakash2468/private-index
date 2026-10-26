import XCTest
@testable import PrivateIndexEngine

final class FileCrawlerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCrawlerTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testCrawlDiscoversSupportedFiles() throws {
        // Create files
        let mdFile = tempDir.appendingPathComponent("notes.md")
        let txtFile = tempDir.appendingPathComponent("doc.txt")
        let swiftFile = tempDir.appendingPathComponent("Main.swift")
        let pngFile = tempDir.appendingPathComponent("image.png")
        let mp3File = tempDir.appendingPathComponent("sound.mp3")
        let sqliteFile = tempDir.appendingPathComponent("database.sqlite")

        try "Hello markdown".write(to: mdFile, atomically: true, encoding: .utf8)
        try "Hello text".write(to: txtFile, atomically: true, encoding: .utf8)
        try "print(1)".write(to: swiftFile, atomically: true, encoding: .utf8)
        try "binary data".write(to: pngFile, atomically: true, encoding: .utf8)
        try "audio data".write(to: mp3File, atomically: true, encoding: .utf8)
        try "sqlite data".write(to: sqliteFile, atomically: true, encoding: .utf8)

        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)

        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })
        XCTAssertTrue(indexableNames.contains("notes.md"))
        XCTAssertTrue(indexableNames.contains("doc.txt"))
        XCTAssertTrue(indexableNames.contains("Main.swift"))
        XCTAssertTrue(indexableNames.contains("image.png"))
        XCTAssertFalse(indexableNames.contains("sound.mp3"))
        XCTAssertFalse(indexableNames.contains("database.sqlite"))
    }

    func testCrawlDiscoversAllSupportedImageExtensions() throws {
        let extensions = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp"]
        for ext in extensions {
            let fileURL = tempDir.appendingPathComponent("photo.\(ext)")
            try "fake image data".write(to: fileURL, atomically: true, encoding: .utf8)
        }

        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)
        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })

        for ext in extensions {
            XCTAssertTrue(
                indexableNames.contains("photo.\(ext)"),
                "Expected photo.\(ext) to be recognized as indexable"
            )
        }
    }

    func testCrawlSkipsHiddenFilesAndDirectories() throws {
        let hiddenDir = tempDir.appendingPathComponent(".hidden_dir")
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        let hiddenFileInDir = hiddenDir.appendingPathComponent("secret.md")
        try "secret".write(to: hiddenFileInDir, atomically: true, encoding: .utf8)

        let hiddenFile = tempDir.appendingPathComponent(".hidden_file.txt")
        try "hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)

        let visibleFile = tempDir.appendingPathComponent("visible.txt")
        try "visible".write(to: visibleFile, atomically: true, encoding: .utf8)

        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)

        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })
        XCTAssertTrue(indexableNames.contains("visible.txt"))
        XCTAssertFalse(indexableNames.contains(".hidden_file.txt"))
        XCTAssertFalse(indexableNames.contains("secret.md"))
    }

    func testCrawlSkipsExcludedDirectories() throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        let nodeDir = tempDir.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)

        let gitFile = gitDir.appendingPathComponent("COMMIT_EDITMSG")
        let nodeFile = nodeDir.appendingPathComponent("package.json")
        try "commit msg".write(to: gitFile, atomically: true, encoding: .utf8)
        try "{}".write(to: nodeFile, atomically: true, encoding: .utf8)

        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)

        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })
        XCTAssertFalse(indexableNames.contains("COMMIT_EDITMSG"))
        XCTAssertFalse(indexableNames.contains("package.json"))
    }

    func testCrawlEmptyDirectory() throws {
        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)

        XCTAssertTrue(result.indexableFiles.isEmpty)
        XCTAssertTrue(result.skippedEvicted.isEmpty)
    }
}
