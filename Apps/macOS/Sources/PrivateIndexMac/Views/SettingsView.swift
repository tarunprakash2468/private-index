import SwiftUI
import AppKit
import PrivateIndexEngine

// MARK: - SettingsView

@MainActor
public struct SettingsView: View {

    @Bindable var appState: AppState
    @State private var showingRebuildConfirmation = false

    public init(appState: AppState) {
        self.appState = appState
    }

    public init() {
        self.appState = AppState.shared
    }

    public var body: some View {
        Form {
            // MARK: - About
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

            // MARK: - Synced Sources
            Section("Synced Sources") {
                if appState.indexedSources.isEmpty {
                    Text("No sources indexed yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.indexedSources) { source in
                        HStack(spacing: 10) {
                            Image(systemName: source.iconSystemName.isEmpty ? "folder.fill" : source.iconSystemName)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 20)
                            Text(source.name)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(source.fileCount) files • \(source.formattedBytes)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // MARK: - Actions
            Section("Actions") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Status:").foregroundStyle(.secondary)
                        Text(appState.indexStatusMessage)
                    }
                    .font(.caption)

                    if appState.isIndexing {
                        ProgressView(value: appState.indexProgress)
                            .progressViewStyle(.linear)
                    }

                    HStack(spacing: 12) {
                        Button("Re-index Sources") {
                            Task {
                                await appState.startIndexing()
                            }
                        }
                        .disabled(appState.isIndexing)

                        Button("Rebuild Index from Scratch", role: .destructive) {
                            showingRebuildConfirmation = true
                        }
                        .disabled(appState.isIndexing)
                    }
                }
            }

            // MARK: - Startup & Power
            Section("Options") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { appState.launchAtLogin },
                    set: { appState.launchAtLogin = $0 }
                ))

                Toggle("Prevent sleep while indexing", isOn: $appState.preventSleepDuringIndexing)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
        .confirmationDialog(
            "Rebuild Index?",
            isPresented: $showingRebuildConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rebuild", role: .destructive) {
                Task {
                    await appState.rebuildIndex()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will purge the current vector index and re-scan your sources. This process runs in the background.")
        }
    }
}
