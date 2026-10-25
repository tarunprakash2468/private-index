import Foundation
import CoreServices

// MARK: - DirectoryWatcher

/// Monitors a directory hierarchy for filesystem changes using macOS FSEvents.
///
/// Automatically debounces events to prevent re-indexing thrashing during rapid edits.
public final class DirectoryWatcher: @unchecked Sendable {

    public typealias ChangeHandler = @Sendable () -> Void

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.privateindex.directorywatcher", qos: .utility)
    private var debounceTimer: DispatchSourceTimer?
    private let debounceInterval: TimeInterval
    private let onChange: ChangeHandler

    public private(set) var watchedURL: URL?

    public init(debounceInterval: TimeInterval = 2.0, onChange: @escaping ChangeHandler) {
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    /// Starts monitoring `directoryURL` for changes.
    public func start(watching directoryURL: URL) {
        stop()
        self.watchedURL = directoryURL

        let pathsToWatch = [directoryURL.path] as CFArray

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
            kFSEventStreamCreateFlagNoDefer
        )

        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            watcher.handleFileSystemEvent()
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
    }

    /// Stops monitoring.
    public func stop() {
        if let eventStream = stream {
            FSEventStreamStop(eventStream)
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
            self.stream = nil
        }
        cancelDebounceTimer()
        self.watchedURL = nil
    }

    // MARK: - Debounce Handling

    private func handleFileSystemEvent() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.scheduleDebouncedNotification()
        }
    }

    private func scheduleDebouncedNotification() {
        cancelDebounceTimer()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + debounceInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.onChange()
        }
        timer.resume()
        self.debounceTimer = timer
    }

    private func cancelDebounceTimer() {
        debounceTimer?.cancel()
        debounceTimer = nil
    }
}
