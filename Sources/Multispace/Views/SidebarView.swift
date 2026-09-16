import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    let compact: Bool
    let canExpand: Bool
    @Binding var sidebarCollapsed: Bool
    @Binding var showingAddPlatform: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if compact {
                Button { if canExpand { sidebarCollapsed = false } } label: {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .help(canExpand ? "Expand sidebar" : "Multispace")
                .padding(.top, 31)
                .padding(.bottom, 26)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Multispace")
                            .font(.system(size: 20, weight: .bold))
                        Spacer()
                        Button { sidebarCollapsed = true } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .buttonStyle(.plain)
                        .help("Collapse sidebar")
                    }
                    Text("All your social apps, one place")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 31)
                .padding(.bottom, 24)
            }

            VStack(spacing: 4) {
                navButton("Home", symbol: "house.fill", destination: .home)
                navButton("Feed", symbol: "square.grid.2x2.fill", destination: .feed)
                navButton("Inbox", symbol: "bubble.left.and.bubble.right.fill", destination: .inbox)
            }
            .padding(.horizontal, compact ? 8 : 10)

            HStack {
                if !compact {
                    Text("SOCIAL APPS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Palette.muted)
                    Spacer()
                }
                Button { showingAddPlatform = true } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: compact ? .infinity : nil)
                }
                .buttonStyle(.plain)
                .help("Add social app")
            }
            .padding(.horizontal, compact ? 8 : 20)
            .padding(.top, 32)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.socialPlatforms) { platform in
                        platformButton(platform)
                    }
                }
                .padding(.horizontal, compact ? 8 : 10)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                if compact {
                    Button { store.destination = .settings } label: { Avatar(member: store.me, size: 34) }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .help("Settings & Profile")
                } else {
                    Avatar(member: store.me, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.me.name).font(.system(size: 12, weight: .semibold))
                        Text("@\(store.me.handle)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button { store.destination = .settings } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Palette.card.opacity(0.45))
        }
        .frame(width: compact ? 68 : (store.preferences.compactMode ? 190 : 224))
        .background(Palette.sidebar)
    }

    private func navButton(_ title: String, symbol: String, destination: AppDestination) -> some View {
        Button { store.destination = destination } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 19)
                if !compact {
                    Text(title).font(.system(size: 13, weight: store.destination == destination ? .semibold : .medium))
                    Spacer()
                }
            }
            .foregroundStyle(store.destination == destination ? .white : Palette.muted)
            .padding(.horizontal, compact ? 16 : 12)
            .frame(height: 35)
            .background(store.destination == destination ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func platformButton(_ platform: SocialPlatform) -> some View {
        let selected = store.destination == .platform(platform.id)
        let accounts = store.accounts(for: platform.id)
        let active = store.selectedAccount(for: platform.id)
        return VStack(spacing: 2) {
            Button { store.destination = .platform(platform.id) } label: {
                HStack(spacing: 12) {
                    PlatformLogo(platform: platform, size: 20)
                        .frame(width: 20)
                    if !compact {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(platform.name).font(.system(size: 13, weight: selected ? .semibold : .medium))
                            if let active {
                                Text(active.name).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 2)
                        let count = accounts.compactMap { store.platformActivity[$0.id]?.unreadCount }.reduce(0, +)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Palette.accent, in: Capsule())
                        }
                    }
                }
                .foregroundStyle(selected ? .white : Palette.muted)
                .padding(.horizontal, compact ? 16 : 12)
                .frame(height: compact ? 37 : (store.preferences.compactMode ? 39 : 47))
                .background(selected ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .help(active.map { "\(platform.name) · \($0.name)" } ?? platform.name)
            .contextMenu {
                if accounts.count > 1 {
                    ForEach(accounts) { account in
                        Button(account.name, systemImage: active?.id == account.id ? "checkmark.circle.fill" : "circle") {
                            store.selectAccount(account.id)
                        }
                    }
                    Divider()
                }
                Button("Edit…", systemImage: "pencil") { store.editingPlatform = platform }
                Button("Remove from sidebar", systemImage: "minus.circle", role: .destructive) {
                    store.removePlatform(platform.id)
                }
            }
            if !compact && accounts.count > 1 {
                ForEach(accounts) { account in
                    Button { store.selectAccount(account.id) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: active?.id == account.id ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(active?.id == account.id ? Palette.accent : Palette.muted)
                            Text(account.name).font(.system(size: 11, weight: active?.id == account.id ? .semibold : .regular))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let unread = store.platformActivity[account.id]?.unreadCount, unread > 0 {
                                Text("\(unread)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                        }
                        .padding(.leading, 31)
                        .padding(.trailing, 10)
                        .frame(height: 28)
                        .background(active?.id == account.id ? Palette.accent.opacity(0.10) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .help("Switch to \(platform.name) · \(account.name)")
                }
            }
        }
    }
}
