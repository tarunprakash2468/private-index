import SwiftUI
import UniformTypeIdentifiers
import PrivateIndexEngine

// MARK: - IOSSourcesView

@MainActor
public struct IOSSourcesView: View {

    @Bindable var appState: IOSAppState
    @State private var showingFolderPicker = false

    public init(appState: IOSAppState) {
        self.appState = appState
    }

    public init() {
        self.appState = IOSAppState.shared
    }

    public var body: some View {
        NavigationStack {
            List {
                // Section: Synced Sources
                Section("Synced Sources (\(appState.indexedSources.count))") {
                    if appState.indexedSources.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No sources synced yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Allow your Mac to finish syncing via iCloud, or tap Add Source below to index a folder on this iPhone.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(appState.indexedSources) { source in
                            NavigationLink {
                                SourceDetailView(source: source, appState: appState)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: source.iconSystemName)
                                        .font(.title3)
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.name)
                                            .font(.headline)

                                        Text("\(source.fileCount) files • \(source.formattedBytes)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                // Section: Add Local Source
                Section("Add Source") {
                    if let folder = appState.monitoredFolderURL {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "folder.badge.gearshape")
                                    .foregroundStyle(Color.accentColor)
                                Text(folder.lastPathComponent)
                                    .font(.subheadline.bold())
                            }
                            Text(folder.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label(
                            appState.monitoredFolderURL == nil ? "Add Folder from Files" : "Change Monitored Folder",
                            systemImage: "folder.badge.plus"
                        )
                    }
                }

                // Section: Status
                Section("Status") {
                    HStack {
                        Text("Indexing Status")
                        Spacer()
                        Text(appState.indexStatusMessage)
                            .foregroundStyle(.secondary)
                    }

                    if appState.isIndexing {
                        ProgressView(value: appState.indexProgress)
                    }

                    HStack {
                        Text("Total Indexed Files")
                        Spacer()
                        Text("\(appState.indexedFiles.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Sources")
            .refreshable {
                await appState.startIndexing()
            }
            .fileImporter(
                isPresented: $showingFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let first = urls.first {
                        appState.setMonitoredFolder(first)
                    }
                case .failure(let error):
                    appState.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - SourceDetailView

@MainActor
public struct SourceDetailView: View {
    let source: VectorStore.IndexedSource
    let appState: IOSAppState

    private var files: [VectorStore.FileRecord] {
        appState.files(for: source.id)
    }

    public var body: some View {
        List {
            Section("Location Info") {
                LabeledContent("Source", value: source.name)
                LabeledContent("Path", value: (source.rootPath as NSString).abbreviatingWithTildeInPath)
                LabeledContent("Files", value: "\(source.fileCount)")
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: source.totalBytes, countStyle: .file))
            }

            Section("Files (\(files.count))") {
                ForEach(files, id: \.id) { file in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                                .font(.subheadline)
                                .lineLimit(1)

                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle(source.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
