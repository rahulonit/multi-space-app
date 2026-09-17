import SwiftUI
import AppKit

private enum InboxViewMode: String, CaseIterable {
    case all = "All Messages"
    case byPlatform = "By Platform"
    case alerts = "Alerts & Notices"
}

struct UnifiedMessageItem: Identifiable {
    var id: String { "\(accountID)-\(message.id)" }
    let accountID: UUID
    let accountName: String
    let platform: SocialPlatform
    let message: PlatformMessagePreview
    let snapshotDate: Date
}

struct UnifiedAlertItem: Identifiable {
    var id: String { "\(account.id)-\(alertText)" }
    let account: PlatformAccount
    let platform: SocialPlatform
    let alertText: String
}

struct InboxView: View {
    @EnvironmentObject private var store: AppStore
    @State private var viewMode: InboxViewMode = .all
    @State private var selectedPlatformID: String? = nil
    @State private var unreadOnly: Bool = false
    @State private var isRefreshing: Bool = false
    @State private var hoveredCardID: String? = nil

    private var query: String {
        store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Aggregated Messages
    private var allUnifiedMessages: [UnifiedMessageItem] {
        var items: [UnifiedMessageItem] = []
        for account in store.platformAccounts {
            guard let platform = store.platform(account.platformID) else { continue }
            let snapshot = store.platformActivity[account.id]
            if let snapshot, !snapshot.messages.isEmpty {
                for msg in snapshot.messages {
                    items.append(UnifiedMessageItem(
                        accountID: account.id,
                        accountName: account.name,
                        platform: platform,
                        message: msg,
                        snapshotDate: snapshot.updatedAt
                    ))
                }
            } else {
                items.append(UnifiedMessageItem(
                    accountID: account.id,
                    accountName: account.name,
                    platform: platform,
                    message: PlatformMessagePreview(
                        id: "\(account.id)-starter",
                        sender: "\(platform.name) Updates",
                        text: "Connected to \(platform.name). Open portal to sign in and stream your live chats into PINGGO.",
                        time: "Ready",
                        linkURL: platform.inboxURL?.absoluteString
                    ),
                    snapshotDate: snapshot?.updatedAt ?? .now
                ))
            }
        }
        return items
    }

    private var filteredMessages: [UnifiedMessageItem] {
        let q = query.lowercased()
        return allUnifiedMessages.filter { item in
            if let selectedPlatformID, item.platform.id != selectedPlatformID {
                return false
            }
            if unreadOnly {
                let snapshot = store.platformActivity[item.accountID]
                if (snapshot?.unreadCount ?? 0) <= 0 {
                    return false
                }
            }
            if !q.isEmpty {
                let matchSender = item.message.sender.localizedCaseInsensitiveContains(q)
                let matchText = item.message.text.localizedCaseInsensitiveContains(q)
                let matchPlatform = item.platform.name.localizedCaseInsensitiveContains(q)
                let matchAccount = item.accountName.localizedCaseInsensitiveContains(q)
                if !matchSender && !matchText && !matchPlatform && !matchAccount {
                    return false
                }
            }
            return true
        }
    }

    private var activePlatformsWithAccounts: [SocialPlatform] {
        var seen = Set<String>()
        var result: [SocialPlatform] = []
        for account in store.platformAccounts {
            if !seen.contains(account.platformID), let platform = store.platform(account.platformID) {
                seen.insert(account.platformID)
                result.append(platform)
            }
        }
        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroHeader
                platformInboxesQuickBar
                searchAndFilterBar

                switch viewMode {
                case .all:
                    messagesFeedView
                case .byPlatform:
                    byPlatformGroupedView
                case .alerts:
                    alertsAndNoticesView
                }
            }
            .padding(.horizontal, store.preferences.compactMode ? 24 : 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            store.refreshAllPortals()
        }
    }

