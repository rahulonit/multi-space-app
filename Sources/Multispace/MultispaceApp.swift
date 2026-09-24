import SwiftUI

@main
struct PinggoApp: App {
    @StateObject private var store = AppStore()

    init() {
        if let iconURL = Bundle.module.url(forResource: "app-logo", withExtension: "png"),
           let image = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 620, minHeight: 520)
                .onOpenURL { url in
                    store.handleDeepLink(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Home") { store.destination = .home }
                    .keyboardShortcut("1", modifiers: .command)
                    .disabled(store.isAppLocked)
                Button("Browser") { store.destination = .browser }
                    .keyboardShortcut("2", modifiers: .command)
                    .disabled(store.isAppLocked)
                Button("Settings…") { store.destination = .settings }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(store.isAppLocked)
                Divider()
                Button("Command Palette…") { store.showingCommandPalette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(store.isAppLocked)
                Button("Toggle Split View") { store.toggleSplitView() }
                    .keyboardShortcut("\\", modifiers: .command)
                    .disabled(store.isAppLocked)
                Divider()
                Button("Lock PINGGO") { store.lockApp() }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(store.isAppLocked)
            }
        }

        MenuBarExtra {
            Button("Open PINGGO") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            Divider()
            Button("Private Browser") {
                store.destination = .browser
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Toggle Split View") {
                store.toggleSplitView()
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            ForEach(store.socialPlatforms) { platform in
                let unread = store.accounts(for: platform.id).compactMap { store.platformActivity[$0.id]?.unreadCount }.reduce(0, +)
                Button("\(platform.name)\(unread > 0 ? " (\(unread))" : "")") {
                    store.destination = .platform(platform.id)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            Divider()
            Button("Lock PINGGO") {
                store.lockApp()
            }
            Button("Quit PINGGO") {
                NSApp.terminate(nil)
            }
        } label: {
            let unread = store.platformActivity.values.compactMap(\.unreadCount).reduce(0, +)
            HStack(spacing: 3) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                if unread > 0 {
                    Text("\(unread)")
                }
            }
        }
    }
}
