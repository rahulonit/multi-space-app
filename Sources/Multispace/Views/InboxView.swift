import SwiftUI
import AppKit

private enum InboxFolder: String, CaseIterable {
    case all = "All Messages"
    case unread = "Unread Only"
    case alerts = "Alerts & Notices"

    var icon: String {
        switch self {
        case .all: return "tray.full.fill"
        case .unread: return "line.3.horizontal.decrease.circle.fill"
        case .alerts: return "bell.badge.fill"
        }
    }
}

private enum SummarySubTab: String, CaseIterable {
    case overview = "Briefing"
    case actions = "Action Items"
    case threads = "Contacts"
}

struct UnifiedMessageItem: Identifiable, Equatable {
    var id: String { "\(accountID)-\(message.id)" }
    let accountID: UUID
    let accountName: String
    let platform: SocialPlatform
    let message: PlatformMessagePreview
    let snapshotDate: Date
}

@MainActor
enum AlertCategoryType: String, CaseIterable {
    case all = "All"
    case mention = "Mentions"
    case request = "Requests"
    case security = "Security"
    case reaction = "Reactions"
    case reply = "Replies"
    case stream = "Notices Hub"

    var icon: String {
        switch self {
        case .all: return "bell.badge"
        case .mention: return "at"
        case .request: return "person.badge.plus"
        case .security: return "shield.lefthalf.filled"
        case .reaction: return "heart.fill"
        case .reply: return "bubble.left.and.bubble.right.fill"
        case .stream: return "bell.fill"
        }
    }

    @MainActor
    var color: Color {
        switch self {
        case .all: return Palette.accent
        case .mention: return Color.blue
        case .request: return Color.purple
        case .security: return Color.red
        case .reaction: return Color.pink
        case .reply: return Color.teal
        case .stream: return Color.orange
        }
    }
}

@MainActor
struct UnifiedAlertItem: Identifiable, Equatable {
    let id: String
    let account: PlatformAccount
    let platform: SocialPlatform
    let title: String
    let alertText: String
    let time: String?
    let directURL: URL?
    let category: String
    let isLiveExtracted: Bool

    var categoryType: AlertCategoryType {
        switch category.lowercased() {
        case "mention": return .mention
        case "request": return .request
        case "security": return .security
        case "reaction": return .reaction
        case "reply": return .reply
        case "stream": return .stream
        default: return .stream
        }
    }

    var displayTime: String {
        time ?? (isLiveExtracted ? "Recent" : "Live Stream")
    }
}

struct InboxView: View {
    @EnvironmentObject private var store: AppStore

    // Navigation & Selection State
    @State private var selectedFolder: InboxFolder = .all
    @State private var selectedPlatformID: String? = nil // nil means "All Platforms"
    @State private var selectedMessageID: String? = nil
    @State private var selectedAlertID: String? = nil
    @State private var selectedAlertCategory: AlertCategoryType = .all

    // Filter & Search State
    @State private var searchQuery: String = ""
    @State private var selectedIntentFilter: String? = nil
    @State private var isSummaryExpanded: Bool = true
    @State private var summarySubTab: SummarySubTab = .overview
    @State private var completedActionItems: Set<String> = []
    @State private var isRefreshing: Bool = false
    @State private var isRegenerating: Bool = false
    @State private var copiedNotice: Bool = false
    @State private var copiedAlertURL: Bool = false
    @State private var copiedReplyIndex: Int? = nil

    private var query: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
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
            // Platform filter
            if let selectedPlatformID, item.platform.id != selectedPlatformID {
                return false
            }
            // Folder filter
            if selectedFolder == .unread {
                let snapshot = store.platformActivity[item.accountID]
                if (snapshot?.unreadCount ?? 0) <= 0 {
                    return false
                }
            }
            // Intent chip filter
            if let filter = selectedIntentFilter {
                let analysis = ConversationSummaryService.shared.analyzeMessage(item.message)
                if !analysis.detectedIntent.contains(filter) {
                    return false
                }
            }
            // Search text filter
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

