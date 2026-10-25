import SwiftUI
import AppKit

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

    private var databaseSizeString: String {
        let dbURL = iCloudContainerManager.shared.databaseURL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
              let size = attrs[.size] as? Int64 else {
            return "0 KB"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    public var body: some View {
        Form {
            // MARK: - Folder Selection
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Monitored Folder")
                        .font(.headline)

                    Text("Private Index monitors this folder recursively and automatically indexes text and code documents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)

                        Text((appState.monitoredDirectoryURL.path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)

                        Spacer()

                        Button("Change Folder...") {
                            chooseFolder()
                        }
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // MARK: - Database & Indexing
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Index Status")
                        .font(.headline)

                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Indexed Files:").foregroundStyle(.secondary)
                            Text("\(appState.totalFilesIndexed)")
                        }
                        GridRow {
                            Text("Database Size:").foregroundStyle(.secondary)
                            Text(databaseSizeString)
                        }
                        GridRow {
                            Text("Database Location:").foregroundStyle(.secondary)
                            Text((iCloudContainerManager.shared.databaseURL.path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                        }
                        GridRow {
                            Text("Status:").foregroundStyle(.secondary)
                            Text(appState.indexStatusMessage)
                        }
                    }

                    if appState.isIndexing {
                        ProgressView(value: appState.indexProgress)
                            .progressViewStyle(.linear)
                    }

                    HStack(spacing: 12) {
                        Button("Re-index Now") {
                            Task {
                                await appState.startIndexing()
                            }
                        }
                        .disabled(appState.isIndexing)

                        Button("Rebuild Index From Scratch", role: .destructive) {
                            showingRebuildConfirmation = true
                        }
                        .disabled(appState.isIndexing)
                    }
                    .padding(.top, 4)
                }
            }

            // MARK: - Startup & Power
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Startup & Background")
                        .font(.headline)

                    Toggle("Launch at Login", isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.launchAtLogin = $0 }
                    ))

                    Text("Keep the menu bar companion running seamlessly on boot without needing the search window open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    Toggle("Prevent sleep while indexing", isOn: $appState.preventSleepDuringIndexing)

                    Text("Requests a power assertion (kIOPMAssertionTypePreventUserIdleSystemSleep) during active indexing passes so system sleep does not interrupt neural embedding.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Privacy & Architecture
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Privacy & Security")
                        .font(.headline)
                    Text("• Zero-Cloud: All embeddings and SQLite tables remain entirely on your Mac.")
                        .font(.caption)
                    Text("• Neural Engine Acceleration: Uses FP16 Core ML weights on the Apple Neural Engine.")
                        .font(.caption)
                    Text("• iCloud Loop Prevention: The database is strictly isolated from user documents.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 520)
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
            Text("This will purge the current vector index and re-scan your documents. This process runs in the background.")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Select Folder"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try iCloudContainerManager.shared.validateTargetFolder(url)
                appState.monitoredDirectoryURL = url
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }
}
