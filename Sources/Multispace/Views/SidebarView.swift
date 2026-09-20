import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    let compact: Bool
    let canExpand: Bool
    @Binding var sidebarCollapsed: Bool
    @Binding var showingAddPlatform: Bool
    @State private var accountPendingDeletion: PlatformAccount?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if compact {
                VStack(spacing: 10) {
                    Button { if canExpand { sidebarCollapsed = false } } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .help(canExpand ? "Expand sidebar" : "Sidebar")

                    Button { showingAddPlatform = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .help("Add social app")
                }
                .padding(.top, 14)
                .padding(.bottom, 12)
            } else {
                HStack {
                    Text("SOCIAL APPS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Button { showingAddPlatform = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Add social app")

                    Button { sidebarCollapsed = true } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse sidebar")
                    .padding(.leading, 6)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }

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
                    Button { store.destination = .profile } label: {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(member: store.me, size: 34)
                            if store.userProfile.isSignedIn {
                                Circle()
                                    .fill(Palette.background)
                                    .frame(width: 12, height: 12)
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .help("Profile & Cloud Account")
                } else {
                    Button { store.destination = .profile } label: {
                        HStack(spacing: 9) {
                            ZStack(alignment: .bottomTrailing) {
                                Avatar(member: store.me, size: 34)
                                if store.userProfile.isSignedIn {
                                    Circle()
                                        .fill(Palette.background)
                                        .frame(width: 12, height: 12)
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 8, height: 8)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(store.userProfile.isSignedIn ? store.userProfile.displayName : store.me.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    if store.userProfile.isSignedIn {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Palette.accent)
                                    }
                                }
                                Text(store.userProfile.isSignedIn ? store.userProfile.email : "@\(store.me.handle)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Profile & Cloud Account")

                    Spacer()

                    Button { store.destination = .settings } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain)
                        .help("Settings")
                }
            }
            .padding(14)
            .background(Palette.card.opacity(0.45))
        }
        .frame(width: compact ? 68 : (store.preferences.compactMode ? 190 : 224))
        .background(Palette.sidebar)
        .confirmationDialog(
            "Delete account?",
            isPresented: Binding(
                get: { accountPendingDeletion != nil },
                set: { if !$0 { accountPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let account = accountPendingDeletion {
                Button("Delete \(account.name)", role: .destructive) {
                    store.removeAccount(account.id)
                    accountPendingDeletion = nil
                }
            }
            Button("Cancel", role: .cancel) { accountPendingDeletion = nil }
        } message: {
            if let account = accountPendingDeletion {
                Text("This removes \(account.name) from PINGGO and clears its separate website session. Your account on the social platform is not deleted.")
            }
        }
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
                    if destination == .inbox && store.totalUnreadCount > 0 {
                        Text("\(store.totalUnreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.accent, in: Capsule())
                    }
                } else if destination == .inbox && store.totalUnreadCount > 0 {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 6, height: 6)
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
                    let removableAccounts = accounts.filter { store.canRemoveAccount($0.id) }
                    if !removableAccounts.isEmpty {
                        Menu("Delete account…", systemImage: "trash") {
                            ForEach(removableAccounts) { account in
                                Button(account.name, role: .destructive) {
                                    accountPendingDeletion = account
                                }
                            }
                        }
                        Divider()
                    }
                }
                Button("Edit…", systemImage: "pencil") { store.editingPlatform = platform }
                Button("Remove from sidebar", systemImage: "minus.circle", role: .destructive) {
                    store.removePlatform(platform.id)
                }
            }
            if !compact && accounts.count > 1 {
                ForEach(accounts) { account in
                    HStack(spacing: 4) {
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
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Switch to \(platform.name) · \(account.name)")

                        if store.canRemoveAccount(account.id) {
                            Menu {
                                Button("Delete \(account.name)…", systemImage: "trash", role: .destructive) {
                                    accountPendingDeletion = account
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 22, height: 22)
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .frame(width: 22)
                            .help("Account options")
                        }
                    }
                    .padding(.leading, 31)
                    .padding(.trailing, 8)
                    .frame(height: 28)
                    .background(active?.id == account.id ? Palette.accent.opacity(0.10) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .contextMenu {
                        if store.canRemoveAccount(account.id) {
                            Button("Delete \(account.name)…", systemImage: "trash", role: .destructive) {
                                accountPendingDeletion = account
                            }
                        }
                    }
                }
            }
        }
    }
}