    private func notificationsHubDescriptor(for platform: SocialPlatform) -> (title: String, desc: String, category: String) {
        switch platform.id.lowercased() {
        case "linkedin":
            return (
                "Activity & Network Notices",
                "Live stream of your post impressions, connection requests, profile views, and network mentions.",
                "stream"
            )
        case "x":
            return (
                "Notifications Hub",
                "Direct access to your verified mentions, retweets, quotes, reposts, and notification alerts.",
                "mention"
            )
        case "whatsapp":
            return (
                "Security & Sync Notices",
                "Device link status, security encryption verification, and incoming group alerts.",
                "security"
            )
        case "discord":
            return (
                "Mentions & Inbox Hub",
                "Server @mentions, direct pings, unread thread activity, and member notices.",
                "mention"
            )
        case "slack":
            return (
                "Mentions & Activity Feed",
                "Channel @mentions, workspace threads, emoji reactions, and workflow app updates.",
                "mention"
            )
        case "instagram":
            return (
                "Activity Feed",
                "Likes, comments, story tags, direct message requests, and new follower alerts.",
                "reaction"
            )
        case "facebook":
            return (
                "Notifications Center",
                "Friend requests, group notifications, post tags, and community alerts.",
                "request"
            )
        case "reddit":
            return (
                "Notifications & Inbox",
                "Upvote milestones, post comment replies, moderator alerts, and subreddit notices.",
                "reply"
            )
        case "threads":
            return (
                "Activity & Mentions",
                "Replies, quotes, reposts, and profile mentions across your Threads feed.",
                "reply"
            )
        case "telegram":
            return (
                "Service Notices",
                "Login codes, channel broadcasts, secret chat alerts, and session updates.",
                "security"
            )
        default:
            return (
                "Notifications Stream",
                "Direct gateway to all notifications, alerts, and live activity for \(platform.name).",
                "stream"
            )
        }
    }

    private var allAlerts: [UnifiedAlertItem] {
        var result: [UnifiedAlertItem] = []

        // 1. Live extracted notifications across all accounts
        for account in store.platformAccounts {
            guard let platform = store.platform(account.platformID),
                  let snapshot = store.platformActivity[account.id] else { continue }

            for preview in snapshot.allNotificationPreviews {
                let directURL: URL? = {
                    if let raw = preview.linkURL, let u = URL(string: raw), u.scheme?.hasPrefix("http") == true {
                        return u
                    }
                    return platform.notificationsURL ?? platform.resolvedWebsiteURL
                }()

                result.append(UnifiedAlertItem(
                    id: "\(account.id)-\(preview.id)",
                    account: account,
                    platform: platform,
                    title: preview.title.isEmpty ? "\(platform.name) Alert" : preview.title,
                    alertText: preview.text,
                    time: preview.time,
                    directURL: directURL,
                    category: preview.category,
                    isLiveExtracted: true
                ))
            }
        }

        // 2. Official Notifications Hub for EVERY connected account
        // Ensures all connected platforms are always meaningfully represented with direct links
        for account in store.platformAccounts {
            guard let platform = store.platform(account.platformID) else { continue }
            let hubURL = platform.notificationsURL ?? platform.inboxURL ?? platform.resolvedWebsiteURL
            let info = notificationsHubDescriptor(for: platform)

            result.append(UnifiedAlertItem(
                id: "\(account.id)-hub-\(platform.id)",
                account: account,
                platform: platform,
                title: "\(platform.name) · \(info.title)",
                alertText: info.desc,
                time: "Live Hub",
                directURL: hubURL,
                category: info.category,
                isLiveExtracted: false
            ))
        }

        return result
    }

    private var filteredAlerts: [UnifiedAlertItem] {
        let q = query.lowercased()
        return allAlerts.filter { alert in
            // Platform filter
            if let selectedPlatformID, alert.platform.id != selectedPlatformID {
                return false
            }
            // Category filter
            if selectedAlertCategory != .all {
                if alert.categoryType != selectedAlertCategory {
                    return false
                }
            }
            // Search query filter
            if !q.isEmpty {
                let matchTitle = alert.title.localizedCaseInsensitiveContains(q)
                let matchText = alert.alertText.localizedCaseInsensitiveContains(q)
                let matchPlatform = alert.platform.name.localizedCaseInsensitiveContains(q)
                let matchAccount = alert.account.name.localizedCaseInsensitiveContains(q)
                if !matchTitle && !matchText && !matchPlatform && !matchAccount {
                    return false
                }
            }
            return true
        }
    }

    private var selectedAlert: UnifiedAlertItem? {
        if let id = selectedAlertID {
            return filteredAlerts.first(where: { $0.id == id }) ?? filteredAlerts.first
        }
        return filteredAlerts.first
    }

    private var selectedMessage: UnifiedMessageItem? {
        if let id = selectedMessageID {
            return filteredMessages.first(where: { $0.id == id }) ?? filteredMessages.first
        }
        return filteredMessages.first
    }

