import SwiftUI

@main
struct MultispaceApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Home") { store.destination = .home }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Feed") { store.destination = .feed }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Inbox") { store.destination = .inbox }
                    .keyboardShortcut("3", modifiers: .command)
            }
        }
    }
}
