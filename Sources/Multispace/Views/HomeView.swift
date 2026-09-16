import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    SectionHeading(title: "Your social accounts", subtitle: "Recent activity from your connected websites.")
                    Spacer()
                    Image(systemName: "sparkles").font(.system(size: 25)).foregroundStyle(Palette.accent)
                }
                .padding(.top, 36)
                VStack(alignment: .leading, spacing: 14) {
                    Text("YOUR SOCIAL APPS").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted)
                    ForEach(store.platformAccounts) { account in
                        if let platform = store.platform(account.platformID) {
                            Button { store.selectAccount(account.id) } label: {
                                HStack(spacing: 14) {
                                    PlatformLogo(platform: platform, size: 27)
                                        .frame(width: 42, height: 42)
                                        .background(spaceColor(platform.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(platform.name).font(.system(size: 14, weight: .semibold))
                                        Text(account.name)
                                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                        if let snapshot = store.platformActivity[account.id] {
                                            Text(snapshot.unreadCount.map { "Website unread indicator: \($0)" } ?? "Website checked")
                                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                        } else {
                                            Text("Open to check activity")
                                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                                        }
                                    }
                                    Spacer()
                                    if store.selectedAccount(for: platform.id)?.id == account.id {
                                        Text("ACTIVE")
                                            .font(.system(size: 9, weight: .bold))
                                            .tracking(0.8)
                                            .foregroundStyle(Palette.accent)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(Palette.accent.opacity(0.14), in: Capsule())
                                    }
                                    Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                                }
                                .padding(14)
                                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("RECENT ACTIVITY").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted)
                    if !hasActivity {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("No message previews yet")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Open a platform and sign in. Previews and website alerts appear here when its web portal makes them available.")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    ForEach(store.platformAccounts) { account in
                        if let platform = store.platform(account.platformID),
                           let snapshot = store.platformActivity[account.id] {
                            ForEach(snapshot.messages) { message in
                                activityRow(platform: platform, account: account, symbol: "bubble.left.fill", title: message.sender, detail: message.text)
                            }
                            if store.preferences.showWebsiteAlerts {
                                ForEach(snapshot.notifications, id: \.self) { notification in
                                    activityRow(platform: platform, account: account, symbol: "bell.fill", title: "Website alert", detail: notification)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, store.preferences.compactMode ? 24 : 38)
            .padding(.bottom, 36)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
    }

    private var hasActivity: Bool {
        store.platformAccounts.contains { account in
            guard let snapshot = store.platformActivity[account.id] else { return false }
            return !snapshot.messages.isEmpty || (store.preferences.showWebsiteAlerts && !snapshot.notifications.isEmpty)
        }
    }

    private func activityRow(platform: SocialPlatform, account: PlatformAccount, symbol: String, title: String, detail: String) -> some View {
        Button { store.selectAccount(account.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                PlatformLogo(platform: platform, size: 24).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: symbol).font(.system(size: 10))
                        Text("\(platform.name) · \(account.name)").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Palette.muted)
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