    private var currentSummary: PlatformConversationSummary? {
        let key = selectedPlatformID ?? "all"
        return store.platformSummaries[key]
    }

    // MARK: - Body (3-Pane Split)
    var body: some View {
        HStack(spacing: 0) {
            // PANE 1: Left Navigation Rail (Folders & Platforms)
            inboxNavigatorPane
                .frame(width: 230)
                .background(Palette.sidebar)

            Divider()
                .background(Palette.border)

            // PANE 2: Center Message Stream & Conversation Summary Digest
            inboxMessageStreamPane
                .frame(width: 380)
                .background(Palette.panel)

            Divider()
                .background(Palette.border)

            // PANE 3: Right Live Reader & Embedded Portal View
            inboxReaderPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            store.refreshSummaries()
            if selectedMessageID == nil {
                selectedMessageID = filteredMessages.first?.id
            }
        }
    }

    // MARK: - PANE 1: Left Rail (Navigator)
    private var inboxNavigatorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Palette.accent.gradient)
                        .frame(width: 26, height: 26)
                    Image(systemName: "tray.2.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("Inbox")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                if store.totalUnreadCount > 0 {
                    Text("\(store.totalUnreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Smart Folders Section
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SMART VIEWS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.muted.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 4)

                        folderRow(folder: .all, count: allUnifiedMessages.count)
                        folderRow(folder: .unread, count: store.totalUnreadCount, isBadgeRed: true)
                        folderRow(folder: .alerts, count: allAlerts.count)
                    }

                    // Connected Platforms Section
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("PLATFORMS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.muted.opacity(0.8))
                            Spacer()
                            Text("\(activePlatformsWithAccounts.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)

                        // "All Platforms" item
                        platformRow(
                            name: "All Platforms",
                            symbol: "square.grid.2x2",
                            color: "accent",
                            platformID: nil,
                            unread: store.totalUnreadCount,
                            total: allUnifiedMessages.count
                        )

                        // Per-platform rows
                        ForEach(activePlatformsWithAccounts) { platform in
                            let msgs = allUnifiedMessages.filter { $0.platform.id == platform.id }
                            let unread = store.accounts(for: platform.id).compactMap { store.platformActivity[$0.id]?.unreadCount }.reduce(0, +)

                            platformRow(
                                name: platform.name,
                                platform: platform,
                                platformID: platform.id,
                                unread: unread,
                                total: msgs.count
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer(minLength: 0)

            // Footer Quick Actions
            VStack(spacing: 8) {
                Divider()

                HStack(spacing: 8) {
                    Button {
                        isRefreshing = true
                        store.refreshAllPortals()
                        store.refreshSummaries()
                        store.showToast("Waking portals & syncing inboxes…")
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            isRefreshing = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            Text(isRefreshing ? "Syncing…" : "Sync Portals")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        isRegenerating = true
                        store.refreshSummaries()
                        store.showToast("AI Summaries regenerated")
                        Task {
                            try? await Task.sleep(for: .seconds(0.5))
                            isRegenerating = false
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Regenerate AI Conversation Summaries")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private func folderRow(folder: InboxFolder, count: Int, isBadgeRed: Bool = false) -> some View {
        let isSelected = selectedFolder == folder

        return Button {
            selectedFolder = folder
            if folder == .alerts {
                selectedAlertID = filteredAlerts.first?.id ?? allAlerts.first?.id
            } else {
                selectedMessageID = filteredMessages.first?.id
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: folder.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.muted)
                    .frame(width: 18)

                Text(folder.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Palette.muted)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isBadgeRed && count > 0 ? .white : Palette.muted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(isBadgeRed && count > 0 ? Color.red : Palette.card.opacity(0.8), in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Palette.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Palette.accent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func platformRow(
        name: String,
        platform: SocialPlatform? = nil,
        symbol: String = "circle",
        color: String = "accent",
        platformID: String?,
        unread: Int,
        total: Int
    ) -> some View {
        let isSelected = selectedPlatformID == platformID

        return Button {
            selectedPlatformID = platformID
            if selectedFolder == .alerts {
                selectedAlertID = filteredAlerts.first?.id
            } else {
                selectedMessageID = filteredMessages.first?.id
            }
        } label: {
            HStack(spacing: 9) {
                if let platform {
                    PlatformLogo(platform: platform, size: 16)
                        .frame(width: 18)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 18)
                }

                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Palette.muted)
                    .lineLimit(1)

                Spacer()

                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.red, in: Capsule())
                } else if total > 0 {
                    Text("\(total)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? (platform != nil ? spaceColor(platform!.color).opacity(0.15) : Palette.accent.opacity(0.12)) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? (platform != nil ? spaceColor(platform!.color).opacity(0.35) : Palette.accent.opacity(0.3)) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - PANE 2: Center Message Stream & Conversation Summary
    private var inboxMessageStreamPane: some View {
        VStack(spacing: 0) {
            // Search & Filter Header
            VStack(spacing: 8) {
                // Search Input
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)

                    TextField("Filter messages, senders, topics…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.card, lineWidth: 1))

                // Intent Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        intentChip(title: "All", filter: nil)
                        intentChip(title: "📅 Meetings", filter: "Meeting")
                        intentChip(title: "📝 Actions", filter: "Review")
                        intentChip(title: "🚨 Urgent", filter: "Urgent")
                        intentChip(title: "🤝 Business", filter: "Business")
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(12)
            .background(Palette.panel)

            Divider()
                .background(Palette.border)

            if selectedFolder == .alerts {
                // Alerts & Notices list mode
                alertsStreamView
            } else {
                // Regular messages stream with Platform Conversation Summary Header
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // Intelligent Conversation Summary Card
                        enhancedPlatformSummaryCard

                        // Stream items count label
                        HStack {
                            Text("\(filteredMessages.count) CONVERSATION\(filteredMessages.count == 1 ? "" : "S")")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.muted.opacity(0.8))

                            Spacer()

                            if selectedPlatformID != nil, let platform = store.platform(selectedPlatformID!) {
                                HStack(spacing: 4) {
                                    PlatformLogo(platform: platform, size: 12)
                                    Text(platform.name)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(spaceColor(platform.color))
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                        // Message Cards Stream
                        if filteredMessages.isEmpty {
                            emptyStreamCard
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredMessages) { item in
                                    messageStreamCard(item)
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Enhanced Conversation Summary Card
    private var enhancedPlatformSummaryCard: some View {
        let summary = currentSummary ?? ConversationSummaryService.shared.generateExecutiveBriefing(
            platforms: activePlatformsWithAccounts,
            accounts: store.platformAccounts,
            activity: store.platformActivity
        )

        let targetPlatform = selectedPlatformID != nil ? store.platform(selectedPlatformID!) : nil
        let brandColor = targetPlatform != nil ? spaceColor(targetPlatform!.color) : Palette.accent

        return VStack(alignment: .leading, spacing: 10) {
            // Top Card Header
            HStack(spacing: 8) {
                if let targetPlatform {
                    PlatformLogo(platform: targetPlatform, size: 20)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(targetPlatform != nil ? "\(targetPlatform!.name) Summary" : "Executive Inbox Digest")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.primary)

                        urgencyBadge(summary.urgency)
                    }

                    Text(summary.headline)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }

                Spacer()

                // Actions: Refresh + Collapse
                HStack(spacing: 6) {
                    Button {
                        isRegenerating = true
                        store.refreshSummaries()
                        Task {
                            try? await Task.sleep(for: .seconds(0.4))
                            isRegenerating = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .rotationEffect(.degrees(isRegenerating ? 360 : 0))
                            .animation(isRegenerating ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRegenerating)
                            .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Regenerate intelligence summary")

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            isSummaryExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isSummaryExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isSummaryExpanded {
                // Metrics HUD Row
                HStack(spacing: 8) {
                    summaryMetricPill(
                        icon: "person.2.fill",
                        label: "\(summary.activeSendersCount) Contacts",
                        color: brandColor
                    )

                    if summary.questionsCount > 0 {
                        summaryMetricPill(
                            icon: "questionmark.circle.fill",
                            label: "\(summary.questionsCount) Questions",
                            color: .orange
                        )
                    }

                    if !summary.actionItems.isEmpty {
                        summaryMetricPill(
                            icon: "bolt.fill",
                            label: "\(summary.actionItems.count) Actions",
                            color: .red
                        )
                    }

                    Spacer()
                }

                // Sub-Tab Switcher
                HStack(spacing: 4) {
                    ForEach(SummarySubTab.allCases, id: \.self) { tab in
                        Button {
                            summarySubTab = tab
                        } label: {
                            HStack(spacing: 4) {
                                Text(tab.rawValue)
                                if tab == .actions && !summary.actionItems.isEmpty {
                                    Text("\(summary.actionItems.count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange, in: Capsule())
                                } else if tab == .threads && !summary.threads.isEmpty {
                                    Text("\(summary.threads.count)")
                                        .font(.system(size: 9))
                                        .opacity(0.8)
                                }
                            }
                            .font(.system(size: 10, weight: summarySubTab == tab ? .semibold : .regular))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(summarySubTab == tab ? brandColor.opacity(0.18) : Palette.background, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(summarySubTab == tab ? brandColor : Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.top, 2)

                Divider()
                    .background(brandColor.opacity(0.2))

                // Tab Contents
                switch summarySubTab {
                case .overview:
                    // Overview: Synthesized paragraph + Topic badges + Key thread highlights
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary.executiveOverview)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.95))
                            .lineSpacing(2)

                        // Key Topics Tags
                        if !summary.keyTopics.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach(summary.keyTopics, id: \.self) { topic in
                                        Text(topic)
                                            .font(.system(size: 9.5, weight: .medium))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2.5)
                                            .background(brandColor.opacity(0.12), in: Capsule())
                                            .foregroundStyle(brandColor)
                                    }
                                }
                            }
                        }

                        // Thread Synthesized Bullets
                        if !summary.bulletPoints.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(summary.bulletPoints, id: \.self) { bullet in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("•")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(brandColor)
                                        Text(bullet)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(Color.primary.opacity(0.9))
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }

                case .actions:
                    // Action Items Tab
                    VStack(alignment: .leading, spacing: 5) {
                        if summary.actionItems.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("No pending action items on this platform.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(.vertical, 6)
                        } else {
                            ForEach(summary.actionItems, id: \.self) { action in
                                let isDone = completedActionItems.contains(action)
                                HStack(spacing: 8) {
                                    Button {
                                        if isDone {
                                            completedActionItems.remove(action)
                                        } else {
                                            completedActionItems.insert(action)
                                        }
                                    } label: {
                                        Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 13))
                                            .foregroundStyle(isDone ? .green : .orange)
                                    }
                                    .buttonStyle(.plain)

                                    Text(action)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(isDone ? Palette.muted : Color.primary)
                                        .strikethrough(isDone)

                                    Spacer()

                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Palette.muted)
                                }
                                .padding(8)
                                .background(isDone ? Palette.background.opacity(0.5) : Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                            }
                        }
                    }

                case .threads:
                    // Active Contacts / Threads Tab
                    VStack(alignment: .leading, spacing: 6) {
                        if summary.threads.isEmpty {
                            Text("No contacts detected yet.")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                        } else {
                            ForEach(summary.threads) { thread in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(avatarGradient(for: thread.sender, colorName: "accent"))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text(initials(for: thread.sender))
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                        )

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(thread.sender)
                                                .font(.system(size: 11, weight: .bold))
                                            Text("·")
                                                .foregroundStyle(Palette.muted)
                                            Text(thread.detectedIntent)
                                                .font(.system(size: 9.5, weight: .medium))
                                                .foregroundStyle(brandColor)
                                        }

                                        Text(thread.contextSummary)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(Palette.muted)
                                            .lineLimit(2)

                                        if let q = thread.detectedQuestion {
                                            HStack(spacing: 4) {
                                                Image(systemName: "questionmark.circle")
                                                    .font(.system(size: 8))
                                                    .foregroundStyle(.orange)
                                                Text(q)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.orange)
                                                    .lineLimit(1)
                                            }
                                            .padding(.top, 1)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Palette.background, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(brandColor.opacity(0.35), lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
    }

    private func summaryMetricPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Palette.background, in: Capsule())
    }

    private func urgencyBadge(_ urgency: SummaryUrgency) -> some View {
        let (color, icon) = urgencyColorAndIcon(urgency)

        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
            Text(urgency.rawValue)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func urgencyColorAndIcon(_ urgency: SummaryUrgency) -> (Color, String) {
        switch urgency {
        case .high: return (.red, "exclamationmark.triangle.fill")
        case .medium: return (.orange, "clock.fill")
        case .normal: return (Palette.accent, "info.circle.fill")
        case .caughtUp: return (.green, "checkmark.circle.fill")
        }
    }

    private func intentChip(title: String, filter: String?) -> some View {
        let isSelected = selectedIntentFilter == filter

        return Button {
            selectedIntentFilter = isSelected ? nil : filter
        } label: {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isSelected ? Palette.accent.opacity(0.18) : Palette.card, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Palette.accent : Palette.border, lineWidth: 1))
                .foregroundStyle(isSelected ? Palette.accent : Palette.muted)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Message Card in Stream
    private func messageStreamCard(_ item: UnifiedMessageItem) -> some View {
        let isSelected = selectedMessageID == item.id
        let platformColor = spaceColor(item.platform.color)
        let analysis = ConversationSummaryService.shared.analyzeMessage(item.message)

        return Button {
            selectedMessageID = item.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Avatar with Platform Overlay
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(avatarGradient(for: item.message.sender, colorName: item.platform.color))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(initials(for: item.message.sender))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    PlatformLogo(platform: item.platform, size: 14)
                        .padding(1)
                        .background(Palette.panel, in: Circle())
                        .offset(x: 2, y: 2)
                }

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(item.message.sender)
                            .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        Spacer()

                        if let time = item.message.time, !time.isEmpty {
                            Text(time)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                        }
                    }

                    // Intent / Action Tag
                    if analysis.detectedIntent != "General Update" {
                        HStack(spacing: 3) {
                            Text(analysis.detectedIntent)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(analysis.urgency == .high ? Color.red : (analysis.urgency == .medium ? Color.orange : platformColor))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            (analysis.urgency == .high ? Color.red : (analysis.urgency == .medium ? Color.orange : platformColor)).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                    }

                    // Snippet
                    Text(item.message.text)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.9) : Palette.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .background(isSelected ? Palette.accent.opacity(0.14) : Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Palette.accent : Palette.card, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Alerts Stream Mode
    private var alertsStreamView: some View {
        VStack(spacing: 0) {
            // Category Filter Pills & Counter
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(filteredAlerts.count) ALERTS & NOTICES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.muted)

                    if let platformID = selectedPlatformID, let platform = store.platform(platformID) {
                        Text("• \(platform.name)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(spaceColor(platform.color))
                    }

                    Spacer()

                    Button {
                        store.refreshAllPortals()
                        store.showToast("Refreshed alerts across platforms")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                        }
                        .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                // Category Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AlertCategoryType.allCases, id: \.self) { cat in
                            let isSelected = selectedAlertCategory == cat
                            Button {
                                selectedAlertCategory = cat
                                selectedAlertID = filteredAlerts.first?.id
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 9))
                                    Text(cat.rawValue)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isSelected ? cat.color.opacity(0.18) : Palette.card, in: Capsule())
                                .overlay(Capsule().stroke(isSelected ? cat.color : Palette.border, lineWidth: 1))
                                .foregroundStyle(isSelected ? cat.color : Palette.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 6)

                Divider()
                    .background(Palette.border)
            }

            // Stream of Alert Cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    if filteredAlerts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: selectedAlertCategory == .all ? "bell.slash" : selectedAlertCategory.icon)
                                .font(.system(size: 28))
                                .foregroundStyle(Palette.muted)
                            Text(selectedAlertCategory == .all ? "No Alerts" : "No \(selectedAlertCategory.rawValue)")
                                .font(.system(size: 13, weight: .bold))
                            Text("All platform notices and notifications in this view are up to date.")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(36)
                    } else {
                        ForEach(filteredAlerts) { alert in
                            alertCard(alert)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
        }
    }

    private func alertCard(_ alert: UnifiedAlertItem) -> some View {
        let isSelected = selectedAlert?.id == alert.id
        let catColor = alert.categoryType.color

        return Button {
            selectedAlertID = alert.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // Top Row: Logo, Platform & Account, Category Badge
                HStack(alignment: .center, spacing: 6) {
                    PlatformLogo(platform: alert.platform, size: 18)

                    Text(alert.platform.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(spaceColor(alert.platform.color))

                    Text("·")
                        .foregroundStyle(Palette.muted)

                    Text(alert.account.name)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    // Category Badge
                    HStack(spacing: 3) {
                        Image(systemName: alert.categoryType.icon)
                            .font(.system(size: 8))
                        Text(alert.categoryType.rawValue)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(catColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(catColor)
                }

                // Middle Row: Title
                Text(alert.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Body Text / Snippet
                Text(alert.alertText)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.9) : Palette.muted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                // Bottom Row: Time & Direct Link Badge
                HStack(alignment: .center, spacing: 6) {
                    Text(alert.displayTime)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)

                    Spacer()

                    if let directURL = alert.directURL {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 9))
                            Text(directURL.host?.replacingOccurrences(of: "www.", with: "") ?? "Direct Link")
                                .font(.system(size: 9.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.card, lineWidth: 1))
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
            .padding(10)
            .background(isSelected ? Palette.accent.opacity(0.14) : Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Palette.accent : Palette.card, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - PANE 3: Right Live Reader & Portal
    private var inboxReaderPane: some View {
        VStack(spacing: 0) {
            if selectedFolder == .alerts {
                alertDetailPane
            } else if let item = selectedMessage {
                conversationDetailPane(item)
            } else {
                emptyReaderPane
            }
        }
    }

    private func conversationDetailPane(_ item: UnifiedMessageItem) -> some View {
        let platformColor = spaceColor(item.platform.color)
        let analysis = ConversationSummaryService.shared.analyzeMessage(item.message)

        return VStack(spacing: 0) {
            // Inspector Toolbar
            HStack(spacing: 12) {
                // Sender details
                HStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(avatarGradient(for: item.message.sender, colorName: item.platform.color))
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(initials(for: item.message.sender))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            )

                        PlatformLogo(platform: item.platform, size: 13)
                            .padding(1)
                            .background(Palette.panel, in: Circle())
                            .offset(x: 2, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.message.sender)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.primary)

                            Text("·")
                                .foregroundStyle(Palette.muted)

                            HStack(spacing: 4) {
                                Text(item.platform.name)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(platformColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(platformColor)

                            Text(item.accountName)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                        }

                        if let time = item.message.time, !time.isEmpty {
                            Text("Received \(time)")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 6) {
                    if let link = item.message.linkURL, !link.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link, forType: .string)
                            copiedNotice = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                copiedNotice = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedNotice ? "checkmark" : "link")
                                Text(copiedNotice ? "Copied" : "Copy Link")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Copy conversation link")
                    }

                    Button {
                        store.openInSplitView(platformID: item.platform.id, accountID: item.accountID)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "rectangle.split.2x1")
                            Text("Split View")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open platform in Split View alongside current task")

                    Button {
                        store.openPlatformInbox(accountID: item.accountID, messageURL: item.message.linkURL)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open in Tab")
                            Image(systemName: "arrow.up.forward.app")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(platformColor)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open in full platform tab")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Palette.panel)

            Divider()
                .background(Palette.border)

            // Intelligent Conversation Intelligence Briefing Bar
            VStack(alignment: .leading, spacing: 7) {
                // Top Context Line
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(platformColor)

                    Text("Conversation Briefing:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.primary)

                    Text(analysis.contextSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)

                    Spacer()

                    Text(analysis.detectedIntent)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(platformColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(platformColor.opacity(0.12), in: Capsule())
                }

                // Question Box if detected
                if let q = analysis.detectedQuestion {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .padding(.top, 1)

                        Text("Question: \"\(q)\"")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.orange)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }

                // Suggested Quick Replies Strip
                if !analysis.suggestedReplies.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Text("Quick Replies:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.muted)

                            ForEach(Array(analysis.suggestedReplies.enumerated()), id: \.offset) { idx, reply in
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(reply, forType: .string)
                                    copiedReplyIndex = idx
                                    store.showToast("Copied reply: \"\(reply.prefix(35))…\" — ready to paste into chat!")
                                    Task {
                                        try? await Task.sleep(for: .seconds(2))
                                        if copiedReplyIndex == idx {
                                            copiedReplyIndex = nil
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedReplyIndex == idx ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 8))
                                        Text(reply)
                                            .font(.system(size: 10))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(copiedReplyIndex == idx ? Color.green.opacity(0.2) : Palette.background, in: Capsule())
                                    .overlay(Capsule().stroke(copiedReplyIndex == idx ? Color.green : Palette.card, lineWidth: 1))
                                    .foregroundStyle(copiedReplyIndex == idx ? Color.green : Color.primary.opacity(0.85))
                                }
                                .buttonStyle(.plain)
                                .help("Click to copy this response to clipboard")
                            }
                        }
                    }
                    .padding(.top, 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(platformColor.opacity(0.06))

            Divider()
                .background(Palette.border)

            // Embedded Live Portal Web View
            PlatformPortalView(
                platformID: item.platform.id,
                explicitAccountID: item.accountID
            )
            .id("\(item.accountID):\(item.message.id)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var alertDetailPane: some View {
        let alert = selectedAlert

        return VStack(spacing: 0) {
            if let alert {
                let platformColor = spaceColor(alert.platform.color)
                let catColor = alert.categoryType.color

                // 1. Inspector Toolbar
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        PlatformLogo(platform: alert.platform, size: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(alert.title)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)

                                HStack(spacing: 3) {
                                    Image(systemName: alert.categoryType.icon)
                                        .font(.system(size: 8))
                                    Text(alert.categoryType.rawValue)
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(catColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(catColor)
                            }

                            HStack(spacing: 6) {
                                Text(alert.platform.name)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(platformColor)

                                Text("·")
                                    .foregroundStyle(Palette.muted)

                                Text(alert.account.name)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.muted)

                                Text("·")
                                    .foregroundStyle(Palette.muted)

                                Text(alert.displayTime)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                    }

                    Spacer()

                    // Action Buttons
                    HStack(spacing: 6) {
                        if let url = alert.directURL {
                            // Copy Link Button
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                copiedAlertURL = true
                                store.showToast("Direct notice URL copied!")
                                Task {
                                    try? await Task.sleep(for: .seconds(1.5))
                                    copiedAlertURL = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedAlertURL ? "checkmark" : "link")
                                    Text(copiedAlertURL ? "Copied" : "Copy Link")
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Copy exact notification URL")

                            // Open in Split View
                            Button {
                                store.openInSplitView(platformID: alert.platform.id, accountID: alert.account.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "rectangle.split.2x1")
                                    Text("Split View")
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Open platform in Split View alongside current task")

                            // Open in Browser
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Image(systemName: "safari")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Open direct link in external browser")

                            // Open Direct Link / Tab
                            Button {
                                store.openPlatformNotifications(accountID: alert.account.id, notificationURL: url.absoluteString)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Open Direct Link")
                                    Image(systemName: "arrow.up.forward.app")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(platformColor)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Open this notification in full platform view")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.panel)

                Divider()
                    .background(Palette.border)

                // 2. Alert Intelligence Briefing Banner
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: alert.categoryType.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(catColor)

                        Text("Alert Intelligence:")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.primary)

                        Text(alertContextAdvice(for: alert))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)

                        Spacer()

                        if let url = alert.directURL {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.system(size: 9))
                                Text(url.absoluteString)
                                    .font(.system(size: 9.5))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Palette.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(catColor.opacity(0.06))

                Divider()
                    .background(Palette.border)

                // 3. Embedded Live WebKit Portal pointing directly to Alert / Notifications URL
                PlatformPortalView(
                    platformID: alert.platform.id,
                    explicitAccountID: alert.account.id,
                    customURL: alert.directURL
                )
                .id("alert-portal-\(alert.account.id)-\(alert.directURL?.absoluteString ?? alert.id)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyReaderPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func alertContextAdvice(for alert: UnifiedAlertItem) -> String {
        switch alert.categoryType {
        case .mention:
            return "Direct mention detected. Review the post or comment thread below to respond."
        case .security:
            return "Security alert or login notification. Verify device and session details below."
        case .request:
            return "Connection or invite request. Review profile and accept or decline below."
        case .reaction:
            return "New engagement activity on your content. View reacting members below."
        case .reply:
            return "Thread reply or comment received. Continue the conversation directly below."
        case .stream, .all:
            return "Official live notification feed for \(alert.platform.name). Direct interaction available below."
        }
    }

    private var emptyReaderPane: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 40))
                .foregroundStyle(Palette.accent)

            VStack(spacing: 4) {
                Text("Select a Conversation")
                    .font(.system(size: 17, weight: .bold))
                Text("Choose a message from the list to view its full conversation and reply live right here.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            // Quick Platform Launchers
            if !activePlatformsWithAccounts.isEmpty {
                VStack(spacing: 8) {
                    Text("Or open a platform directly:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)

                    HStack(spacing: 8) {
                        ForEach(activePlatformsWithAccounts.prefix(4)) { platform in
                            if let acc = store.accounts(for: platform.id).first {
                                Button {
                                    store.openPlatformInbox(accountID: acc.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        PlatformLogo(platform: platform, size: 16)
                                        Text(platform.name)
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(spaceColor(platform.color).opacity(0.3), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var emptyStreamCard: some View {
        VStack(spacing: 14) {
            if !query.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.muted)
                Text("No messages match \"\(query)\"")
                    .font(.system(size: 13, weight: .semibold))
                Button("Clear Filter") {
                    searchQuery = ""
                    selectedIntentFilter = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 26))
                    .foregroundStyle(Palette.muted)
                Text("No messages in this view")
                    .font(.system(size: 13, weight: .semibold))
                Text("Switch to \"All Messages\" or connect your accounts to begin streaming.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
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