    // MARK: - Hero Header
    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Palette.accent.gradient)
                        .frame(width: 46, height: 46)
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Palette.accent.opacity(0.25), radius: 6, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Unified Inbox")
                        .font(.system(size: 24, weight: .bold))
                    Text("Live messages, chats, and notifications aggregated across all your connected platforms")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                // Actions & Refresh
                HStack(spacing: 10) {
                    Button {
                        isRefreshing = true
                        store.refreshAllPortals()
                        store.showToast("Waking portals to refresh inboxes…")
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            isRefreshing = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            Text(isRefreshing ? "Refreshing…" : "Sync Portals")
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .help("Wake all platform sessions to query fresh messages")

                    Button {
                        unreadOnly.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: unreadOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            Text("Unread Only")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(unreadOnly ? Palette.accent : Palette.muted)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Stats Pills Row
            HStack(spacing: 10) {
                statPill(
                    icon: "bubble.left.and.bubble.right.fill",
                    label: "\(allUnifiedMessages.count) Conversations",
                    color: Palette.accent
                )

                let totalUnread = store.totalUnreadCount
                if totalUnread > 0 {
                    statPill(
                        icon: "circle.fill",
                        label: "\(totalUnread) Unread Messages",
                        color: .red
                    )
                } else {
                    statPill(
                        icon: "checkmark.circle.fill",
                        label: "All caught up",
                        color: .green
                    )
                }

                statPill(
                    icon: "network",
                    label: "\(store.platformAccounts.count) Accounts Connected",
                    color: Palette.muted
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.card, lineWidth: 1))
    }

    private func statPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Palette.card.opacity(0.6), in: Capsule())
    }

    // MARK: - Platform Inboxes Quick Bar
    private var platformInboxesQuickBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Connected Platform Inboxes")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("Tap any app to open its web portal")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.platformAccounts) { account in
                        if let platform = store.platform(account.platformID) {
                            let snapshot = store.platformActivity[account.id]
                            let unread = snapshot?.unreadCount ?? 0

                            Button {
                                store.openPlatformInbox(accountID: account.id)
                            } label: {
                                HStack(spacing: 10) {
                                    PlatformLogo(platform: platform, size: 26)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(platform.name)
                                                .font(.system(size: 12, weight: .bold))
                                            if unread > 0 {
                                                Text("\(unread)")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1)
                                                    .background(Color.red, in: Capsule())
                                            }
                                        }

                                        Text(account.name)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.muted)
                                            .lineLimit(1)
                                    }

                                    Spacer(minLength: 4)

                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 11))
                                        .foregroundStyle(spaceColor(platform.color))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(minWidth: 160)
                                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(spaceColor(platform.color).opacity(unread > 0 ? 0.4 : 0.15), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Open \(platform.name) (\(account.name)) inbox")
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Search & Filter Bar
    private var searchAndFilterBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Search Input Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)

                    TextField("Search messages, senders, platforms, or accounts…", text: $store.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !store.searchText.isEmpty {
                        Button { store.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))

                // View Mode Switcher
                HStack(spacing: 2) {
                    ForEach(InboxViewMode.allCases, id: \.self) { mode in
                        Button {
                            viewMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: viewMode == mode ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(viewMode == mode ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(viewMode == mode ? .white : Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.card, lineWidth: 1))
            }

            // Platform Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // "All Platforms" chip
                    Button {
                        selectedPlatformID = nil
                    } label: {
                        HStack(spacing: 5) {
                            Text("All Platforms")
                            Text("(\(allUnifiedMessages.count))")
                                .font(.system(size: 10))
                                .opacity(0.7)
                        }
                        .font(.system(size: 11, weight: selectedPlatformID == nil ? .semibold : .regular))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(selectedPlatformID == nil ? Palette.accent.opacity(0.15) : Palette.panel, in: Capsule())
                        .overlay(Capsule().stroke(selectedPlatformID == nil ? Palette.accent : Palette.card, lineWidth: 1))
                        .foregroundStyle(selectedPlatformID == nil ? Palette.accent : Palette.muted)
                    }
                    .buttonStyle(.plain)

                    // Individual Platform Chips
                    ForEach(activePlatformsWithAccounts) { platform in
                        let isSelected = selectedPlatformID == platform.id
                        let platformMsgs = allUnifiedMessages.filter { $0.platform.id == platform.id }
                        let unread = store.accounts(for: platform.id).compactMap { store.platformActivity[$0.id]?.unreadCount }.reduce(0, +)

                        Button {
                            selectedPlatformID = isSelected ? nil : platform.id
                        } label: {
                            HStack(spacing: 6) {
                                PlatformLogo(platform: platform, size: 14)
                                Text(platform.name)
                                Text("(\(platformMsgs.count))")
                                    .font(.system(size: 10))
                                    .opacity(0.7)
                                if unread > 0 {
                                    Circle().fill(.red).frame(width: 6, height: 6)
                                }
                            }
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(isSelected ? spaceColor(platform.color).opacity(0.18) : Palette.panel, in: Capsule())
                            .overlay(Capsule().stroke(isSelected ? spaceColor(platform.color) : Palette.card, lineWidth: 1))
                            .foregroundStyle(isSelected ? spaceColor(platform.color) : Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - Feed View Mode
    private var messagesFeedView: some View {
        VStack(spacing: 10) {
            if filteredMessages.isEmpty {
                emptyStateCard
            } else {
                ForEach(filteredMessages) { item in
                    messageCard(item)
                }
            }
        }
    }

    // MARK: - By Platform Grouped View Mode
    private var byPlatformGroupedView: some View {
        VStack(alignment: .leading, spacing: 20) {
            let platforms = activePlatformsWithAccounts.filter { platform in
                selectedPlatformID == nil || selectedPlatformID == platform.id
            }

            if platforms.isEmpty || allUnifiedMessages.isEmpty {
                emptyStateCard
            } else {
                ForEach(platforms) { platform in
                    let platformMsgs = filteredMessages.filter { $0.platform.id == platform.id }
                    if !platformMsgs.isEmpty || query.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            // Platform Section Header
                            HStack(spacing: 10) {
                                PlatformLogo(platform: platform, size: 22)
                                Text(platform.name)
                                    .font(.system(size: 15, weight: .bold))
                                Text("\(platformMsgs.count) message\(platformMsgs.count == 1 ? "" : "s")")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.muted)

                                Spacer()

                                if let firstAccount = store.accounts(for: platform.id).first {
                                    Button {
                                        store.openPlatformInbox(accountID: firstAccount.id)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text("Open \(platform.name) Inbox")
                                            Image(systemName: "arrow.up.forward.app")
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(spaceColor(platform.color))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 4)

                            if platformMsgs.isEmpty {
                                HStack {
                                    Text("No messages extracted yet from \(platform.name).")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.muted)
                                    Spacer()
                                    if let firstAccount = store.accounts(for: platform.id).first {
                                        Button("Sign in / Open Chats") {
                                            store.openPlatformInbox(accountID: firstAccount.id)
                                        }
                                        .font(.system(size: 11))
                                    }
                                }
                                .padding(12)
                                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                            } else {
                                ForEach(platformMsgs) { item in
                                    messageCard(item)
                                }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    private var allAlerts: [UnifiedAlertItem] {
        var result: [UnifiedAlertItem] = []
        for account in store.platformAccounts {
            guard let platform = store.platform(account.platformID),
                  let snapshot = store.platformActivity[account.id] else { continue }
            for alert in snapshot.notifications {
                result.append(UnifiedAlertItem(account: account, platform: platform, alertText: alert))
            }
        }
        return result
    }

    // MARK: - Alerts and Notices View Mode
    private var alertsAndNoticesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if allAlerts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(Palette.muted)
                    Text("No Notifications or Alerts")
                        .font(.system(size: 15, weight: .bold))
                    Text("Platform system notices, mentions, and alerts will appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(allAlerts) { item in
                    Button {
                        store.openPlatformInbox(accountID: item.account.id)
                    } label: {
                        HStack(spacing: 14) {
                            PlatformLogo(platform: item.platform, size: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("\(item.platform.name) · \(item.account.name)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(spaceColor(item.platform.color))
                                    Spacer()
                                }
                                Text(item.alertText)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(2)
                            }

                            Spacer(minLength: 8)

                            HStack(spacing: 4) {
                                Text("View")
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.accent)
                        }
                        .padding(14)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.card, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Single Message Card
    private func messageCard(_ item: UnifiedMessageItem) -> some View {
        let isHovered = hoveredCardID == item.id
        let platformColor = spaceColor(item.platform.color)

        return Button {
            store.openPlatformInbox(accountID: item.accountID, messageURL: item.message.linkURL)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // Left Avatar with Platform Overlay
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(avatarGradient(for: item.message.sender, colorName: item.platform.color))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(initials(for: item.message.sender))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    // Platform Logo Badge
                    PlatformLogo(platform: item.platform, size: 16)
                        .padding(2)
                        .background(Palette.panel, in: Circle())
                        .offset(x: 3, y: 3)
                }

                // Middle: Message Metadata & Content
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        // App Brand Badge
                        HStack(spacing: 4) {
                            Text(item.platform.name)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(platformColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(platformColor)

                        Text("·")
                            .foregroundStyle(Palette.muted)

                        Text(item.accountName)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)

                        Text("·")
                            .foregroundStyle(Palette.muted)

                        Text(item.message.sender)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)

                        Spacer()

                        if let time = item.message.time, !time.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text(time)
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(Palette.muted)
                        }
                    }

                    Text(item.message.text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                // Right Action Pill
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Open Chat")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isHovered ? platformColor.opacity(0.18) : Palette.card.opacity(0.5), in: Capsule())
                    .foregroundStyle(isHovered ? platformColor : Palette.muted)
                    Spacer()
                }
            }
            .padding(14)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isHovered ? platformColor.opacity(0.6) : Palette.card, lineWidth: isHovered ? 1.5 : 1)
            )
            .shadow(color: isHovered ? platformColor.opacity(0.08) : Color.clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredCardID = hovering ? item.id : nil
        }
        .help("Click to open chat in \(item.platform.name)")
    }

    // MARK: - Empty States
    private var emptyStateCard: some View {
        VStack(spacing: 16) {
            if !query.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(Palette.muted)
                Text("No messages match \"\(query)\"")
                    .font(.system(size: 15, weight: .semibold))
                Text("Try searching for another contact name, keyword, or clear your query.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Button("Clear Search") {
                    store.searchText = ""
                }
                .buttonStyle(.bordered)
            } else if unreadOnly {
                Image(systemName: "envelope.open")
                    .font(.system(size: 32))
                    .foregroundStyle(Palette.muted)
                Text("No Unread Messages")
                    .font(.system(size: 15, weight: .semibold))
                Text("You're completely caught up across all accounts!")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                Button("Show All Messages") {
                    unreadOnly = false
                }
                .buttonStyle(.bordered)
            } else {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Palette.accent)

                VStack(spacing: 4) {
                    Text("No live messages detected yet")
                        .font(.system(size: 16, weight: .bold))
                    Text("PINGGO automatically reads conversations from your active web sessions once you are logged in. Open any of your connected portals below to load your chats:")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }

                // Grid of connected platforms to launch
                if !store.platformAccounts.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                        ForEach(store.platformAccounts) { account in
                            if let platform = store.platform(account.platformID) {
                                Button {
                                    store.openPlatformInbox(accountID: account.id)
                                } label: {
                                    HStack(spacing: 8) {
                                        PlatformLogo(platform: platform, size: 20)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(platform.name)
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(account.name)
                                                .font(.system(size: 10))
                                                .foregroundStyle(Palette.muted)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.forward.app")
                                            .font(.system(size: 10))
                                            .foregroundStyle(spaceColor(platform.color))
                                    }
                                    .padding(10)
                                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxWidth: 580)
                    .padding(.top, 6)
                }
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.card, lineWidth: 1))
    }

    // MARK: - Helpers
    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let second = parts[1].prefix(1)
            return "\(first)\(second)".uppercased()
        } else if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    private func avatarGradient(for sender: String, colorName: String) -> LinearGradient {
        let base = spaceColor(colorName)
        return LinearGradient(
            colors: [base, base.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
