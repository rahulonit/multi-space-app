import SwiftUI

private enum HomeFilter: String, CaseIterable {
    case all = "All Updates"
    case unread = "Unread"
    case tasks = "Action Items"
    case questions = "Questions"
    case live = "Active"
    case sleeping = "Sleeping"
}

struct HomeActivityItem: Identifiable {
    let id: String
    let platform: SocialPlatform
    let account: PlatformAccount
    let title: String
    let snippet: String
    let time: String?
    let isAlert: Bool
    let isUnread: Bool
    let isQuestion: Bool
    let isTask: Bool
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
                aiExecutiveBriefingCard
                bentoStatsRow
                searchAndFilterBar
                recentActivityStream
                socialAppsBentoGrid
                quickShortcutsBar
            }
            .padding(.horizontal, store.preferences.compactMode ? 16 : 24)
            .padding(.vertical, 24)
            .frame(maxWidth: 1360, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Hero Header Banner
    private var heroHeaderCard: some View {
        let userName = store.userProfile.isSignedIn ? store.userProfile.displayName : store.me.name
        let isOnline = NetworkMonitorService.shared.isConnected
        let netDesc = NetworkMonitorService.shared.connectionDescription

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                AppLogo(size: 48, cornerRadius: 12)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("\(greetingText), \(userName) 👋")
                            .font(.system(size: 23, weight: .bold))
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(Palette.muted)
                        Text(formattedDate)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                    }

                    Text("Universal command center for all your connected social platforms and accounts")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                // Status & Quick Action Pills
                HStack(spacing: 8) {
                    // Network Connectivity Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isOnline ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                        Text(netDesc)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Palette.panel, in: Capsule())
                    .overlay(Capsule().stroke(Palette.card, lineWidth: 1))

                    if store.totalUnreadCount > 0 {
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("\(store.totalUnreadCount) Unread")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
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
                        .overlay(Capsule().stroke(Palette.card, lineWidth: 1))
                    }

                    if store.preferences.appLockEnabled {
                        Button { store.lockApp() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.accent)
                                Text("Locked")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.accent.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(Palette.accent.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("PINGGO is protected · Click to lock (⌘L)")
                    }

                    Button {
                        store.destination = .settings
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 28, height: 28)
                            .background(Palette.panel, in: Circle())
                            .overlay(Circle().stroke(Palette.card, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Preferences & Settings (⌘,)")
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Palette.panel, Palette.panel.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Palette.card, lineWidth: 1)
                )
        )
    }

    // MARK: - AI Executive Briefing Card
    private var aiExecutiveBriefingCard: some View {
        let summary = store.platformSummaries["all"]
        let headline = summary?.headline ?? "All inboxes clear across connected platforms"
        let overview = summary?.executiveOverview ?? "No pending messages or action items across any connected platforms. You are completely caught up!"
        let actionItems = summary?.actionItems ?? []
        let questions = summary?.threads.compactMap { thread -> (sender: String, question: String)? in
            guard let q = thread.detectedQuestion, !q.isEmpty else { return nil }
            return (thread.sender, q)
        } ?? []
        let topics = summary?.keyTopics ?? []

        return VStack(alignment: .leading, spacing: 14) {
            // Header Row
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("AI EXECUTIVE BRIEFING")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundStyle(Palette.accent)

                        Text("·")
                            .foregroundStyle(Palette.muted)

                        Text("Cross-Platform Synthesis")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }

                    Text(headline)
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                Button {
                    store.refreshSummaries()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Refresh AI")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.panel, in: Capsule())
                    .overlay(Capsule().stroke(Palette.card, lineWidth: 1))
                    .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .help("Re-synthesize intelligence across all active portals")
            }

            // Overview Narrative Banner
            Text(overview)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.text)
                .lineSpacing(3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            // Action Items & Questions Grid
            if !actionItems.isEmpty || !questions.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    // Action Items Column
                    if !actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.orange)
                                Text("ACTION ITEMS (\(actionItems.count))")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .tracking(1.0)
                                    .foregroundStyle(Palette.muted)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(actionItems.prefix(4).enumerated()), id: \.offset) { _, item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.orange)
                                            .padding(.top, 2)
                                        Text(item)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Palette.text)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))
                    }

                    // Questions Column
                    if !questions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 5) {
                                Image(systemName: "questionmark.bubble.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.purple)
                                Text("QUESTIONS AWAITING REPLY (\(questions.count))")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .tracking(1.0)
                                    .foregroundStyle(Palette.muted)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(questions.prefix(3).enumerated()), id: \.offset) { _, pair in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pair.sender)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Palette.accent)
                                        Text("\"\(pair.question)\"")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Palette.text)
                                            .italic()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))
                    }
                }
            }

            // Topics Chips
            if !topics.isEmpty {
                HStack(spacing: 6) {
                    Text("KEY TOPICS:")
                        .font(.system(size: 9.5, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(Palette.muted)

                    ForEach(topics, id: \.self) { topic in
                        Text("#\(topic)")
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Palette.card, in: Capsule())
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Palette.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            LinearGradient(
                                colors: [Palette.accent.opacity(0.35), Palette.card],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Bento Metrics Strip
    private var bentoStatsRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            // Stat 1: Unread Messages
            Button {
                selectedFilter = .unread
            } label: {
                statTile(
                    title: "Unread Messages",
                    value: "\(store.totalUnreadCount)",
                    subtitle: store.totalUnreadCount == 0 ? "All inboxes reviewed" : "Pending your attention",
                    symbol: "bubble.left.and.bubble.right.fill",
                    color: store.totalUnreadCount > 0 ? .red : Palette.accent,
                    actionText: store.totalUnreadCount > 0 ? "Review Unreads" : nil
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
                    actionText: "+ Add Platform"
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
                    value: hibernateFeedback ? "RAM Freed!" : "\(estimatedRamSavedMB) MB",
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
                    subtitle: "Toggle side-by-side (⌘\\)",
                    symbol: store.isSplitView ? "rectangle.split.2x1.fill" : "macwindow",
                    color: .purple,
                    actionText: store.isSplitView ? "Exit Split" : "Split Screen"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func statTile(title: String, value: String, subtitle: String, symbol: String, color: Color, actionText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }

            if let actionText = actionText, !actionText.isEmpty {
                HStack(spacing: 4) {
                    Text(actionText)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(color)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(color)
                    Spacer()
                }
            } else {
                HStack {
                    Text("Live status")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                }
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

                TextField("Search platforms, accounts, contacts, or messages…", text: $searchText)
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

    // MARK: - Recent Activity Stream
    private var recentActivityStream: some View {
        let items = filteredActivityItems

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("UNIFIED ACTIVITY STREAM")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Palette.muted)

                Spacer()

                Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }

            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                        .font(.system(size: 28))
                        .foregroundStyle(Palette.muted)
                    Text("No matching incoming activity")
                        .font(.system(size: 14, weight: .semibold))
                    Text("When connected platforms (like WhatsApp, Discord, or Telegram) receive new messages, instant previews will stream here.")
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
                    ForEach(items.prefix(20)) { item in
                        activityRowView(item: item)
                    }
                }
            }
        }
    }

    private func activityRowView(item: HomeActivityItem) -> some View {
        Button {
            store.selectAccount(item.account.id)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                PlatformLogo(platform: item.platform, size: 24)
                    .frame(width: 38, height: 38)
                    .background(spaceColor(item.platform.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(item.platform.name) · \(item.account.name)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.muted)

                        if item.isUnread {
                            Text("Unread")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.red.opacity(0.12), in: Capsule())
                        }

                        if item.isTask {
                            Text("Action Item")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }

                        if item.isQuestion {
                            Text("Question")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.purple.opacity(0.12), in: Capsule())
                        }

                        if item.isAlert {
                            Text("Alert")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }

                        Spacer()

                        if let time = item.time {
                            Text(time)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                        }
                    }

                    Text(item.title)
                        .font(.system(size: 13, weight: .bold))

                    Text(item.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        store.openInSplitView(platformID: item.platform.id, accountID: item.account.id)
                    } label: {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 26, height: 26)
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Open in Split View (⌘\\)")

                    HStack(spacing: 4) {
                        Text("Open")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Palette.accent)
                }
            }
            .padding(14)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.card, lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    // MARK: - Activity Items Aggregator
    private var allActivityItems: [HomeActivityItem] {
        var items: [HomeActivityItem] = []
        for account in store.platformAccounts {
            guard let platform = store.platform(account.platformID),
                  let snapshot = store.platformActivity[account.id] else { continue }

            for message in snapshot.messages {
                let text = message.text
                let lower = text.lowercased()
                let isQ = text.contains("?") || lower.hasPrefix("can ") || lower.hasPrefix("could ") || lower.hasPrefix("what ") || lower.hasPrefix("how ") || lower.hasPrefix("when ") || lower.hasPrefix("where ")
                let isT = lower.contains("todo") || lower.contains("please ") || lower.contains("need to") || lower.contains("urgent") || lower.contains("deadline") || lower.contains("review") || lower.contains("send ")
                items.append(HomeActivityItem(
                    id: message.id,
                    platform: platform,
                    account: account,
                    title: message.sender,
                    snippet: text,
                    time: message.time,
                    isAlert: false,
                    isUnread: message.isUnread == true,
                    isQuestion: isQ,
                    isTask: isT
                ))
            }

            if store.preferences.showWebsiteAlerts {
                for (idx, alert) in snapshot.notifications.enumerated() {
                    items.append(HomeActivityItem(
                        id: "\(account.id)-alert-\(idx)",
                        platform: platform,
                        account: account,
                        title: "Website Alert",
                        snippet: alert,
                        time: nil,
                        isAlert: true,
                        isUnread: false,
                        isQuestion: false,
                        isTask: false
                    ))
                }
            }
        }
        return items
    }

    private var filteredActivityItems: [HomeActivityItem] {
        allActivityItems.filter { item in
            // Filter by search query
            if !searchText.isEmpty {
                let matches = item.title.localizedCaseInsensitiveContains(searchText)
                    || item.snippet.localizedCaseInsensitiveContains(searchText)
                    || item.platform.name.localizedCaseInsensitiveContains(searchText)
                    || item.account.name.localizedCaseInsensitiveContains(searchText)
                if !matches { return false }
            }

            // Filter by category chip
            switch selectedFilter {
            case .all:
                return true
            case .unread:
                return item.isUnread
            case .tasks:
                return item.isTask
            case .questions:
                return item.isQuestion
            case .live:
                return !store.isSessionHibernated(accountID: item.account.id)
            case .sleeping:
                return store.isSessionHibernated(accountID: item.account.id)
            }
        }
    }

    // MARK: - Filter & Computed Helpers
    private var filteredAccounts: [PlatformAccount] {
        store.platformAccounts.filter { account in
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

            switch selectedFilter {
            case .all, .tasks, .questions:
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
            return allActivityItems.count
        case .unread:
            return allActivityItems.filter(\.isUnread).count
        case .tasks:
            return allActivityItems.filter(\.isTask).count
        case .questions:
            return allActivityItems.filter(\.isQuestion).count
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
                PlatformLogo(platform: platform, size: 26)
                    .frame(width: 42, height: 42)
                    .background(spaceColor(platform.color).opacity(0.14), in: RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.name)
                        .font(.system(size: 14, weight: .bold))
                    Text(account.name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                // Status Indicator Badge
                if unread > 0 {
                    HStack(spacing: 5) {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("\(unread) unread")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Color.red.opacity(0.3), lineWidth: 1))
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
                        Text("Active")
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
                            .font(.system(size: 8.5))
                            .foregroundStyle(Palette.accent)
                        Text(message.sender)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        if let time = message.time {
                            Text(time)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    Text(message.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                        Text(platform.resolvedWebsiteURL?.host ?? "Connected web portal")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            Divider()

            // Card Action Buttons
            HStack(spacing: 8) {
                // Primary Open Button
                Button {
                    store.selectAccount(account.id)
                } label: {
                    HStack(spacing: 5) {
                        Text("Open Portal")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)

                // Split View Action
                Button {
                    store.openInSplitView(platformID: platform.id, accountID: account.id)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
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
                        .foregroundStyle(isMuted ? .orange : Palette.muted)
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
