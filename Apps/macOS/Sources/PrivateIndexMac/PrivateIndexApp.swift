import SwiftUI
import AppKit

// MARK: - PrivateIndexApp

@main
struct PrivateIndexApp: App {

    @State private var appState = AppState.shared

    var body: some Scene {
        // Spotlight-style Search HUD Window
        WindowGroup(id: "search-hud") {
            SearchHUDView(appState: appState)
                .background(WindowAccessor())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Menu Bar Companion
        MenuBarExtra("Private Index", systemImage: "sparkle.magnifyingglass") {
            MenuBarView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        // Preferences Window
        Settings {
            SettingsView(appState: appState)
        }
    }
}

// MARK: - WindowAccessor

/// Makes the search window floating and transparent with rounded glass appearance.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.level = .floating
                window.hasShadow = false // Shadow handled by SwiftUI clipShape
                window.titlebarAppearsTransparent = true
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.isMovableByWindowBackground = true
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
