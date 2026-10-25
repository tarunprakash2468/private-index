import SwiftUI
import UniformTypeIdentifiers
import PrivateIndexEngine

// MARK: - IOSDocumentsView

@MainActor
public struct IOSDocumentsView: View {

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
                // Section: Monitored Folder
                Section("Monitored Folder") {
                    if let folder = appState.monitoredFolderURL {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Color.accentColor)
                                Text(folder.lastPathComponent)
                                    .font(.headline)
                            }
                            Text(folder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("No folder selected yet")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label(
                            appState.monitoredFolderURL == nil ? "Select Folder to Index" : "Change Folder",
                            systemImage: "folder.badge.plus"
                        )
                    }
                }

                // Section: Indexing Status
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
                        Text("Indexed Documents")
                        Spacer()
                        Text("\(appState.indexedFiles.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                // Section: Indexed Files
                if !appState.indexedFiles.isEmpty {
                    Section("Indexed Files (\(appState.indexedFiles.count))") {
                        ForEach(appState.indexedFiles, id: \.id) { file in
                            HStack {
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
            }
            .navigationTitle("Documents")
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
