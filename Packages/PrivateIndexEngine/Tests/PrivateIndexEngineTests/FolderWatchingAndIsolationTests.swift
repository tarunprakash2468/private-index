import XCTest
#if os(macOS)
import CoreServices
#endif
@testable import PrivateIndexEngine

final class FolderWatchingAndIsolationTests: XCTestCase {

    private final class SafeBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T

        init(_ value: T) {
            self._value = value
        }

        var value: T {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _value
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _value = newValue
            }
        }
    }

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderWatchingTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - 1. FSEvent Debouncing & Path Accumulation

    func testDebouncingCoalescesRapidEvents() throws {
        let expectation = expectation(description: "Debounced callback should fire exactly once")
        let changeCount = SafeBox<Int>(0)
        let receivedPaths = SafeBox<[String]>([])

        let watcher = DirectoryWatcher(
            debounceInterval: 0.15,
            onPathsChanged: { paths in
                receivedPaths.value = paths
            },
            onChange: {
                changeCount.value += 1
                expectation.fulfill()
            }
        )

        watcher.start(watching: tempDir)

        // Rapidly fire 5 events within 50ms
        for i in 1...5 {
            watcher.handleFileSystemEvent(paths: ["/path/to/file\(i).txt"])
            usleep(5_000) // 5ms
        }

        // Before debounce expiration, callback should NOT have fired
        XCTAssertEqual(changeCount.value, 0, "Callback should not fire before debounce interval expires")

        // Wait for debounce timer to fire
        wait(for: [expectation], timeout: 1.5)

        XCTAssertEqual(changeCount.value, 1, "Callback should have fired exactly once after debouncing")
        XCTAssertTrue(receivedPaths.value.contains("/path/to/file1.txt"))
        XCTAssertTrue(receivedPaths.value.contains("/path/to/file5.txt"))

        watcher.stop()
    }

    // MARK: - 2. Debounce Cancellation on Stop

    func testDebounceCancellationOnStop() throws {
        let changeCount = SafeBox<Int>(0)

        let watcher = DirectoryWatcher(debounceInterval: 0.2) {
            changeCount.value += 1
        }

        watcher.start(watching: tempDir)
        XCTAssertTrue(watcher.isWatching)
        XCTAssertEqual(watcher.watchedURL, tempDir)

        // Trigger an event
        watcher.handleFileSystemEvent(paths: ["/path/file.txt"])

        // Immediately cancel/stop before the 0.2s debounce completes
        watcher.stop()
        XCTAssertFalse(watcher.isWatching)
        XCTAssertNil(watcher.watchedURL)

        // Sleep past debounce interval
        usleep(300_000) // 300ms

        XCTAssertEqual(changeCount.value, 0, "Callback must NOT be called after watcher is stopped")
    }

    // MARK: - 3. Batched FSEvent IDs and Wake/Rescan Flags

    func testBatchedEventIdsAndRescanFlags() throws {
        let watcher = DirectoryWatcher(debounceInterval: 0.1)

        watcher.start(watching: tempDir)
        usleep(20_000) // allow stream initialization

        #if os(macOS)
        let baseId = max(watcher.lastEventId, 2_000_000_000)
        let mustScanFlag = UInt32(kFSEventStreamEventFlagMustScanSubDirs)
        let eventIds: [UInt64] = [baseId + 5, baseId + 10, baseId + 20, baseId + 15]

        watcher.handleFileSystemEvent(
            paths: ["/dir/a", "/dir/b"],
            eventFlags: [0, mustScanFlag],
            eventIds: eventIds
        )

        // Let queue process
        usleep(30_000)

        XCTAssertEqual(watcher.lastEventId, baseId + 20, "Watcher should track highest FSEvent ID across batch")
        XCTAssertTrue(watcher.needsFullRescan, "Watcher should flag full rescan when MustScanSubDirs is set")
        #endif

        watcher.stop()
    }

    func testWatcherFlushTriggersPendingImmediately() throws {
        let didFire = SafeBox<Bool>(false)

        let watcher = DirectoryWatcher(debounceInterval: 10.0) {
            didFire.value = true
        }

        watcher.start(watching: tempDir)
        watcher.handleFileSystemEvent(paths: ["/dir/file.md"])

        // Flush without waiting 10 seconds
        watcher.flush()

        XCTAssertTrue(didFire.value, "Flush should immediately trigger pending changes")
        watcher.stop()
    }

    // MARK: - 4. Safe Handling of Dataless / Evicted iCloud Files

    func testNormalFilesAreNotConsideredDataless() throws {
        let testFile = tempDir.appendingPathComponent("local_document.txt")
        try "Content that is downloaded and resident on disk".write(
            to: testFile,
            atomically: true,
            encoding: .utf8
        )

        // A standard local file should not be reported as dataless
        XCTAssertFalse(FileCrawler.isDatalessICloudFile(at: testFile))
    }

    func testNonExistentFileIsNotDataless() throws {
        let missing = tempDir.appendingPathComponent("does_not_exist.txt")
        XCTAssertFalse(FileCrawler.isDatalessICloudFile(at: missing))
    }

    func testFileCrawlerResultCategorization() throws {
        let file1 = tempDir.appendingPathComponent("valid.md")
        let file2 = tempDir.appendingPathComponent("code.swift")
        let sqlite = tempDir.appendingPathComponent("index.sqlite")

        try "# Markdown".write(to: file1, atomically: true, encoding: .utf8)
        try "let x = 1".write(to: file2, atomically: true, encoding: .utf8)
        try "database".write(to: sqlite, atomically: true, encoding: .utf8)

        let crawler = FileCrawler()
        let result = crawler.crawl(rootURL: tempDir)

        let indexableNames = Set(result.indexableFiles.map { $0.lastPathComponent })
        XCTAssertTrue(indexableNames.contains("valid.md"))
        XCTAssertTrue(indexableNames.contains("code.swift"))
        XCTAssertFalse(indexableNames.contains("index.sqlite"), "SQLite files must be excluded")
    }

    // MARK: - 5. Isolation Validation & Loop Prevention

    func testValidateTargetFolderPermitsExternalDirectory() throws {
        let manager = iCloudContainerManager.shared
        let externalFolder = tempDir.appendingPathComponent("UserDocuments")
        try FileManager.default.createDirectory(at: externalFolder, withIntermediateDirectories: true)

        // Valid external directory should pass without throwing
        XCTAssertNoThrow(try manager.validateTargetFolder(externalFolder))
    }

    func testValidateTargetFolderRejectsContainerOrDatabaseDirectory() throws {
        let manager = iCloudContainerManager.shared

        // Direct database directory
        let dbDir = manager.databaseURL.deletingLastPathComponent()
        XCTAssertThrowsError(try manager.validateTargetFolder(dbDir)) { error in
            guard let isolationError = error as? iCloudContainerManager.IsolationError else {
                XCTFail("Expected IsolationError, got: \(error)")
                return
            }
            if case .databaseContainedWithinTargetFolder(let path) = isolationError {
                XCTAssertEqual(path, dbDir.path)
            } else {
                XCTFail("Wrong isolation error case")
            }
        }

        // Entire container directory
        let containerDir = manager.containerURL
        XCTAssertThrowsError(try manager.validateTargetFolder(containerDir))
    }

    // MARK: - 6. PowerAssertion Safe Operation

    func testPowerAssertionTakeAndRelease() throws {
        let assertion = PowerAssertion(name: "Unit Test Assertion")

        // Should be safe to take
        assertion.take()

        // Double take should be no-op / safe
        assertion.take()

        // Should be safe to release
        assertion.release()

        // Double release should be no-op / safe
        assertion.release()
    }
}
