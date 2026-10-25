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

    private var databaseSizeString: String {
        let dbURL = IOSContainerManager.shared.databaseURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
              let size = attrs[.size] as? Int64 else {
            return "0 KB"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public var body: some View {
        NavigationStack {
            List {
                // Section: Database Info
                Section("Database & Storage") {
                    HStack {
                        Text("Database Size")
                        Spacer()
                        Text(databaseSizeString)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Vector Dimensions")
                        Spacer()
                        Text("384 (Cosine)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Ubiquity Isolation")
                        Spacer()
                        Text("Enforced")
                            .foregroundStyle(.green)
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

                    Button("Re-index Documents") {
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

                // Section: Privacy Info
                Section("Privacy & On-Device AI") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zero Cloud Architecture")
                            .font(.subheadline.bold())
                        Text("Private Index processes documents and queries entirely on your device using the Apple Neural Engine. Your data and search queries are never transmitted over the network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
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
