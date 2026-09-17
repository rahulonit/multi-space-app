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
                Button("Inbox") { store.destination = .inbox }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Settings…") { store.destination = .settings }
                    .keyboardShortcut(",", modifiers: .command)
                Divider()
                Button("Command Palette…") { store.showingCommandPalette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Toggle Split View") { store.toggleSplitView() }
                    .keyboardShortcut("\\", modifiers: .command)
                Divider()
                Button("Lock PINGGO") { store.lockApp() }
                    .keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}
