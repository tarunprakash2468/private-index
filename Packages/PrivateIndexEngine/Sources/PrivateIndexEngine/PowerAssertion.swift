import Foundation
#if os(macOS)
import IOKit.pwr_mgt
#endif

// MARK: - PowerAssertion

/// Prevents system idle sleep during active neural embedding and indexing operations.
public final class PowerAssertion: @unchecked Sendable {
    private let name: String
    #if os(macOS)
    private var assertionID: IOPMAssertionID = 0
    #endif
    private var activity: (any NSObjectProtocol)?
    private var isActive = false
    private let lock = NSLock()

    public init(name: String = "Private Index Active Indexing") {
        self.name = name
    }

    public func take() {
        lock.lock()
        defer { lock.unlock() }
        guard !isActive else { return }

        #if os(macOS)
        let type = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        let reason = name as CFString
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isActive = true
        }
        #endif

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: name
        )
        isActive = true
    }

    public func release() {
        lock.lock()
        defer { lock.unlock() }
        guard isActive else { return }

        #if os(macOS)
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        #endif

        if let act = activity {
            ProcessInfo.processInfo.endActivity(act)
            activity = nil
        }
        isActive = false
    }

    deinit {
        release()
    }
}
