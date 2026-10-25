import SwiftUI
import AppKit
import PrivateIndexEngine

// MARK: - SearchHUDView

/// Spotlight-style floating HUD interface for zero-cloud semantic search.
@MainActor
public struct SearchHUDView: View {

    @Bindable var appState: AppState
    @FocusState private var isFieldFocused: Bool

    public init(appState: AppState) {
        self.appState = appState
    }

    public init() {
        self.appState = AppState.shared
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Search Bar
            searchHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            Divider()
                .opacity(0.3)

            // Results List / Empty States
            if appState.isSearching && appState.searchResults.isEmpty {
                searchingStateView
            } else if appState.searchResults.isEmpty && !appState.query.isEmpty {
                noResultsStateView
            } else if appState.searchResults.isEmpty {
                welcomeStateView
            } else {
                resultsListView
            }

            // Bottom Status Bar
            Divider()
                .opacity(0.3)
            bottomStatusBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(width: 680, height: 460)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 15)
        .onAppear {
            isFieldFocused = true
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentColor)

            TextField("Search your iCloud documents semantically...", text: $appState.query)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular, design: .default))
                .focused($isFieldFocused)

            if !appState.query.isEmpty {
                Button {
                    appState.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if appState.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Results List

    private var resultsListView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(appState.searchResults) { item in
                    SearchResultRow(
                        item: item,
                        isSelected: appState.selectedResultID == item.id,
                        onOpen: { appState.openFile(at: item.filePath) },
                        onReveal: { appState.revealInFinder(at: item.filePath) }
                    )
                    .onTapGesture {
                        appState.selectedResultID = item.id
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    // MARK: - States

    private var searchingStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text("Computing semantic embeddings...")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var noResultsStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No semantic matches found")
                .font(.headline)
            Text("Try phrasing your query differently or index more folders.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var welcomeStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text("Private Index")
                .font(.title2.bold())
            Text("Type anything to search files by meaning, entirely on-device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Bottom Bar

    private var bottomStatusBar: some View {
        HStack {
            if appState.isIndexing {
                HStack(spacing: 6) {
                    ProgressView(value: appState.indexProgress)
                        .frame(width: 60)
                        .controlSize(.small)
                    Text(appState.indexStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("\(appState.totalFilesIndexed) files indexed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Text("↵ Open")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("⌘↵ Reveal in Finder")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - SearchResultRow

struct SearchResultRow: View {
    let item: SearchResultItem
    let isSelected: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void

    @State private var isHovered = false

    private var fileName: String {
        URL(fileURLWithPath: item.filePath).lastPathComponent
    }

    private var directoryPath: String {
        let parent = URL(fileURLWithPath: item.filePath).deletingLastPathComponent().path
        return (parent as NSString).abbreviatingWithTildeInPath
    }

    private var scoreColor: Color {
        if item.score >= 0.85 { return .green }
        if item.score >= 0.70 { return .teal }
        if item.score >= 0.50 { return .blue }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.filePath))
                    .resizable()
                    .frame(width: 18, height: 18)

                Text(fileName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(directoryPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // Similarity percentage pill
                Text("\(Int(item.score * 100))% match")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(scoreColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(scoreColor.opacity(0.12))
                    .clipShape(Capsule())

                // Action buttons on hover
                if isHovered || isSelected {
                    HStack(spacing: 4) {
                        Button {
                            onReveal()
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")

                        Button {
                            onOpen()
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .help("Open File")
                    }
                }
            }

            // Snippet
            Text(item.content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.leading, 26)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.06) : Color.clear))
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
