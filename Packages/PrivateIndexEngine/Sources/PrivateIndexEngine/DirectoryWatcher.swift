import Foundation
#if os(macOS)
import CoreServices
#if canImport(AppKit)
import AppKit
#endif
#endif

// MARK: - DirectoryWatcher

/// Monitors a directory hierarchy for filesystem changes using macOS FSEvents.
///
/// Features:
/// - 2.0s automatic event debouncing to prevent re-indexing thrashing during rapid edits
/// - Batched FSEvent ID tracking and rescan flag detection
/// - Automatic recovery from system sleep and clamshell mode via `NSWorkspace.didWakeNotification`
/// - Safe cleanup and stream invalidation on cancellation / shutdown
public final class DirectoryWatcher: @unchecked Sendable {

    public typealias ChangeHandler = @Sendable () -> Void
    public typealias DetailedChangeHandler = @Sendable ([String]) -> Void

    #if os(macOS)
    private var stream: FSEventStreamRef?
    private var wakeObserver: (any NSObjectProtocol)?
    #endif

    private let queue = DispatchQueue(label: "com.privateindex.directorywatcher", qos: .utility)
    private var debounceTimer: DispatchSourceTimer?
    private let debounceInterval: TimeInterval
    private let onChange: ChangeHandler?
    private let onPathsChanged: DetailedChangeHandler?

    public private(set) var watchedURLs: [URL] = []
    public var watchedURL: URL? { watchedURLs.first }
    public private(set) var isWatching: Bool = false
    public private(set) var lastEventId: UInt64 = 0
    public var needsFullRescan: Bool = false

    private var accumulatedPaths = Set<String>()
    private let lock = NSLock()

    public init(
        debounceInterval: TimeInterval = 2.0,
        onPathsChanged: DetailedChangeHandler? = nil,
        onChange: ChangeHandler? = nil
    ) {
        self.debounceInterval = debounceInterval
        self.onPathsChanged = onPathsChanged
        self.onChange = onChange
    }

    public convenience init(
        debounceInterval: TimeInterval = 2.0,
        onChange: @escaping ChangeHandler
    ) {
        self.init(debounceInterval: debounceInterval, onPathsChanged: nil, onChange: onChange)
    }

    deinit {
        stop()
    }

    /// Starts monitoring multiple directories for changes in a unified FSEvents stream.
    public func start(watching directoryURLs: [URL]) {
        stop()
        guard !directoryURLs.isEmpty else { return }
        self.watchedURLs = directoryURLs
        self.isWatching = true

        #if os(macOS)
        let pathsToWatch = directoryURLs.map { $0.path } as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

            var paths: [String] = []
            if let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] {
                paths = cfPaths
            }

            var flagsArray: [UInt32] = []
            var idsArray: [UInt64] = []
            for i in 0..<numEvents {
                flagsArray.append(eventFlags[i])
                idsArray.append(eventIds[i])
            }

            watcher.handleFileSystemEvent(paths: paths, eventFlags: flagsArray, eventIds: idsArray)
        }

        guard let eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency
            flags
        ) else {
            return
        }

        self.stream = eventStream
        FSEventStreamSetDispatchQueue(eventStream, queue)
        FSEventStreamStart(eventStream)

        #if canImport(AppKit)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleSystemWake()
        }
        #endif
        #endif
    }

    /// Convenience method to start monitoring a single directory.
    public func start(watching directoryURL: URL) {
        start(watching: [directoryURL])
    }

    /// Stops monitoring and cancels all active timers.
    public func stop() {
        lock.lock()
        isWatching = false
        accumulatedPaths.removeAll()
        self.watchedURLs.removeAll()
        lock.unlock()

        queue.sync { [weak self] in
            self?.cancelDebounceTimer()
        }

        #if os(macOS)
        if let eventStream = stream {
            FSEventStreamStop(eventStream)
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
            self.stream = nil
        }
        #if canImport(AppKit)
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.wakeObserver = nil
        }
        #endif
        #endif
    }

    /// Flushes any pending changes immediately.
    public func flush() {
        queue.sync { [weak self] in
            guard let self = self else { return }
            self.cancelDebounceTimer()
            self.fireChangeNotification()
        }
    }

    // MARK: - Event Handling

    public func handleFileSystemEvent(
        paths: [String] = [],
        eventFlags: [UInt32] = [],
        eventIds: [UInt64] = []
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.lock.lock()
            guard self.isWatching else {
                self.lock.unlock()
                return
            }

            for path in paths {
                self.accumulatedPaths.insert(path)
            }
            if let maxId = eventIds.max(), maxId > self.lastEventId {
                self.lastEventId = maxId
            }
            #if os(macOS)
            for flag in eventFlags {
                let mustScan = (flag & UInt32(kFSEventStreamEventFlagMustScanSubDirs)) != 0
                let userDropped = (flag & UInt32(kFSEventStreamEventFlagUserDropped)) != 0
                let kernelDropped = (flag & UInt32(kFSEventStreamEventFlagKernelDropped)) != 0
                if mustScan || userDropped || kernelDropped {
                    self.needsFullRescan = true
                }
            }
            #endif
            self.lock.unlock()

            self.scheduleDebouncedNotification()
        }
    }

    #if os(macOS)
    @objc private func handleSystemWake() {
        queue.async { [weak self] in
            guard let self = self, let stream = self.stream else { return }
            // Flush any batched FSEvent IDs that accumulated during sleep/wake
            FSEventStreamFlushAsync(stream)
            self.lock.lock()
            self.needsFullRescan = true
            self.lock.unlock()
            self.scheduleDebouncedNotification()
        }
    }
    #endif

    // MARK: - Debounce Handling

    private func scheduleDebouncedNotification() {
        cancelDebounceTimer()
        lock.lock()
        guard isWatching else {
            lock.unlock()
            return
        }
        lock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + debounceInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.fireChangeNotification()
        }
        timer.resume()
        self.debounceTimer = timer
    }

    private func fireChangeNotification() {
        lock.lock()
        guard isWatching else {
            lock.unlock()
            return
        }
        let paths = Array(accumulatedPaths)
        accumulatedPaths.removeAll()
        lock.unlock()

        onPathsChanged?(paths)
        onChange?()
    }

    private func cancelDebounceTimer() {
        debounceTimer?.cancel()
        debounceTimer = nil
    }
}
