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
        let sqliteFile = tempDir.appendingPathComponent("database.sqlite")

        try "Hello markdown".write(to: mdFile, atomically: true, encoding: .utf8)
        try "Hello text".write(to: txtFile, atomically: true, encoding: .utf8)
        try "print(1)".write(to: swiftFile, atomically: true, encoding: .utf8)
        try "binary data".write(to: pngFile, atomically: true, encoding: .utf8)
        try "sqlite data".write(to: sqliteFile, atomically: true, encoding: .utf8)

        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)

        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })
        XCTAssertTrue(indexableNames.contains("notes.md"))
        XCTAssertTrue(indexableNames.contains("doc.txt"))
        XCTAssertTrue(indexableNames.contains("Main.swift"))
        XCTAssertFalse(indexableNames.contains("image.png"))
        XCTAssertFalse(indexableNames.contains("database.sqlite"))
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

    func testCrawlTraversesDirectorySymlinks() throws {
        let targetDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileCrawlerSymlinkTarget_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: targetDir)
        }

        let docFile = targetDir.appendingPathComponent("linked_notes.md")
        let codeFile = targetDir.appendingPathComponent("linked_script.py")
        try "Symlinked markdown content".write(to: docFile, atomically: true, encoding: .utf8)
        try "print('symlinked')".write(to: codeFile, atomically: true, encoding: .utf8)

        let symlinkURL = tempDir.appendingPathComponent("DocumentsLink")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetDir)

        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)

        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })
        XCTAssertTrue(indexableNames.contains("linked_notes.md"))
        XCTAssertTrue(indexableNames.contains("linked_script.py"))
    }

    func testCrawlCircularSymlinksTerminateCleanly() throws {
        let dirA = tempDir.appendingPathComponent("dirA")
        let dirB = tempDir.appendingPathComponent("dirB")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)

        let fileA = dirA.appendingPathComponent("fileA.txt")
        let fileB = dirB.appendingPathComponent("fileB.txt")
        try "Content A".write(to: fileA, atomically: true, encoding: .utf8)
        try "Content B".write(to: fileB, atomically: true, encoding: .utf8)

        // Create circular symlink: dirA/toB -> dirB and dirB/toA -> dirA
        let linkToB = dirA.appendingPathComponent("toB")
        let linkToA = dirB.appendingPathComponent("toA")
        try FileManager.default.createSymbolicLink(at: linkToB, withDestinationURL: dirB)
        try FileManager.default.createSymbolicLink(at: linkToA, withDestinationURL: dirA)

        // Create self-referential loop: dirA/selfLink -> dirA
        let selfLink = dirA.appendingPathComponent("selfLink")
        try FileManager.default.createSymbolicLink(at: selfLink, withDestinationURL: dirA)

        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)

        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })
        XCTAssertTrue(indexableNames.contains("fileA.txt"))
        XCTAssertTrue(indexableNames.contains("fileB.txt"))
    }

    func testCrawlSkipsNewlyExcludedDirectories() throws {
        // Excluded folders to test
        let excludedFolderNames = [
            // Python
            ".venv", "venv", "env", ".env", "site-packages", "__pycache__",
            // Web / Frontend
            "dist", "out", ".next", ".nuxt", ".turbo",
            // iOS / Mobile
            "Pods", "Carthage", "DerivedData",
            // Rust / Go / Java
            "target", "vendor", ".gradle",
            // IDEs
            ".idea", ".vscode"
        ]

        for folderName in excludedFolderNames {
            let folderURL = tempDir.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let dummyFile = folderURL.appendingPathComponent("\(folderName)_file.py")
            try "# dummy content".write(to: dummyFile, atomically: true, encoding: .utf8)
        }

        // Include a legitimate source directory and file
        let srcDir = tempDir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        let validFile = srcDir.appendingPathComponent("App.swift")
        try "struct App {}".write(to: validFile, atomically: true, encoding: .utf8)

        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)

        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })
        XCTAssertTrue(indexableNames.contains("App.swift"))

        for folderName in excludedFolderNames {
            XCTAssertFalse(
                indexableNames.contains("\(folderName)_file.py"),
                "Directory \(folderName) should be excluded from crawling"
            )
        }
    }

    func testCrawlEnforcesMaxDepth() throws {
        // Construct nesting: d0 / d1 / d2 / d3 / d4
        var currentDir = tempDir!
        for level in 0...4 {
            let fileAtLevel = currentDir.appendingPathComponent("file_level_\(level).txt")
            try "Level \(level)".write(to: fileAtLevel, atomically: true, encoding: .utf8)
            currentDir = currentDir.appendingPathComponent("d\(level)")
            try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        }

        // Crawl with maxDepth = 2
        let crawler = FileCrawler(maxDepth: 2)
        let result = crawler.crawl(rootURL: tempDir)

        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })
        XCTAssertTrue(indexableNames.contains("file_level_0.txt"))
        XCTAssertTrue(indexableNames.contains("file_level_1.txt"))
        XCTAssertTrue(indexableNames.contains("file_level_2.txt"))
        XCTAssertFalse(indexableNames.contains("file_level_3.txt"))
        XCTAssertFalse(indexableNames.contains("file_level_4.txt"))
    }
}
