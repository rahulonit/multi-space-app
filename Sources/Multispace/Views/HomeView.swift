import SwiftUI

private enum HomeFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case live = "Active"
    case sleeping = "Sleeping"
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var selectedFilter: HomeFilter = .all
    @State private var hibernateFeedback = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroHeaderCard
                bentoStatsRow
                searchAndFilterBar
                socialAppsBentoGrid
                recentActivityStream
                quickShortcutsBar
            }
            .padding(.horizontal, store.preferences.compactMode ? 16 : 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Hero Header Banner
    private var heroHeaderCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                AppLogo(size: 46, cornerRadius: 11)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("\(greetingText) 👋")
                            .font(.system(size: 24, weight: .bold))
                        Text("·")
                            .foregroundStyle(Palette.muted)
                        Text(formattedDate)
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.muted)
                    }

                    Text("Command center for all your connected social platforms and accounts")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                // Status Pills
                HStack(spacing: 8) {
                    if store.totalUnreadCount > 0 {
                        Button { store.destination = .inbox } label: {
                            HStack(spacing: 6) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Text("\(store.totalUnreadCount) Unread")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("View unread messages in Inbox")
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                            Text("All caught up")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.panel, in: Capsule())
                    }

                    if store.preferences.appLockEnabled {
                        Button { store.lockApp() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.accent)
                                Text("Protected")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.accent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("PINGGO is Touch ID locked · Click to lock now")
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Palette.card, lineWidth: 1)
                )
        )
    }

    // MARK: - Bento Metrics Strip
    private var bentoStatsRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            // Stat 1: Unread Messages
            Button { store.destination = .inbox } label: {
                statTile(
                    title: "Unread Messages",
                    value: "\(store.totalUnreadCount)",
                    subtitle: store.totalUnreadCount == 0 ? "Inbox is zero" : "Across connected apps",
                    symbol: "bubble.left.and.bubble.right.fill",
                    color: store.totalUnreadCount > 0 ? .red : Palette.accent,
                    actionText: "View Inbox →"
                )
            }
            .buttonStyle(.plain)

            // Stat 2: Active Accounts
            Button { store.triggerAddPlatform() } label: {
                statTile(
                    title: "Connected Accounts",
                    value: "\(store.platformAccounts.count)",
                    subtitle: "\(uniquePlatformsCount) social platforms",
                    symbol: "square.stack.3d.up.fill",
                    color: .blue,
                    actionText: "+ Add Account"
                )
            }
            .buttonStyle(.plain)

            // Stat 3: RAM Saver
            Button {
                store.hibernateInactiveNow()
                hibernateFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    hibernateFeedback = false
                }
            } label: {
                statTile(
                    title: "Memory Saver",
                    value: hibernateFeedback ? "Saved!" : "\(estimatedRamSavedMB) MB",
                    subtitle: "\(store.sleepingSessionCount()) sleeping tabs",
                    symbol: "leaf.fill",
                    color: .green,
                    actionText: "Hibernate Inactive"
                )
            }
            .buttonStyle(.plain)

            // Stat 4: Split View Mode
            Button { store.toggleSplitView() } label: {
                statTile(
                    title: "Workspace Layout",
                    value: store.isSplitView ? "Split 2-Pane" : "Single View",
                    subtitle: "Shortcut: ⌘\\",
                    symbol: store.isSplitView ? "rectangle.split.2x1.fill" : "macwindow",
                    color: .purple,
                    actionText: store.isSplitView ? "Close Split" : "Split Screen"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func statTile(title: String, value: String, subtitle: String, symbol: String, color: Color, actionText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }

            HStack {
                Text(actionText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Palette.card, lineWidth: 1)
        )
    }

    // MARK: - Search & Filter Bar
    private var searchAndFilterBar: some View {
        HStack(spacing: 14) {
            // Search Input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)

                TextField("Search platforms, accounts, or messages…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
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

            // Filter Chips
            HStack(spacing: 6) {
                ForEach(HomeFilter.allCases, id: \.self) { filter in
                    let count = countForFilter(filter)
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 4) {
                            Text(filter.rawValue)
                            Text("(\(count))")
                                .font(.system(size: 10))
                                .opacity(0.7)
                        }
                        .font(.system(size: 11, weight: selectedFilter == filter ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedFilter == filter ? Palette.accent.opacity(0.18) : Palette.panel,
                            in: Capsule()
                        )
                        .foregroundStyle(selectedFilter == filter ? Palette.accent : Palette.muted)
                        .overlay(
                            Capsule().stroke(selectedFilter == filter ? Palette.accent.opacity(0.4) : Palette.card, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Social Apps Bento Grid
    private var socialAppsBentoGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("YOUR SOCIAL WORKSPACES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Palette.muted)

                Spacer()

                Button {
                    store.triggerAddPlatform()
                } label: {
                    Label("Add App", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
            }

            let accounts = filteredAccounts
            if accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(Palette.muted)
                    Text("No accounts match your filter")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Try clearing your search query or selecting 'All'.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    Button("Reset Filter") {
                        searchText = ""
                        selectedFilter = .all
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(accounts) { account in
                        if let platform = store.platform(account.platformID) {
                            BentoAppCardView(platform: platform, account: account)
                        }
                    }

                    // Add Platform Card
                    addPlatformBentoCard
                }
            }
        }
    }

    private var addPlatformBentoCard: some View {
        Button {
            store.triggerAddPlatform()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Palette.accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }

                VStack(spacing: 3) {
                    Text("Add Platform")
                        .font(.system(size: 14, weight: .bold))
                    Text("Connect Slack, WhatsApp, Instagram, or custom web address")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(Palette.card)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Activity Stream
    private var recentActivityStream: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("RECENT INCOMING ACTIVITY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Palette.muted)

                Spacer()
            }

            if !hasActivity {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                        .font(.system(size: 28))
                        .foregroundStyle(Palette.muted)
                    Text("No incoming message previews yet")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Sign in to your platforms. When a signed-in portal (like WhatsApp, Discord, or Telegram) receives new messages, instant previews will stream here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.card, lineWidth: 1))
            } else {
                VStack(spacing: 10) {
                    ForEach(store.platformAccounts) { account in
                        if let platform = store.platform(account.platformID),
                           let snapshot = store.platformActivity[account.id] {
                            ForEach(snapshot.messages) { message in
                                activityRow(platform: platform, account: account, title: message.sender, snippet: message.text, isAlert: false)
                            }
                            if store.preferences.showWebsiteAlerts {
                                ForEach(snapshot.notifications, id: \.self) { alert in
                                    activityRow(platform: platform, account: account, title: "Website alert", snippet: alert, isAlert: true)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func activityRow(platform: SocialPlatform, account: PlatformAccount, title: String, snippet: String, isAlert: Bool) -> some View {
        Button {
            store.selectAccount(account.id)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                PlatformLogo(platform: platform, size: 24)
                    .frame(width: 36, height: 36)
                    .background(spaceColor(platform.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: isAlert ? "bell.fill" : "bubble.left.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(isAlert ? .orange : Palette.accent)
                        Text("\(platform.name) · \(account.name)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }

                    Text(title)
                        .font(.system(size: 13, weight: .bold))

                    Text(snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Open")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                }
                .foregroundStyle(Palette.accent)
            }
            .padding(14)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.card, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Launcher Bar
    private var quickShortcutsBar: some View {
        HStack(spacing: 12) {
            Text("POWER SHORTCUTS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Palette.muted)

            Spacer()

            shortcutButton(label: "Command Palette", shortcut: "⌘K") {
                store.showingCommandPalette = true
            }

            shortcutButton(label: "Split View", shortcut: "⌘\\") {
                store.toggleSplitView()
            }

            shortcutButton(label: "Lock PINGGO", shortcut: "⌘L") {
                store.lockApp()
            }

            shortcutButton(label: "Settings", shortcut: "⌘,") {
                store.destination = .settings
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.card, lineWidth: 1))
    }

    private func shortcutButton(label: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11))
                Text(shortcut)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Palette.muted)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter & Computed Helpers
    private var filteredAccounts: [PlatformAccount] {
        store.platformAccounts.filter { account in
            // Filter by search text
            if !searchText.isEmpty {
                let platform = store.platform(account.platformID)
                let platformName = platform?.name ?? ""
                let accountName = account.name
                let messageMatch = (store.platformActivity[account.id]?.messages ?? []).contains {
                    $0.sender.localizedCaseInsensitiveContains(searchText) || $0.text.localizedCaseInsensitiveContains(searchText)
                }

                let matches = platformName.localizedCaseInsensitiveContains(searchText)
                    || accountName.localizedCaseInsensitiveContains(searchText)
                    || messageMatch

                if !matches { return false }
            }

            // Filter by category
            switch selectedFilter {
            case .all:
                return true
            case .unread:
                let unread = store.platformActivity[account.id]?.unreadCount ?? 0
                return unread > 0
            case .live:
                return !store.isSessionHibernated(accountID: account.id)
            case .sleeping:
                return store.isSessionHibernated(accountID: account.id)
            }
        }
    }

    private func countForFilter(_ filter: HomeFilter) -> Int {
        switch filter {
        case .all:
            return store.platformAccounts.count
        case .unread:
            return store.platformAccounts.filter { (store.platformActivity[$0.id]?.unreadCount ?? 0) > 0 }.count
        case .live:
            return store.platformAccounts.filter { !store.isSessionHibernated(accountID: $0.id) }.count
        case .sleeping:
            return store.platformAccounts.filter { store.isSessionHibernated(accountID: $0.id) }.count
        }
    }

    private var uniquePlatformsCount: Int {
        Set(store.platformAccounts.map(\.platformID)).count
    }

    private var estimatedRamSavedMB: Int {
        let sleepingCount = store.sleepingSessionCount()
        return sleepingCount * 140 + (sleepingCount > 0 ? 60 : 0)
    }

    private var hasActivity: Bool {
        store.platformAccounts.contains { account in
            guard let snapshot = store.platformActivity[account.id] else { return false }
            return !snapshot.messages.isEmpty || (store.preferences.showWebsiteAlerts && !snapshot.notifications.isEmpty)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
}

struct BentoAppCardView: View {
    @EnvironmentObject private var store: AppStore
    let platform: SocialPlatform
    let account: PlatformAccount

    var body: some View {
        let snapshot = store.platformActivity[account.id]
        let unread = snapshot?.unreadCount ?? 0
        let isHibernated = store.isSessionHibernated(accountID: account.id)
        let isMuted = store.isSessionMuted(accountID: account.id)
        let isCurrent = store.selectedAccount(for: platform.id)?.id == account.id

        VStack(alignment: .leading, spacing: 14) {
            // Card Header
            HStack(alignment: .center, spacing: 12) {
                PlatformLogo(platform: platform, size: 28)
                    .frame(width: 44, height: 44)
                    .background(spaceColor(platform.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.name)
                        .font(.system(size: 15, weight: .bold))
                    Text(account.name)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                // Status Indicator Badge
                if unread > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("\(unread) unread")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12), in: Capsule())
                } else if isHibernated {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.fill").font(.system(size: 8))
                        Text("Sleeping")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                    .foregroundStyle(.blue)
                } else if isCurrent {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("Live")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1), in: Capsule())
                }
            }

            // Middle Activity / Preview snippet
            VStack(alignment: .leading, spacing: 4) {
                if let message = snapshot?.messages.first {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.muted)
                        Text(message.sender)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    Text(message.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                } else {
                    Text(platform.resolvedWebsiteURL?.host ?? "Connected web portal")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 34, alignment: .topLeading)

            Divider()

            // Card Action Buttons
            HStack(spacing: 8) {
                // Primary Open Button
                Button {
                    store.selectAccount(account.id)
                } label: {
                    HStack(spacing: 5) {
                        Text("Open")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Palette.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)

                // Split View Action
                Button {
                    store.openInSplitView(platformID: platform.id, accountID: account.id)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11))
                        .frame(width: 28, height: 28)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Open in Split View (⌘\\)")

                // Mute / Unmute Action
                Button {
                    store.toggleSessionMute(accountID: account.id)
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                        .font(.system(size: 11))
                        .foregroundStyle(isMuted ? .orange : .primary)
                        .frame(width: 28, height: 28)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help(isMuted ? "Unmute audio" : "Mute tab audio")

                // Wake Action (if sleeping)
                if isHibernated {
                    Button {
                        store.wakeSession(accountID: account.id)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill").font(.system(size: 9))
                            Text("Wake").font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Wake tab from hibernation")
                }

                Spacer()
            }
        }
        .padding(16)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Palette.card, lineWidth: 1)
        )
    }
}
