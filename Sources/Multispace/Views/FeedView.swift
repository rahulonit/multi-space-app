import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var store: AppStore

    private var feedAccounts: [PlatformAccount] {
        store.platformAccounts.filter { account in
            ["instagram", "facebook", "x", "linkedin", "tiktok"].contains(account.platformID)
        }
    }

    private var currentAccount: PlatformAccount? {
        feedAccounts.first { $0.id == store.selectedFeedAccountID } ?? feedAccounts.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                SectionHeading(title: "Feeds", subtitle: "Browse posts from your social accounts")
                Spacer()
                if !feedAccounts.isEmpty {
                    Menu {
                        ForEach(feedAccounts) { account in
                            if let platform = store.platform(account.platformID) {
                                Button("\(platform.name) · \(account.name)") {
                                    store.selectedFeedAccountID = account.id
                                    store.selectAccount(account.id, navigate: false)
                                }
                            }
                        }
                    } label: {
                        Label("Choose account", systemImage: "chevron.down")
                    }
                }
            }
            .padding(20)
            .background(Palette.panel)
            if let account = currentAccount,
               let platform = store.platform(account.platformID) {
                PlatformPortalView(platformID: platform.id)
                    .id(account.id)
                    .onAppear { store.selectAccount(account.id, navigate: false) }
            } else {
                EmptyState(symbol: "square.grid.2x2", title: "No feeds yet",
                           subtitle: "Add Instagram, Facebook, X, LinkedIn, or TikTok to browse its feed here.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
