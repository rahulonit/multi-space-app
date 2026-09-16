import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddPlatform = false
    @State private var sidebarCollapsed = false

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 820 || sidebarCollapsed
            if store.destination == .settings {
                SettingsView()
            } else {
                HStack(spacing: 0) {
                    SidebarView(
                        compact: compact,
                        canExpand: geometry.size.width >= 820,
                        sidebarCollapsed: $sidebarCollapsed,
                        showingAddPlatform: $showingAddPlatform
                    )
                    mainContent
                }
            }
        }
        .background(Palette.background)
        .preferredColorScheme(store.preferences.appearance == "Follow System" ? nil : (store.preferences.appearance == "Light" ? .light : .dark))
        .sheet(isPresented: $showingAddPlatform) { AddPlatformSheet() }
        .sheet(item: $store.editingPlatform) { platform in
            EditPlatformSheet(platform: platform)
        }
        .onAppear {
            guard store.preferences.launchWebsites else { return }
            Task { @MainActor in
                if store.preferences.launchDelay > 0 {
                    try? await Task.sleep(for: .seconds(store.preferences.launchDelay))
                }
                PortalSessionRegistry.shared.monitor(store.socialPlatforms, accounts: store.platformAccounts, store: store)
            }
        }
        .onChange(of: store.socialPlatforms) { _, platforms in
            if store.preferences.launchWebsites { PortalSessionRegistry.shared.monitor(platforms, accounts: store.platformAccounts, store: store) }
        }
        .onChange(of: store.platformAccounts) { _, accounts in
            if store.preferences.launchWebsites { PortalSessionRegistry.shared.monitor(store.socialPlatforms, accounts: accounts, store: store) }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            switch store.destination {
            case .home: HomeView()
            case .feed: FeedView()
            case .inbox: InboxView()
            case .platform(let id): PlatformPortalView(platformID: id)
            case .channel, .conversation, .profile, .settings: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
