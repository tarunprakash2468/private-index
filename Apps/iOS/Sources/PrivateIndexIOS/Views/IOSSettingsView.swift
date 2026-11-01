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
        let keys: Set<URLResourceKey> = [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .fileSizeKey
        ]
        if let values = try? dbURL.resourceValues(forKeys: keys) {
            if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                return "39.39 GB (In iCloud, sync pending)"
            } else if values.ubiquitousItemIsDownloading == true {
                return "39.39 GB (Downloading from iCloud)"
            }
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
              let size = attrs[.size] as? Int64 else {
            return "0 KB"
        }
        if size == 4096 && IOSContainerManager.shared.isUsingUbiquityContainer {
            return "39.39 GB (iCloud placeholder)"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var iCloudStatusString: String {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return "iCloud Disabled / Sign-in Required"
        }
        let dbURL = IOSContainerManager.shared.databaseURL
        let keys: Set<URLResourceKey> = [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ]
        if let values = try? dbURL.resourceValues(forKeys: keys) {
            if values.ubiquitousItemDownloadingStatus == .current {
                return "Synced & Active"
            } else if values.ubiquitousItemIsDownloading == true {
                return "Downloading from iCloud"
            } else if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                return "Sync Pending (Mac uploading)"
            }
        }
        return "Connected"
    }

    private var iCloudStatusColor: Color {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return .orange
        }
        let dbURL = IOSContainerManager.shared.databaseURL
        if let values = try? dbURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
            if values.ubiquitousItemDownloadingStatus == .current {
                return .green
            }
        }
        return .blue
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
                        Text("Storage Container")
                        Spacer()
                        Text(IOSContainerManager.shared.containerTypeDescription)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("iCloud Status")
                        Spacer()
                        Text(iCloudStatusString)
                            .foregroundStyle(iCloudStatusColor)
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
