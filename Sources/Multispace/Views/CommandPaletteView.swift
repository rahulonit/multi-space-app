import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String?
        let category: String
        let symbol: String?
        let platform: SocialPlatform?
        let badge: String?
        let action: () -> Void
    }

    private var allItems: [Item] {
        var list: [Item] = []

        // Navigation
        list.append(Item(id: "nav-home", title: "Home", subtitle: "Overview & recent activity", category: "Navigation", symbol: "house.fill", platform: nil, badge: "⌘1") {
            store.destination = .home
        })
        list.append(Item(id: "nav-inbox", title: "Inbox", subtitle: "Cross-platform message previews", category: "Navigation", symbol: "bubble.left.and.bubble.right.fill", platform: nil, badge: "⌘2") {
            store.destination = .inbox
        })
        list.append(Item(id: "nav-settings", title: "Settings", subtitle: "Preferences, appearance & accounts", category: "Navigation", symbol: "gearshape.fill", platform: nil, badge: "⌘,") {
            store.destination = .settings
        })

        // Social Platforms
        for platform in store.socialPlatforms {
            let unread = store.accounts(for: platform.id).compactMap { store.platformActivity[$0.id]?.unreadCount }.reduce(0, +)
            let badgeText = unread > 0 ? "\(unread) unread" : nil
            list.append(Item(
                id: "platform-\(platform.id)",
                title: platform.name,
                subtitle: platform.resolvedWebsiteURL?.host ?? "Social App",
                category: "Social Apps",
                symbol: nil,
                platform: platform,
                badge: badgeText
            ) {
                store.destination = .platform(platform.id)
            })
        }

        // Accounts
        for account in store.platformAccounts {
            if let platform = store.platform(account.platformID) {
                let unread = store.platformActivity[account.id]?.unreadCount
                let badgeText = (unread ?? 0) > 0 ? "\(unread!)" : nil
                list.append(Item(
                    id: "account-\(account.id.uuidString)",
                    title: "\(platform.name) · \(account.name)",
                    subtitle: "Switch to account",
                    category: "Accounts",
                    symbol: "person.crop.circle",
                    platform: platform,
                    badge: badgeText
                ) {
                    store.selectAccount(account.id)
                })
            }
        }

        // Actions
        list.append(Item(
            id: "act-split",
            title: store.isSplitView ? "Exit Split View" : "Toggle Side-by-Side Split View",
            subtitle: "View two platforms side-by-side",
            category: "Actions",
            symbol: "rectangle.split.2x1",
            platform: nil,
            badge: "⌘\\"
        ) {
            store.toggleSplitView()
        })
        list.append(Item(
            id: "act-add",
            title: "Add Social App",
            subtitle: "Browse suggested platforms or connect custom website",
            category: "Actions",
            symbol: "plus.circle.fill",
            platform: nil,
            badge: nil
        ) {
            // Trigger add sheet from store or notification
            // We can post a notification or route
            NotificationCenter.default.post(name: Notification.Name("ShowAddPlatformSheet"), object: nil)
        })

        // Recent Messages
        for account in store.platformAccounts {
            if let platform = store.platform(account.platformID),
               let snapshot = store.platformActivity[account.id] {
                for message in snapshot.messages.prefix(3) {
                    list.append(Item(
                        id: "msg-\(message.id)",
                        title: "\(message.sender) (\(platform.name))",
                        subtitle: message.text,
                        category: "Recent Messages",
                        symbol: "bubble.left.fill",
                        platform: platform,
                        badge: nil
                    ) {
                        store.selectAccount(account.id)
                    })
                }
            }
        }

        return list
    }

    private var filteredItems: [Item] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return allItems }
        return allItems.filter { item in
            item.title.localizedCaseInsensitiveContains(clean) ||
            (item.subtitle?.localizedCaseInsensitiveContains(clean) ?? false) ||
            item.category.localizedCaseInsensitiveContains(clean)
        }
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { store.showingCommandPalette = false }

            // Dialog Window
            VStack(spacing: 0) {
                // Search Header
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    TextField("Type a platform, account, action, or message…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($isSearchFocused)
                        .onSubmit { executeSelected() }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("ESC")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 5))
                }
                .padding(16)
                .background(Palette.panel)

                Divider()

                // Results list
                ScrollViewReader { proxy in
                    ScrollView {
                        if filteredItems.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Palette.muted)
                                Text("No matching results")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Try searching for a platform, account name, or action.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(40)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                    resultRow(item: item, isSelected: index == selectedIndex)
                                        .id(index)
                                        .onTapGesture {
                                            item.action()
                                            store.showingCommandPalette = false
                                        }
                                }
                            }
                            .padding(8)
                        }
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
                .frame(maxHeight: 380)

                Divider()

                // Footer tips
                HStack(spacing: 16) {
                    Text("↑↓ to navigate")
                    Text("↵ to select")
                    Text("esc to dismiss")
                    Spacer()
                    Text("PINGGO Spotlight")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.sidebar)
            }
            .frame(width: 580)
            .background(Palette.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Palette.panel.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        }
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.downArrow) {
            if !filteredItems.isEmpty {
                selectedIndex = min(selectedIndex + 1, filteredItems.count - 1)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if !filteredItems.isEmpty {
                selectedIndex = max(selectedIndex - 1, 0)
            }
            return .handled
        }
        .onKeyPress(.escape) {
            store.showingCommandPalette = false
            return .handled
        }
    }

    private func executeSelected() {
        guard !filteredItems.isEmpty, selectedIndex < filteredItems.count else { return }
        filteredItems[selectedIndex].action()
        store.showingCommandPalette = false
    }

    private func resultRow(item: Item, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            if let platform = item.platform {
                PlatformLogo(platform: platform, size: 20)
                    .frame(width: 24, height: 24)
            } else if let symbol = item.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(item.category)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.panel, in: Capsule())

            if let badge = item.badge {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.accent.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Palette.accent.opacity(0.24) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}
