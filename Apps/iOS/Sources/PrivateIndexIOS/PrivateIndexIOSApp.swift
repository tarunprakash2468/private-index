import SwiftUI
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

// MARK: - Constants

public let backgroundIndexingTaskId = "com.app.privateindex.indexing"

// MARK: - PrivateIndexIOSApp

@main
public struct PrivateIndexIOSApp: App {

    public init() {
        #if os(iOS)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundIndexingTaskId,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            IOSAppState.shared.handleBackgroundIndexing(task: processingTask)
        }
        #endif
    }

    public var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
