import SwiftUI

// MARK: - IOSSettingsView

@MainActor
public struct IOSSettingsView: View {

    @Bindable var appState: IOSAppState
    @State private var showingRebuildAlert = false

    public init(appState: IOSAppState) {
        self.appState = appState
    }

    public init() {
        self.appState = IOSAppState.shared
    }

    public var body: some View {
        NavigationStack {
            List {
                // Section: About
                Section("About") {
                    HStack {
                        Text("iCloud Status")
                        Spacer()
                        Text(appState.isiCloudActive ? "Active" : "Inactive")
                            .foregroundStyle(appState.isiCloudActive ? .green : .secondary)
                    }

                    HStack {
                        Text("Database Size")
                        Spacer()
                        Text(appState.formattedDatabaseSize)
                            .foregroundStyle(.secondary)
                    }
                }

                // Section: Actions
                Section("Actions") {
                    Button {
                        Task {
                            await appState.syncAndCheckDatabase()
                        }
                    } label: {
                        HStack {
                            Text("Sync & Check Database")
                            if appState.isSyncingDatabase {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(appState.isSyncingDatabase)

                    if let syncStatus = appState.syncStatusMessage {
                        Text(syncStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Re-index Sources") {
                        Task {
                            await appState.startIndexing()
                        }
                    }
                    .disabled(appState.isIndexing || appState.monitoredFolderURL == nil)

                    Button("Rebuild Index from Scratch", role: .destructive) {
                        showingRebuildAlert = true
                    }
                    .disabled(appState.isIndexing)
                }
            }
            .navigationTitle("Settings")
            .alert("Rebuild Index?", isPresented: $showingRebuildAlert) {
                Button("Rebuild", role: .destructive) {
                    Task {
                        await appState.rebuildIndex()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete the current vector database and re-scan your selected folder.")
            }
        }
    }
}
