import SwiftUI

// MARK: - MainTabView

@MainActor
public struct MainTabView: View {

    @State private var appState = IOSAppState.shared

    public init() {}

    public var body: some View {
        TabView {
            IOSSearchView(appState: appState)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            IOSSourcesView(appState: appState)
                .tabItem {
                    Label("Sources", systemImage: "folder.fill")
                }

            IOSSettingsView(appState: appState)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}
