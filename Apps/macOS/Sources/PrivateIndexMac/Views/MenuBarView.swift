import SwiftUI
import AppKit

// MARK: - MenuBarView

@MainActor
public struct MenuBarView: View {

    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    public init(appState: AppState) {
        self.appState = appState
    }

    public init() {
        self.appState = AppState.shared
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(Color.accentColor)
                Text("Private Index")
                    .font(.headline)
                Spacer()
                if appState.isIndexing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(appState.indexStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Quick Actions
            Button {
                openWindow(id: "search-hud")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Search", systemImage: "magnifyingglass")
            }
            .keyboardShortcut(" ", modifiers: [.command, .shift])

            Button {
                Task {
                    await appState.startIndexing()
                }
            } label: {
                Label("Index Now", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isIndexing)

            Divider()

            SettingsLink {
                Label("Settings...", systemImage: "gearshape")
            }

            Button("Quit Private Index") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 240)
    }
}
