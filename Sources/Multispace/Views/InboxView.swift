import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var store: AppStore

    private var query: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionHeading(title: "Inbox", subtitle: "Message previews from your social accounts")
                    .padding(.top, 36)
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search messages or accounts", text: $store.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(12)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 11))
                if !hasMessages {
                    EmptyState(symbol: "bubble.left.and.bubble.right", title: "No message previews yet",
                               subtitle: "Sign in to an account. Messages appear here when its website exposes chat previews.")
                }
                ForEach(store.platformAccounts) { account in
                    if let platform = store.platform(account.platformID),
                       let snapshot = store.platformActivity[account.id] {
                        let matches = snapshot.messages.filter { message in
                            query.isEmpty || message.sender.localizedCaseInsensitiveContains(query)
                                || message.text.localizedCaseInsensitiveContains(query)
                                || account.name.localizedCaseInsensitiveContains(query)
                                || platform.name.localizedCaseInsensitiveContains(query)
                        }
                        if !matches.isEmpty {
                            HStack(spacing: 9) {
                                PlatformLogo(platform: platform, size: 22)
                                Text("\(platform.name) · \(account.name)")
                                    .font(.system(size: 13, weight: .semibold))
                                Spacer()
                                if let unread = snapshot.unreadCount, unread > 0 {
                                    Text("\(unread) indicated unread")
                                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                            }
                            ForEach(matches) { message in
                                Button { store.selectAccount(account.id) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "bubble.left.fill")
                                            .foregroundStyle(Palette.accent).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(message.sender).font(.system(size: 13, weight: .semibold))
                                            Text(message.text).font(.system(size: 12))
                                                .foregroundStyle(Palette.muted).lineLimit(2)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                                    }
                                    .padding(14)
                                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 38)
            .padding(.bottom, 30)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
    }

    private var hasMessages: Bool {
        store.platformAccounts.contains { account in
            guard let platform = store.platform(account.platformID),
                  let snapshot = store.platformActivity[account.id] else { return false }
            return snapshot.messages.contains { message in
                query.isEmpty || message.sender.localizedCaseInsensitiveContains(query)
                    || message.text.localizedCaseInsensitiveContains(query)
                    || account.name.localizedCaseInsensitiveContains(query)
                    || platform.name.localizedCaseInsensitiveContains(query)
            }
        }
    }
}
