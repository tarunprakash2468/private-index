import Foundation
import os
#if os(macOS)
import IOKit.pwr_mgt
#endif

// MARK: - PowerAssertion

/// Prevents system idle sleep during active neural embedding and indexing operations.
public final class PowerAssertion: Sendable {
    private let name: String

    private struct State: @unchecked Sendable {
        #if os(macOS)
        var assertionID: IOPMAssertionID = 0
        #endif
        var activity: (any NSObjectProtocol)?
        var isActive = false
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(name: String = "Private Index Active Indexing") {
        self.name = name
        self.state = OSAllocatedUnfairLock(initialState: State())
    }

    public func take() {
        state.withLock { s in
            guard !s.isActive else { return }

            #if os(macOS)
            let type = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
            let reason = name as CFString
            let result = IOPMAssertionCreateWithName(
                type,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &s.assertionID
            )
            if result == kIOReturnSuccess {
                s.isActive = true
            }
            #endif

            s.activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                reason: name
            )
            s.isActive = true
        }
    }

    public func release() {
        state.withLock { s in
            guard s.isActive else { return }

            #if os(macOS)
            if s.assertionID != 0 {
                IOPMAssertionRelease(s.assertionID)
                s.assertionID = 0
            }
            #endif

            if let act = s.activity {
                ProcessInfo.processInfo.endActivity(act)
                s.activity = nil
            }
            s.isActive = false
        }
    }

    deinit {
        release()
    }
}
