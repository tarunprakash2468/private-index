import SwiftUI
import QuickLook
import PrivateIndexEngine

// MARK: - IOSSearchView

@MainActor
public struct IOSSearchView: View {

    @Bindable var appState: IOSAppState

    public init(appState: IOSAppState) {
        self.appState = appState
    }

    public init() {
        self.appState = IOSAppState.shared
    }

    public var body: some View {
        NavigationStack {
            Group {
                if appState.isSearching && appState.searchResults.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Finding semantic matches...")
                            .foregroundStyle(.secondary)
                    }
                } else if appState.searchResults.isEmpty && !appState.query.isEmpty {
                    ContentUnavailableView(
                        "No Matches Found",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Try searching with different keywords or concepts.")
                    )
                } else if appState.searchResults.isEmpty {
                    ContentUnavailableView(
                        "Private Semantic Search",
                        systemImage: "sparkle.magnifyingglass",
                        description: Text("Search your indexed documents by meaning, entirely on-device.")
                    )
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search")
            .searchable(
                text: $appState.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search by meaning..."
            )
            .quickLookPreview($appState.selectedPreviewURL)
            .toolbar {
                if appState.isIndexing {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        List(appState.searchResults) { item in
            IOSResultCard(item: item) {
                let fileURL = URL(fileURLWithPath: item.filePath)
                appState.selectedPreviewURL = fileURL
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }
}

// MARK: - IOSResultCard

struct IOSResultCard: View {
    let item: SearchResultItem
    let onPreview: () -> Void

    private var fileName: String {
        URL(fileURLWithPath: item.filePath).lastPathComponent
    }

    private var scoreColor: Color {
        if item.score >= 0.85 { return .green }
        if item.score >= 0.70 { return .teal }
        if item.score >= 0.50 { return .blue }
        return .secondary
    }

    var body: some View {
        Button {
            onPreview()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(Color.accentColor)

                    Text(fileName)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    // Match Pill
                    Text("\(Int(item.score * 100))% match")
                        .font(.caption2.bold())
                        .foregroundStyle(scoreColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(scoreColor.opacity(0.12))
                        .clipShape(Capsule())
                }

                // Snippet
                Text(item.content)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onPreview()
            } label: {
                Label("Quick Look", systemImage: "eye")
            }

            ShareLink(item: URL(fileURLWithPath: item.filePath)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
