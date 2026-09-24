import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddPlatform = false
    @State private var sidebarCollapsed = false

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 820 || sidebarCollapsed
            VStack(spacing: 0) {
                // Standardized 64px Global Header
                GlobalHeaderView(windowWidth: geometry.size.width)
                    .frame(height: 64)

                Divider()
                    .background(Palette.border)

                // Main body area
                if store.destination == .settings || store.destination == .profile {
                    SettingsView(initialPage: store.destination == .profile ? .profile : .general)
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

                // Mobile Bottom Nav (< 768px)
                if geometry.size.width < 768 {
                    Divider()
                        .background(Palette.border)
                    MobileBottomNavView()
                        .frame(height: 52)
                }
            }
        }
        .background(Palette.background)
        .preferredColorScheme(store.preferences.appearance == "Follow System" ? nil : (store.preferences.appearance == "Light" ? .light : .dark))
        .sheet(isPresented: $showingAddPlatform) { AddPlatformSheet() }
        .sheet(item: $store.editingPlatform) { platform in
            EditPlatformSheet(platform: platform)
        }
        .overlay {
            if store.showingCommandPalette {
                CommandPaletteView()
            }
        }
        .overlay {
            if store.isAppLocked {
                LockScreenView()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThickMaterial, in: Capsule())
                .overlay(Capsule().stroke(Palette.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .padding(.bottom, 24)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.toastMessage)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowAddPlatformSheet"))) { _ in
            showingAddPlatform = true
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
        .background {
            BackgroundPortalHost(store: store)
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if store.isSplitView {
                SplitPortalView()
            } else {
                switch store.destination {
                case .home: HomeView()
                case .browser: BrowserView()
                case .platform(let id): PlatformPortalView(platformID: id)
                case .channel, .conversation, .profile, .settings:
                    SettingsView(initialPage: store.destination == .profile ? .profile : .general)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

struct BackgroundPortalHost: NSViewRepresentable {
    @ObservedObject var store: AppStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        PortalSessionRegistry.shared.attachBackgroundWebViews(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        PortalSessionRegistry.shared.attachBackgroundWebViews(to: nsView)
    }
}
