import SwiftUI
import AppKit

private enum InboxFolder: String, CaseIterable {
    case unread = "Unread Messages"
    case alerts = "Alerts & Notices"
    case all = "All Messages"

    var icon: String {
        switch self {
        case .unread: return "tray.fill"
        case .alerts: return "bell.badge.fill"
        case .all: return "archivebox.fill"
        }
    }
}

private enum SummarySubTab: String, CaseIterable {
    case overview = "Briefing"
    case actions = "Action Items"
    case calendar = "Calendar"
    case threads = "Contacts"
}

struct UnifiedMessageItem: Identifiable, Equatable {
    var id: String { "\(accountID)-\(message.id)" }
    let accountID: UUID
    let accountName: String
    let platform: SocialPlatform
    let message: PlatformMessagePreview
    let snapshotDate: Date
    let isUnread: Bool
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
        case .all: return "bell"
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

private enum ConversationViewMode: String, CaseIterable {
    case stealth = "Stealth Peek"
    case live = "Live Portal"
}

struct InboxView: View {
    @EnvironmentObject private var store: AppStore

    // Navigation & Selection State (Defaults to Unread Messages ONLY)
    @State private var selectedFolder: InboxFolder = .unread
    @State private var selectedPlatformID: String? = nil // nil means "All Platforms"
    @State private var selectedMessageID: String? = nil
    @State private var selectedAlertID: String? = nil
    @State private var selectedAlertCategory: AlertCategoryType = .all

    // Stealth Mode & AI Assistant State
    @State private var conversationViewMode: ConversationViewMode = .stealth
    @State private var customPromptInput: String = ""
    @State private var isDraftingReply: Bool = false
    @State private var draftedReplyText: String? = nil
    @State private var selectedReplyTone: AIReplyTone = .professional
    @State private var selectedAIPriorityFilter: AIMessagePriority? = nil
    @State private var loginProviderItem: AILoginProviderItem? = nil
    @State private var coPilotInput: String = ""
    @State private var coPilotResponse: String? = nil
    @State private var isCoPilotThinking: Bool = false
    @State private var showTranslation: Bool = true

    // Cross-Platform Auto-Reply Queue & Alert Responder State
    @State private var isShowingAutoReplyQueue: Bool = false
    @State private var isGeneratingQueue: Bool = false
    @State private var autoReplyQueue: [AIAutoReplyItem] = []
    @State private var alertDraftedReply: String? = nil
    @State private var isDraftingAlertReply: Bool = false
    @State private var alertCustomPrompt: String = ""
    @State private var selectedAlertTone: AIReplyTone = .professional

    // Filter & Search State
    @State private var searchQuery: String = ""
    @State private var selectedIntentFilter: String? = nil
    @State private var isSummaryExpanded: Bool = false // Clean by default: compact 1-line strip
    @State private var summarySubTab: SummarySubTab = .overview
    @State private var completedActionItems: Set<String> = []
    @State private var isRefreshing: Bool = false
    @State private var isRegenerating: Bool = false
    @State private var showDailySummarySheet: Bool = false
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
            let accountUnread = snapshot?.unreadCount ?? 0

            if let snapshot, !snapshot.messages.isEmpty {
                for (idx, msg) in snapshot.messages.enumerated() {
                    let unread = msg.unread || (accountUnread > 0 && idx < accountUnread)
                    items.append(UnifiedMessageItem(
                        accountID: account.id,
                        accountName: account.name,
                        platform: platform,
                        message: msg,
                        snapshotDate: snapshot.updatedAt,
                        isUnread: unread
                    ))
                }
            }
        }
        return items
    }

    private var unreadUnifiedMessages: [UnifiedMessageItem] {
        allUnifiedMessages.filter { $0.isUnread }
    }

    private var filteredMessages: [UnifiedMessageItem] {
        let q = query.lowercased()
        let sourceList: [UnifiedMessageItem] = {
            switch selectedFolder {
            case .unread:
                return allUnifiedMessages.filter { $0.isUnread }
            case .all:
                return allUnifiedMessages
            case .alerts:
                return []
            }
        }()

        return sourceList.filter { item in
            // Platform filter
            if let selectedPlatformID, item.platform.id != selectedPlatformID {
                return false
            }
            // AI Priority filter
            if let priorityFilter = selectedAIPriorityFilter {
                let ai = AIService.shared.analyzeChat(
                    sender: item.message.sender,
                    messageText: item.message.text,
                    platformName: item.platform.name,
                    accountName: item.accountName,
                    preferences: store.preferences
                )
                if ai.aiPriority != priorityFilter {
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
                "Live stream of post impressions, connection requests, and profile views.",
                "stream"
            )
        case "x":
            return (
                "Notifications Hub",
                "Verified mentions, retweets, quotes, reposts, and alerts.",
                "mention"
            )
        case "whatsapp":
            return (
                "Security & Sync Notices",
                "Device link status, security encryption, and incoming group alerts.",
                "security"
            )
        case "discord":
            return (
                "Mentions & Inbox Hub",
                "Server @mentions, direct pings, unread thread activity, and notices.",
                "mention"
            )
        case "slack":
            return (
                "Mentions & Activity Feed",
                "Channel @mentions, workspace threads, emoji reactions, and bot updates.",
                "mention"
            )
        case "instagram":
            return (
                "Activity Feed",
                "Likes, comments, story tags, direct message requests, and followers.",
                "reaction"
            )
        case "facebook":
            return (
                "Notifications Center",
                "Friend requests, group notifications, post tags, and community notices.",
                "request"
            )
        case "reddit":
            return (
                "Notifications & Inbox",
                "Upvote milestones, post comment replies, and subreddit notices.",
                "reply"
            )
        case "threads":
            return (
                "Activity & Mentions",
                "Replies, quotes, reposts, and profile mentions across Threads.",
                "reply"
            )
        case "telegram":
            return (
                "Service Notices",
                "Login codes, channel broadcasts, and session security updates.",
                "security"
            )
        default:
            return (
                "Notifications Stream",
                "Direct gateway to notifications and live activity for \(platform.name).",
                "stream"
            )
        }
    }

    private var allAlerts: [UnifiedAlertItem] {
        var result: [UnifiedAlertItem] = []

        // 1. Live extracted notifications across accounts
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

        // 2. Official Notifications Hub for every connected account
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
            if let selectedPlatformID, alert.platform.id != selectedPlatformID {
                return false
            }
            if selectedAlertCategory != .all, alert.categoryType != selectedAlertCategory {
                return false
            }
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

    // MARK: - Body (Clean 3-Pane macOS Split)
    var body: some View {
        HStack(spacing: 0) {
            // PANE 1: Left Navigation Rail (Minimalist, Apple Mail style)
            inboxNavigatorPane
                .frame(width: 220)
                .background(Palette.sidebar)

            Divider()
                .background(Palette.border)

            // PANE 2: Center Message Stream (Linear / Superhuman style)
            inboxMessageStreamPane
                .frame(width: 370)
                .background(Palette.panel)

            Divider()
                .background(Palette.border)

            // PANE 3: Right Live Reader & Portal (Edge-to-edge)
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
            conversationViewMode = store.preferences.stealthModeDefault ? .stealth : .live
        }
        .onChange(of: selectedMessageID) { _, _ in
            conversationViewMode = store.preferences.stealthModeDefault ? .stealth : .live
            draftedReplyText = nil
            customPromptInput = ""
            coPilotResponse = nil
            coPilotInput = ""
        }
        .onChange(of: selectedAlertID) { _, _ in
            alertDraftedReply = nil
            alertCustomPrompt = ""
        }
        .sheet(item: $loginProviderItem) { item in
            AILoginWebSheet(provider: item.id)
        }
        .sheet(isPresented: $isShowingAutoReplyQueue) {
            autoReplyQueueSheet
        }
    }

    // MARK: - PANE 1: Left Navigator Rail
    private var inboxNavigatorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clean Header
            HStack(spacing: 8) {
                Image(systemName: "tray.2.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.accent)

                Text("Inbox")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.primary)

                Spacer()

                let totalUnread = max(unreadUnifiedMessages.count, store.totalUnreadCount)
                if totalUnread > 0 {
                    Text("\(totalUnread)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Smart Folders (Unread is primary!)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VIEWS")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.muted.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 4)

                        let unreadCount = max(unreadUnifiedMessages.count, store.totalUnreadCount)
                        folderRow(folder: .unread, count: unreadCount, isBadgeBlue: true)
                        folderRow(folder: .alerts, count: allAlerts.count)
                        folderRow(folder: .all, count: allUnifiedMessages.count)
                    }

                    // Connected Platforms Section
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("PLATFORMS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.muted.opacity(0.7))
                            Spacer()
                            Text("\(activePlatformsWithAccounts.count)")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted.opacity(0.6))
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)

                        // All Platforms item
                        let totalUnread = max(unreadUnifiedMessages.count, store.totalUnreadCount)
                        platformRow(
                            name: "All Inboxes",
                            platform: nil,
                            symbol: "square.stack.3d.up.fill",
                            platformID: nil,
                            unread: totalUnread,
                            total: allUnifiedMessages.count
                        )

                        // Per-platform rows
                        ForEach(activePlatformsWithAccounts) { platform in
                            let msgs = allUnifiedMessages.filter { $0.platform.id == platform.id }
                            let platformUnread = msgs.filter { $0.isUnread }.count
                            let rawStoreUnread = store.accounts(for: platform.id).compactMap { store.platformActivity[$0.id]?.unreadCount }.reduce(0, +)
                            let unreadDisplay = max(platformUnread, rawStoreUnread)

                            platformRow(
                                name: platform.name,
                                platform: platform,
                                symbol: "circle",
                                platformID: platform.id,
                                unread: unreadDisplay,
                                total: msgs.count
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer(minLength: 0)

            // Minimalist Bottom Status Bar
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)

                Text("Portals Active")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)

                Spacer()

                Button {
                    isRefreshing = true
                    store.refreshAllPortals()
                    store.refreshSummaries()
                    store.showToast("Inboxes synchronized")
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.plain)
                .help("Sync inboxes & wake portals")

                Button {
                    isRegenerating = true
                    store.refreshSummaries()
                    store.showToast("AI Briefing refreshed")
                    Task {
                        try? await Task.sleep(for: .seconds(0.4))
                        isRegenerating = false
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .help("Regenerate AI summaries")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Palette.sidebar)
            .overlay(Divider().background(Palette.border), alignment: .top)
        }
    }

    private func folderRow(folder: InboxFolder, count: Int, isBadgeBlue: Bool = false) -> some View {
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
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.muted)
                    .frame(width: 16)

                Text(folder.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Palette.muted)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isBadgeBlue && count > 0 ? .white : Palette.muted.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(isBadgeBlue && count > 0 ? Color.blue : Palette.card.opacity(0.6), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Palette.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func platformRow(
        name: String,
        platform: SocialPlatform?,
        symbol: String,
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
                    PlatformLogo(platform: platform, size: 15)
                        .frame(width: 16)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 16)
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
                        .padding(.vertical, 1)
                        .background(Color.blue, in: Capsule())
                } else if total > 0 && selectedFolder == .all {
                    Text("\(total)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Palette.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - PANE 2: Message Stream (Linear / Apple Mail style)
    private var inboxMessageStreamPane: some View {
        VStack(spacing: 0) {
            // Top AI Intelligence Bar
            aiIntelligenceHeaderBar

            Divider()
                .background(Palette.border)

            // Search Bar & AI Triage Filter Chips
            VStack(spacing: 8) {
                // Integrated Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)

                    TextField("Search messages, senders, topics…", text: $searchQuery)
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
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))

                // AI Triage Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        aiTriageChip(title: "All", priority: nil)
                        aiTriageChip(title: "🔥 Urgent", priority: .urgent)
                        aiTriageChip(title: "📅 Meetings", priority: .meeting)
                        aiTriageChip(title: "❓ Questions", priority: .question)
                        aiTriageChip(title: "📝 Tasks", priority: .review)
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Palette.panel)

            Divider()
                .background(Palette.border)

            if selectedFolder == .alerts {
                // Alerts & Notices Mode
                alertsStreamView
            } else {
                // Regular Messages Stream
                VStack(spacing: 0) {
                    // Sleek AI Executive Briefing Strip (Collapsible)
                    compactAIBriefingBanner

                    // Stream Counter Subheader
                    HStack {
                        let headerTitle: String = {
                            if selectedFolder == .unread {
                                return "\(filteredMessages.count) UNREAD MESSAGE\(filteredMessages.count == 1 ? "" : "S")"
                            } else {
                                return "\(filteredMessages.count) CONVERSATION\(filteredMessages.count == 1 ? "" : "S")"
                            }
                        }()

                        Text(headerTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.muted.opacity(0.7))

                        Spacer()

                        if let platformID = selectedPlatformID, let platform = store.platform(platformID) {
                            HStack(spacing: 4) {
                                PlatformLogo(platform: platform, size: 11)
                                Text(platform.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(spaceColor(platform.color))
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Palette.panel)

                    Divider()
                        .background(Palette.border.opacity(0.5))

                    // Message Rows
                    if filteredMessages.isEmpty {
                        emptyStreamCard
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(filteredMessages) { item in
                                    cleanMessageRow(item)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Compact AI Briefing Banner
    private var compactAIBriefingBanner: some View {
        let summary = currentSummary ?? ConversationSummaryService.shared.generateExecutiveBriefing(
            platforms: activePlatformsWithAccounts,
            accounts: store.platformAccounts,
            activity: store.platformActivity
        )

        return VStack(spacing: 0) {
            // 1-Line Sleek Compact Header
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isSummaryExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)

                    Text(summary.headline)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.9))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if !summary.actionItems.isEmpty {
                        Text("\(summary.actionItems.count) actions")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }

                    Image(systemName: isSummaryExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Palette.accent.opacity(0.06))
            }
            .buttonStyle(.plain)

            // Expanded Briefing View (Only when user expands it)
            if isSummaryExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Subtab Selector
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
                                    }
                                    if tab == .calendar {
                                        let calCount = unreadUnifiedMessages.filter { msg in
                                            AIService.shared.extractCalendarEvent(sender: msg.message.sender, messageText: msg.message.text, platformName: msg.platform.name) != nil
                                        }.count
                                        if calCount > 0 {
                                            Text("\(calCount)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.purple, in: Capsule())
                                        }
                                    }
                                }
                                .font(.system(size: 10, weight: summarySubTab == tab ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(summarySubTab == tab ? Palette.card : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                                .foregroundStyle(summarySubTab == tab ? Color.primary : Palette.muted)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Button {
                            isRegenerating = true
                            store.refreshSummaries()
                            Task {
                                try? await Task.sleep(for: .seconds(0.4))
                                isRegenerating = false
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.muted)
                                .rotationEffect(.degrees(isRegenerating ? 360 : 0))
                                .animation(isRegenerating ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRegenerating)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh summary")
                    }

                    // Tab Content
                    switch summarySubTab {
                    case .overview:
                        VStack(alignment: .leading, spacing: 6) {
                            Text(summary.executiveOverview)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.85))
                                .lineSpacing(2)

                            if !summary.keyTopics.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(summary.keyTopics.prefix(4), id: \.self) { topic in
                                        Text(topic)
                                            .font(.system(size: 9, weight: .medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Palette.accent.opacity(0.1), in: Capsule())
                                            .foregroundStyle(Palette.accent)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }

                    case .actions:
                        VStack(alignment: .leading, spacing: 4) {
                            if summary.actionItems.isEmpty {
                                Text("No pending action items.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.muted)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(summary.actionItems, id: \.self) { action in
                                    let isDone = completedActionItems.contains(action)
                                    Button {
                                        if isDone {
                                            completedActionItems.remove(action)
                                        } else {
                                            completedActionItems.insert(action)
                                        }
                                    } label: {
                                        HStack(spacing: 7) {
                                            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 11))
                                                .foregroundStyle(isDone ? Color.green : Color.orange)

                                            Text(action)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(isDone ? Palette.muted : Color.primary)
                                                .strikethrough(isDone)
                                                .lineLimit(1)

                                            Spacer()
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                    case .calendar:
                        let events: [(item: UnifiedMessageItem, event: AICalendarEvent)] = unreadUnifiedMessages.compactMap { msg in
                            if let ev = AIService.shared.extractCalendarEvent(sender: msg.message.sender, messageText: msg.message.text, platformName: msg.platform.name) {
                                return (item: msg, event: ev)
                            }
                            return nil
                        }

                        if events.isEmpty {
                            Text("No meetings detected in unread messages.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.muted)
                                .padding(.vertical, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(events, id: \.item.id) { pair in
                                    HStack(spacing: 7) {
                                        Image(systemName: "calendar.badge.clock")
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(Color.purple)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(pair.event.title)
                                                .font(.system(size: 10.5, weight: .semibold))
                                                .lineLimit(1)
                                            Text("\(pair.event.dateSuggestion) · \(pair.event.startTime ?? "") · \(pair.event.locationOrLink ?? "")")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(Palette.muted)
                                        }

                                        Spacer()

                                        Button {
                                            AIService.shared.openInAppleCalendar(event: pair.event, store: store)
                                        } label: {
                                            Text("Add to Cal")
                                                .font(.system(size: 9.5, weight: .semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                    case .threads:
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(summary.threads.prefix(3)) { thread in
                                HStack(spacing: 6) {
                                    Text(thread.sender)
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Text("·")
                                        .foregroundStyle(Palette.muted)
                                    Text(thread.contextSummary)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Palette.muted)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Palette.panel)
                .overlay(Divider().background(Palette.border), alignment: .bottom)
            }

            Divider()
                .background(Palette.border)
        }
    }

    // MARK: - Top AI Intelligence Bar
    private var aiIntelligenceHeaderBar: some View {
        let isGemini = store.preferences.aiProvider == "gemini"
        let isChatGpt = store.preferences.aiProvider == "chatgpt"
        let activeLoggedIn = isGemini ? store.preferences.isGeminiLoggedIn : store.preferences.isChatGptLoggedIn

        return HStack(spacing: 6) {
            // Gemini Toggle
            Button {
                store.preferences.aiProvider = "gemini"
                if !store.preferences.isGeminiLoggedIn {
                    loginProviderItem = AILoginProviderItem(id: "gemini")
                } else {
                    store.showToast("Active AI: Google Gemini")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("Gemini")
                        .font(.system(size: 11, weight: isGemini ? .bold : .medium))
                    if store.preferences.isGeminiLoggedIn {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isGemini ? Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.18) : Palette.card.opacity(0.5),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        isGemini ? Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isGemini ? Color(red: 0.26, green: 0.52, blue: 0.96) : Palette.muted)
            }
            .buttonStyle(.plain)

            // ChatGPT Toggle
            Button {
                store.preferences.aiProvider = "chatgpt"
                if !store.preferences.isChatGptLoggedIn {
                    loginProviderItem = AILoginProviderItem(id: "chatgpt")
                } else {
                    store.showToast("Active AI: OpenAI ChatGPT")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("ChatGPT")
                        .font(.system(size: 11, weight: isChatGpt ? .bold : .medium))
                    if store.preferences.isChatGptLoggedIn {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isChatGpt ? Color(red: 0.06, green: 0.65, blue: 0.53).opacity(0.18) : Palette.card.opacity(0.5),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        isChatGpt ? Color(red: 0.06, green: 0.65, blue: 0.53).opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isChatGpt ? Color(red: 0.06, green: 0.65, blue: 0.53) : Palette.muted)
            }
            .buttonStyle(.plain)

            // Batch Auto-Reply Trigger
            Button {
                generateQueue()
            } label: {
                HStack(spacing: 4) {
                    if isGeneratingQueue {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text("Draft All")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Color.purple.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(Color.purple.opacity(0.5), lineWidth: 1))
                .foregroundStyle(Color.purple)
            }
            .buttonStyle(.plain)
            .disabled(isGeneratingQueue)
            .help("AI reads all unread messages and alerts and drafts replies in a review queue")

            Spacer()

            // Account Login / Status Button
            Button {
                loginProviderItem = AILoginProviderItem(id: store.preferences.aiProvider)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: activeLoggedIn ? "person.crop.circle.badge.checkmark" : "arrow.right.square")
                        .font(.system(size: 9.5))
                    Text(activeLoggedIn ? "Connected" : "Log In")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(activeLoggedIn ? Color.green.opacity(0.12) : Palette.accent.opacity(0.12), in: Capsule())
                .foregroundStyle(activeLoggedIn ? Color.green : Palette.accent)
            }
            .buttonStyle(.plain)
            .help("Open Web Account Login for \(store.preferences.aiProvider == "gemini" ? "Google Gemini" : "ChatGPT")")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Palette.panel)
    }

    private func aiTriageChip(title: String, priority: AIMessagePriority?) -> some View {
        let isSelected = selectedAIPriorityFilter == priority

        return Button {
            selectedAIPriorityFilter = isSelected ? nil : priority
            selectedMessageID = filteredMessages.first?.id
        } label: {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(isSelected ? Palette.accent.opacity(0.18) : Palette.card.opacity(0.5), in: Capsule())
                .foregroundStyle(isSelected ? Palette.accent : Palette.muted)
        }
        .buttonStyle(.plain)
    }

    private func priorityColor(_ priority: AIMessagePriority) -> Color {
        switch priority {
        case .urgent: return Color.red
        case .question: return Color.orange
        case .meeting: return Color.purple
        case .review: return Color.blue
        case .normal: return Color.gray
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
                .padding(.vertical, 3.5)
                .background(isSelected ? Palette.accent.opacity(0.18) : Palette.card.opacity(0.5), in: Capsule())
                .foregroundStyle(isSelected ? Palette.accent : Palette.muted)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clean Message Row (Apple Mail / Linear style with AI Priority)
    private func cleanMessageRow(_ item: UnifiedMessageItem) -> some View {
        let isSelected = selectedMessageID == item.id
        let aiResult = AIService.shared.analyzeChat(
            sender: item.message.sender,
            messageText: item.message.text,
            platformName: item.platform.name,
            accountName: item.accountName,
            preferences: store.preferences
        )

        return Button {
            selectedMessageID = item.id
        } label: {
            HStack(alignment: .top, spacing: 9) {
                // Unread Indicator or subtle spacer
                ZStack {
                    if item.isUnread {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: 6, height: 28)

                // Avatar with tiny platform logo
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(avatarGradient(for: item.message.sender, colorName: item.platform.color))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Text(initials(for: item.message.sender))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        )

                    PlatformLogo(platform: item.platform, size: 10)
                        .padding(0.5)
                        .background(Palette.panel, in: Circle())
                        .offset(x: 2, y: 2)
                }

                // Message Text & Metadata
                VStack(alignment: .leading, spacing: 3) {
                    // Line 1: Sender + Platform + Time
                    HStack(spacing: 5) {
                        Text(item.message.sender)
                            .font(.system(size: 12, weight: isSelected ? .bold : .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        Text("·")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted.opacity(0.6))

                        Text(item.platform.name)
                            .font(.system(size: 10))
                            .foregroundStyle(spaceColor(item.platform.color))

                        Spacer()

                        if let time = item.message.time, !time.isEmpty {
                            Text(time)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted.opacity(0.8))
                        }
                    }

                    // Line 2: AI Priority Pill + Preview Snippet
                    HStack(spacing: 5) {
                        if aiResult.aiPriority != .normal {
                            HStack(spacing: 3) {
                                Image(systemName: aiResult.aiPriority.icon)
                                    .font(.system(size: 8))
                                Text(aiResult.aiPriority.shortTag)
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(priorityColor(aiResult.aiPriority))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(priorityColor(aiResult.aiPriority).opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        }

                        Text(item.message.text)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? Color.primary.opacity(0.9) : Palette.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    // Line 3: If question or meeting detected, show micro callout
                    if let q = aiResult.detectedQuestion {
                        Text("❓ \"\(q)\"")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.orange)
                            .lineLimit(1)
                    } else if let cal = aiResult.detectedCalendarEvent {
                        Text("📅 \(cal.dateSuggestion) · \(cal.startTime ?? "")")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.purple)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                isSelected ? Palette.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Alerts Stream View (Clean & Compact)
    private var alertsStreamView: some View {
        VStack(spacing: 0) {
            // Category Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(AlertCategoryType.allCases, id: \.self) { cat in
                        let isSelected = selectedAlertCategory == cat
                        Button {
                            selectedAlertCategory = cat
                            selectedAlertID = filteredAlerts.first?.id
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 8.5))
                                Text(cat.rawValue)
                                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(isSelected ? cat.color.opacity(0.18) : Palette.card.opacity(0.5), in: Capsule())
                            .foregroundStyle(isSelected ? cat.color : Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Palette.panel)

            Divider()
                .background(Palette.border)

            // Alert List
            if filteredAlerts.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bell.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.muted)
                    Text("No Alerts in this category")
                        .font(.system(size: 12, weight: .semibold))
                    Text("You're all caught up with notifications.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredAlerts) { alert in
                            cleanAlertRow(alert)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
            }
        }
    }

    private func cleanAlertRow(_ alert: UnifiedAlertItem) -> some View {
        let isSelected = selectedAlert?.id == alert.id
        let catColor = alert.categoryType.color

        return Button {
            selectedAlertID = alert.id
        } label: {
            HStack(alignment: .top, spacing: 9) {
                // Category Icon circle
                ZStack {
                    Circle()
                        .fill(catColor.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: alert.categoryType.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(catColor)
                }

                // Alert details
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(alert.platform.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(spaceColor(alert.platform.color))

                        Text("·")
                            .foregroundStyle(Palette.muted.opacity(0.6))

                        Text(alert.categoryType.rawValue)
                            .font(.system(size: 9.5))
                            .foregroundStyle(catColor)

                        Spacer()

                        Text(alert.displayTime)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.muted.opacity(0.8))
                    }

                    Text(alert.title)
                        .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    Text(alert.alertText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.85) : Palette.muted)
                        .lineLimit(2)

                    if let directURL = alert.directURL {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 8))
                            Text(directURL.host?.replacingOccurrences(of: "www.", with: "") ?? "Direct Link")
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 1)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                isSelected ? Palette.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - PANE 3: Reader & Live Portal
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

        return VStack(spacing: 0) {
            // Contextual Conversation Header (64px)
            HStack(spacing: 12) {
                // Sender Avatar
                Circle()
                    .fill(avatarGradient(for: item.message.sender, colorName: item.platform.color))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(initials(for: item.message.sender))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    )

                // Sender Info (Name 15–16px bold + Subtitle: 🟢 Online · Platform · 🔒 End-to-end encrypted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.message.sender)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Online")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Color.green)

                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted.opacity(0.6))

                        HStack(spacing: 3.5) {
                            PlatformLogo(platform: item.platform, size: 11)
                            Text(item.platform.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(platformColor)
                        }

                        Text("·")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted.opacity(0.6))

                        HStack(spacing: 3.5) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9.5))
                            Text("End-to-end encrypted")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Palette.muted)
                    }
                }

                Spacer()

                // Action Controls: [ 🕶️ Stealth | 🌐 Live Chat ] | [ ✦ Chat Insights ] | 📞 Audio call | 🎥 Video call | ⋮ More options
                HStack(spacing: 8) {
                    // 1-Click Stealth Peek vs Live Portal Toggle
                    HStack(spacing: 2) {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                conversationViewMode = .stealth
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.slash.fill")
                                    .font(.system(size: 10))
                                Text("Stealth")
                                    .font(.system(size: 11, weight: conversationViewMode == .stealth ? .semibold : .medium))
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(conversationViewMode == .stealth ? Color.green.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(conversationViewMode == .stealth ? Color.green : Palette.muted)
                        }
                        .buttonStyle(.plain)
                        .help("Incognito reading: zero read receipts or blue ticks")

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                conversationViewMode = .live
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                Text("Live Chat")
                                    .font(.system(size: 11, weight: conversationViewMode == .live ? .semibold : .medium))
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 28)
                            .background(conversationViewMode == .live ? platformColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(conversationViewMode == .live ? platformColor : Palette.muted)
                        }
                        .buttonStyle(.plain)
                        .help("Open interactive web portal to reply live")
                    }
                    .padding(3)
                    .background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))

                    // Chat Insights Button
                    Button {
                        showDailySummarySheet.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Chat Insights")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Palette.accent.opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(Palette.accent.opacity(0.35), lineWidth: 1))
                        .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("AI Chat Insights & Daily Conversation Summary")
                    .popover(isPresented: $showDailySummarySheet, arrowEdge: .bottom) {
                        let threadMessages = store.platformActivity[item.accountID]?.messages.filter {
                            $0.sender.lowercased() == item.message.sender.lowercased()
                        } ?? [item.message]
                        let aiResult = AIService.shared.analyzeChat(
                            sender: item.message.sender,
                            messageText: item.message.text,
                            platformName: item.platform.name,
                            accountName: item.accountName,
                            preferences: store.preferences,
                            threadMessages: threadMessages
                        )
                        ScrollView {
                            dailyConversationSummaryCard(summary: aiResult.dailySummary, item: item, platformColor: platformColor)
                                .padding(16)
                        }
                        .frame(width: 480, height: 440)
                    }

                    // Calling Controls (Platform-Aware)
                    let supportsCalling = item.platform.id.lowercased() == "whatsapp" || item.platform.id.lowercased() == "discord"

                    // Audio Call (📞)
                    Button {
                        if supportsCalling {
                            store.showToast("Initiating audio call with \(item.message.sender) via \(item.platform.name)…")
                            store.openPlatformInbox(accountID: item.accountID, messageURL: item.message.linkURL)
                        } else {
                            store.showToast("Voice calling not supported on \(item.platform.name) Web.")
                        }
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(supportsCalling ? Color.primary.opacity(0.85) : Palette.muted.opacity(0.6))
                            .frame(width: 34, height: 34)
                            .background(Palette.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(supportsCalling ? "Audio call on \(item.platform.name)" : "Voice calling not supported on \(item.platform.name) Web")

                    // Video Call (🎥)
                    Button {
                        if supportsCalling {
                            store.showToast("Initiating video call with \(item.message.sender) via \(item.platform.name)…")
                            store.openPlatformInbox(accountID: item.accountID, messageURL: item.message.linkURL)
                        } else {
                            store.showToast("Video calling not supported on \(item.platform.name) Web.")
                        }
                    } label: {
                        Image(systemName: "video.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(supportsCalling ? Color.primary.opacity(0.85) : Palette.muted.opacity(0.6))
                            .frame(width: 34, height: 34)
                            .background(Palette.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(supportsCalling ? "Video call on \(item.platform.name)" : "Video calling not supported on \(item.platform.name) Web")

                    // More Options (⋮)
                    Menu {
                        Section("Reading Mode") {
                            Button {
                                conversationViewMode = .stealth
                            } label: {
                                Label("Stealth AI Peek (Incognito)", systemImage: conversationViewMode == .stealth ? "checkmark.circle.fill" : "eye.slash")
                            }
                            Button {
                                conversationViewMode = .live
                            } label: {
                                Label("Live Interactive Portal", systemImage: conversationViewMode == .live ? "checkmark.circle.fill" : "globe")
                            }
                        }

                        Divider()

                        Section("Actions") {
                            Button {
                                store.openInSplitView(platformID: item.platform.id, accountID: item.accountID)
                            } label: {
                                Label("Open in Split View", systemImage: "rectangle.split.2x1")
                            }

                            Button {
                                store.openPlatformInbox(accountID: item.accountID, messageURL: item.message.linkURL)
                            } label: {
                                Label("Open in Full Tab", systemImage: "arrow.up.forward.app")
                            }

                            if let link = item.message.linkURL, !link.isEmpty {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(link, forType: .string)
                                    store.showToast("Copied conversation link")
                                } label: {
                                    Label("Copy Conversation Link", systemImage: "link")
                                }
                            }

                            Button {
                                store.refreshAllPortals()
                            } label: {
                                Label("Refresh Portal", systemImage: "arrow.clockwise")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .frame(width: 34, height: 34)
                            .background(Palette.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 34, height: 34)
                    .help("More conversation options")
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 64)
            .background(Palette.panel)

            Divider()
                .background(Palette.border)

            if conversationViewMode == .stealth {
                stealthConversationView(item: item, platformColor: platformColor)
            } else {
                livePortalConversationView(item: item, platformColor: platformColor)
            }
        }
    }

    private func stealthConversationView(item: UnifiedMessageItem, platformColor: Color) -> some View {
        let threadMessages = store.platformActivity[item.accountID]?.messages.filter {
            $0.sender.lowercased() == item.message.sender.lowercased()
        } ?? [item.message]

        let aiResult = AIService.shared.analyzeChat(
            sender: item.message.sender,
            messageText: item.message.text,
            platformName: item.platform.name,
            accountName: item.accountName,
            preferences: store.preferences,
            threadMessages: threadMessages
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Stealth / Ghost Reading Privacy Shield Banner
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Stealth Ghost Reading Active")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.primary)
                            Text("100% Incognito")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundStyle(Color.green)
                        }
                        Text("You can read, analyze, and draft responses safely. No read receipts, 'Seen' status, or blue checkmarks are sent to \(item.message.sender).")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                    }

                    Spacer()

                    Button {
                        conversationViewMode = .live
                    } label: {
                        HStack(spacing: 4) {
                            Text("Open Live Portal")
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.2), lineWidth: 1))

                // 1b. Daily Conversation Summary Card (AI Synthesized)
                dailyConversationSummaryCard(summary: aiResult.dailySummary, item: item, platformColor: platformColor)

                // 2. Incoming Message Transcript Card (Stealth Thread View)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "message.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(platformColor)
                            Text(threadMessages.count > 1 ? "Stealth Conversation Thread (\(threadMessages.count) Messages)" : "Intercepted Message Preview")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.muted)
                                .textCase(.uppercase)
                        }

                        Spacer()

                        if let time = item.message.time, !time.isEmpty {
                            Text(time)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                        }

                        Button {
                            let fullText = threadMessages.map { "\($0.sender) (\($0.time ?? "recent")):\n\($0.text)" }.joined(separator: "\n\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(fullText, forType: .string)
                            store.showToast("Conversation thread copied to clipboard")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text(threadMessages.count > 1 ? "Copy Thread" : "Copy")
                            }
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }

                    if threadMessages.count > 1 {
                        VStack(spacing: 8) {
                            ForEach(threadMessages) { msg in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(msg.sender)
                                            .font(.system(size: 11.5, weight: .bold))
                                            .foregroundStyle(platformColor)
                                        Spacer()
                                        if let t = msg.time {
                                            Text(t)
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(Palette.muted)
                                        }
                                    }
                                    Text(msg.text)
                                        .font(.system(size: 13.5))
                                        .lineSpacing(4)
                                        .foregroundStyle(Color.primary)
                                        .textSelection(.enabled)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))
                            }
                        }
                    } else {
                        Text(item.message.text)
                            .font(.system(size: 14.5))
                            .lineSpacing(5)
                            .foregroundStyle(Color.primary)
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.card, lineWidth: 1))
                    }
                }

                // 2b. Inline Language Translation (if foreign language detected)
                if let lang = aiResult.detectedLanguage, let trans = aiResult.translatedText {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: "character.bubble.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.teal)
                                Text("Inline Translation (\(lang) ➔ English)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .textCase(.uppercase)
                            }
                            Spacer()
                            Button(showTranslation ? "Hide Translation" : "Show Translation") {
                                showTranslation.toggle()
                            }
                            .font(.system(size: 10.5))
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.accent)
                        }
                        if showTranslation {
                            Text(trans)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.primary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.teal.opacity(0.2), lineWidth: 1))
                        }
                    }
                    .padding(14)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.card, lineWidth: 1))
                }

                // 2c. Detected Calendar Event Card (if meeting/schedule detected)
                if let event = aiResult.detectedCalendarEvent {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Color.purple)
                                Text("Detected Meeting & Schedule")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .textCase(.uppercase)
                            }
                            Spacer()
                            Text("AI Extracted")
                                .font(.system(size: 9.5, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.purple)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.primary)

                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.muted)
                                    Text("\(event.dateSuggestion) · \(event.startTime ?? "2:00 PM")")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Palette.muted)
                                }

                                if let loc = event.locationOrLink {
                                    HStack(spacing: 4) {
                                        Image(systemName: "video.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.muted)
                                        Text(loc)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Palette.muted)
                                    }
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                AIService.shared.openInAppleCalendar(event: event, store: store)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "calendar.badge.plus")
                                    Text("Add to Apple Calendar")
                                }
                                .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.purple)
                            .controlSize(.small)

                            Button {
                                let invite = "\(event.title)\nDate: \(event.dateSuggestion) at \(event.startTime ?? "2:00 PM")\nLocation: \(event.locationOrLink ?? "Video Call")"
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(invite, forType: .string)
                                store.showToast("Copied meeting invite")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy Details")
                                }
                                .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(14)
                    .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.25), lineWidth: 1))
                }

                // 3. AI Deep Analysis Deck
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Palette.accent)
                            Text("AI Thread Analysis")
                                .font(.system(size: 13, weight: .bold))
                        }

                        Spacer()

                        Text(aiResult.providerName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Palette.accent.opacity(0.12), in: Capsule())
                    }

                    // Key Badges
                    HStack(spacing: 8) {
                        Text(aiResult.detectedIntent)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Palette.card, in: Capsule())
                            .foregroundStyle(Color.primary)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(aiResult.urgency == .high ? Color.red : (aiResult.urgency == .medium ? Color.orange : Color.blue))
                                .frame(width: 6, height: 6)
                            Text(aiResult.urgency.rawValue)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(aiResult.urgency == .high ? Color.red : (aiResult.urgency == .medium ? Color.orange : Color.blue))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background((aiResult.urgency == .high ? Color.red : (aiResult.urgency == .medium ? Color.orange : Color.blue)).opacity(0.12), in: Capsule())

                        Text(aiResult.sentiment)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Palette.card.opacity(0.6), in: Capsule())
                    }

                    // Context Summary
                    Text(aiResult.contextSummary)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.95))
                        .padding(.vertical, 2)

                    // Detected Question (if any)
                    if let q = aiResult.detectedQuestion {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Awaiting Response to Question:")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .textCase(.uppercase)
                                Text("\"\(q)\"")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Color.primary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Action Item (if any)
                    if let action = aiResult.actionItem {
                        HStack(spacing: 8) {
                            Image(systemName: "checklist")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Palette.accent)
                            Text(action)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(Color.primary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.card, lineWidth: 1))

                // 4. AI Smart Reply Studio
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.and.outline")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Palette.accent)
                            Text("Smart Reply Studio")
                                .font(.system(size: 13, weight: .bold))
                        }

                        Spacer()

                        // Tone Selector
                        HStack(spacing: 4) {
                            ForEach(AIReplyTone.allCases) { tone in
                                Button {
                                    selectedReplyTone = tone
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: tone.symbol)
                                            .font(.system(size: 9))
                                        Text(tone.rawValue)
                                            .font(.system(size: 10.5, weight: selectedReplyTone == tone ? .semibold : .regular))
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(selectedReplyTone == tone ? Palette.accent : Palette.card, in: Capsule())
                                    .foregroundStyle(selectedReplyTone == tone ? .white : Palette.muted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Contextual Suggestions for Selected Tone
                    let toneReplies = aiResult.replies.filter { $0.tone == selectedReplyTone }
                    let displayedReplies = toneReplies.isEmpty ? aiResult.replies : toneReplies

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(displayedReplies) { replyOption in
                            HStack(spacing: 10) {
                                Image(systemName: "bubble.left.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.accent)

                                Text(replyOption.text)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)

                                Spacer()

                                HStack(spacing: 6) {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(replyOption.text, forType: .string)
                                        store.showToast("Copied reply to clipboard!")
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "doc.on.doc")
                                            Text("Copy")
                                        }
                                        .font(.system(size: 10.5, weight: .medium))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(Palette.muted)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(replyOption.text, forType: .string)
                                        conversationViewMode = .live
                                        store.showToast("Copied reply! Switched to Live Portal — paste to send.")
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "paperplane.fill")
                                            Text("Use in Chat")
                                        }
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(platformColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(platformColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                            .background(Palette.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))
                        }
                    }

                    Divider()

                    // Draft Custom Reply on Demand
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Draft Custom Reply with AI")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Palette.muted)

                        HStack(spacing: 8) {
                            TextField("Ask Gemini/ChatGPT (e.g. tell them I can meet tomorrow 4pm instead)...", text: $customPromptInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .onSubmit { triggerCustomDraft(item: item) }

                            Button {
                                triggerCustomDraft(item: item)
                            } label: {
                                HStack(spacing: 4) {
                                    if isDraftingReply {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text("Draft")
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.accent)
                            .controlSize(.small)
                            .disabled(customPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDraftingReply)
                        }

                        // Generated Draft Box
                        if let draft = draftedReplyText {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Drafted Response:")
                                        .font(.system(size: 10.5, weight: .bold))
                                        .foregroundStyle(Palette.accent)
                                        .textCase(.uppercase)
                                    Spacer()
                                }

                                Text(draft)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.primary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Palette.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))

                                HStack(spacing: 8) {
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(draft, forType: .string)
                                        store.showToast("Draft copied to clipboard!")
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "doc.on.doc")
                                            Text("Copy to Clipboard")
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(draft, forType: .string)
                                        conversationViewMode = .live
                                        store.showToast("Copied draft! Switched to Live Portal — paste & send.")
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "paperplane.fill")
                                            Text("Insert into Chat & Open Live Portal")
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(platformColor)
                                    .controlSize(.small)
                                }
                            }
                            .padding(12)
                            .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.accent.opacity(0.3), lineWidth: 1))
                        }
                    }
                }
                // 5. Interactive AI Thread Co-Pilot
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.sparkles")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Palette.accent)
                            Text("AI Thread Co-Pilot")
                                .font(.system(size: 13, weight: .bold))
                        }

                        Spacer()

                        let providerLabel = store.preferences.aiProvider == "gemini" ? "Google Gemini" : "OpenAI ChatGPT"
                        Text("Powered by \(providerLabel)")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Palette.accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(Palette.accent)
                    }

                    Text("Ask questions or draft actions regarding this chat using your connected AI account:")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)

                    // Quick Action Prompts
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            coPilotPromptPill(title: "⚡ 3-Bullet Summary", prompt: "Summarize this message in 3 clear bullet points", item: item)
                            coPilotPromptPill(title: "📝 Polite Decline", prompt: "Draft a polite and respectful decline to this request", item: item)
                            coPilotPromptPill(title: "📅 Propose Meeting", prompt: "Draft a friendly reply proposing a sync tomorrow at 3 PM", item: item)
                            coPilotPromptPill(title: "🕵️ Analyze Subtext", prompt: "Analyze the tone, subtext, and hidden agenda of the sender", item: item)
                            coPilotPromptPill(title: "🌐 Translate Message", prompt: "Translate this message or provide foreign language equivalent", item: item)
                        }
                        .padding(.vertical, 1)
                    }

                    // Co-Pilot Chat Prompt Input
                    HStack(spacing: 8) {
                        TextField("Ask Gemini or ChatGPT about this chat...", text: $coPilotInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                            .onSubmit { runCoPilot(prompt: coPilotInput, item: item) }

                        Button {
                            runCoPilot(prompt: coPilotInput, item: item)
                        } label: {
                            HStack(spacing: 4) {
                                if isCoPilotThinking {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                                Text("Ask")
                            }
                            .font(.system(size: 11.5, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.accent)
                        .controlSize(.small)
                        .disabled(coPilotInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCoPilotThinking)
                    }

                    // Co-Pilot Response Container
                    if let response = coPilotResponse {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Co-Pilot Insight:")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                                    .textCase(.uppercase)
                                Spacer()
                                Button("Clear") {
                                    coPilotResponse = nil
                                }
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.muted)
                                .buttonStyle(.plain)
                            }

                            Text(response)
                                .font(.system(size: 12.5))
                                .lineSpacing(4)
                                .foregroundStyle(Color.primary)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.accent.opacity(0.3), lineWidth: 1))

                            HStack(spacing: 8) {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(response, forType: .string)
                                    store.showToast("Copied Co-Pilot response!")
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy Response")
                                    }
                                    .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(response, forType: .string)
                                    conversationViewMode = .live
                                    store.showToast("Copied to clipboard! Switched to Live Portal.")
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.right.circle.fill")
                                        Text("Insert into Chat & Open Live Portal")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(platformColor)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.card, lineWidth: 1))
                    }
                }
                .padding(16)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.card, lineWidth: 1))

                // 6. Open Live Portal Footer
                HStack {
                    Spacer()
                    Button {
                        conversationViewMode = .live
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                            Text("Open Live Portal (Marks Conversation as Read)")
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(platformColor)
                    .controlSize(.regular)
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .padding(20)
        }
    }

    private func livePortalConversationView(item: UnifiedMessageItem, platformColor: Color) -> some View {
        VStack(spacing: 0) {
            // Live Portal Mode Banner
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Live Web Session")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }

                Text("· Interacting directly with \(item.platform.name)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)

                Spacer()

                Button {
                    conversationViewMode = .stealth
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye.slash.fill")
                        Text("Switch to Stealth Peek")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Palette.panel)

            Divider()
                .background(Palette.border)

            // Embedded Live Portal Web View with direct conversation thread URL!
            PlatformPortalView(
                platformID: item.platform.id,
                explicitAccountID: item.accountID,
                customURL: item.message.linkURL.flatMap { URL(string: $0) }
            )
            .id("\(item.accountID):\(item.message.id)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func triggerCustomDraft(item: UnifiedMessageItem) {
        let prompt = customPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        isDraftingReply = true
        Task {
            let draft = await AIService.shared.draftCustomReply(
                prompt: prompt,
                messageContext: item.message.text,
                sender: item.message.sender,
                tone: selectedReplyTone,
                preferences: store.preferences
            )
            draftedReplyText = draft
            isDraftingReply = false
        }
    }

    private func runCoPilot(prompt: String, item: UnifiedMessageItem) {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        isCoPilotThinking = true
        Task {
            let result = await AIService.shared.askThreadCoPilot(
                prompt: clean,
                messageContext: item.message.text,
                sender: item.message.sender,
                platformName: item.platform.name,
                tone: selectedReplyTone,
                preferences: store.preferences
            )
            coPilotResponse = result
            isCoPilotThinking = false
        }
    }

    // MARK: - Daily Conversation Summary Card
    private func dailyConversationSummaryCard(summary: ConversationDailySummary?, item: UnifiedMessageItem, platformColor: Color) -> some View {
        guard let summary else { return AnyView(EmptyView()) }

        let completedCount = summary.actionItems.filter { completedActionItems.contains($0) }.count

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                // Header Strip
                HStack(alignment: .center, spacing: 8) {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Palette.accent.opacity(0.18))
                                .frame(width: 24, height: 24)
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.accent)
                        }

                        Text("Daily Conversation Summary")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary)

                        Text("Today")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.blue)
                    }

                    Spacer()

                    Text(summary.providerName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Palette.accent)

                    // Actions: Regenerate & Copy
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRegenerating = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                withAnimation {
                                    isRegenerating = false
                                    store.showToast("Daily summary refreshed with latest conversation context")
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.clockwise")
                                    .rotationEffect(.degrees(isRegenerating ? 360 : 0))
                                    .animation(isRegenerating ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRegenerating)
                                Text("Refresh")
                            }
                            .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            let briefingText = """
                            ✦ Daily Conversation Summary: \(summary.sender) (\(summary.platformName))
                            Date: \(summary.summaryDate.formatted(date: .abbreviated, time: .shortened))
                            Headline: \(summary.headline)
                            Overview: \(summary.executiveOverview)

                            Key Topics:
                            \(summary.keyTopics.map { "• " + $0 }.joined(separator: "\n"))

                            Decisions / Status:
                            \(summary.decisionsMade.map { "• " + $0 }.joined(separator: "\n"))

                            Action Items:
                            \(summary.actionItems.map { "• " + $0 }.joined(separator: "\n"))
                            """
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(briefingText, forType: .string)
                            store.showToast("Daily Conversation Summary copied to clipboard!")
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Headline & Metadata Tags
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.headline)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9))
                            Text(summary.relationshipContext)
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Palette.card, in: Capsule())
                        .foregroundStyle(Palette.muted)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(summary.sentiment.contains("Urgent") ? Color.red : Color.green)
                                .frame(width: 6, height: 6)
                            Text(summary.sentiment)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(summary.sentiment.contains("Urgent") ? Color.red : Color.green)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((summary.sentiment.contains("Urgent") ? Color.red : Color.green).opacity(0.12), in: Capsule())

                        if summary.messageCount > 1 {
                            Text("\(summary.messageCount) messages synthesized")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.card.opacity(0.5), in: Capsule())
                        }
                    }
                }

                // Executive Overview Card
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.accent.opacity(0.7))
                        .padding(.top, 2)

                    Text(summary.executiveOverview)
                        .font(.system(size: 12.5))
                        .lineSpacing(3.5)
                        .foregroundStyle(Color.primary.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

                // Key Topics Chips
                if !summary.keyTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Topics Discussed Today:")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.muted)
                            .textCase(.uppercase)

                        HStack(spacing: 6) {
                            ForEach(summary.keyTopics, id: \.self) { topic in
                                Text(topic)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.card, lineWidth: 1))
                                    .foregroundStyle(Color.primary)
                            }
                        }
                    }
                }

                // Two-Column Grid: Decisions & Pending Questions
                HStack(alignment: .top, spacing: 12) {
                    // Decisions Made
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.green)
                            Text("Decisions & Discussion State")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.muted)
                                .textCase(.uppercase)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(summary.decisionsMade, id: \.self) { dec in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("•")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.green)
                                    Text(dec)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.green.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.15), lineWidth: 1))

                    // Pending Questions
                    if !summary.pendingQuestions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.orange)
                                Text("Pending Questions")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .textCase(.uppercase)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(summary.pendingQuestions, id: \.self) { q in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text("?")
                                            .font(.system(size: 10.5, weight: .bold))
                                            .foregroundStyle(Color.orange)
                                        Text(q)
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Color.primary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.2), lineWidth: 1))
                    }
                }

                // Interactive Action Items Checklist
                if !summary.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                                Text("Action Items for Today")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .textCase(.uppercase)
                            }

                            Spacer()

                            Text("\(completedCount)/\(summary.actionItems.count) completed")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(summary.actionItems, id: \.self) { action in
                                let isDone = completedActionItems.contains(action)
                                Button {
                                    if isDone {
                                        completedActionItems.remove(action)
                                    } else {
                                        completedActionItems.insert(action)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: isDone ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(isDone ? Color.green : Palette.muted)

                                        Text(action)
                                            .font(.system(size: 12, weight: .medium))
                                            .strikethrough(isDone, color: Palette.muted)
                                            .foregroundStyle(isDone ? Palette.muted : Color.primary)

                                        Spacer()
                                    }
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))
                }
            }
            .padding(16)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.accent.opacity(0.25), lineWidth: 1.5))
        )
    }

    private func coPilotPromptPill(title: String, prompt: String, item: UnifiedMessageItem) -> some View {
        Button {
            coPilotInput = prompt
            runCoPilot(prompt: prompt, item: item)
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Palette.card, in: Capsule())
                .foregroundStyle(Palette.muted)
        }
        .buttonStyle(.plain)
    }

    private var alertDetailPane: some View {
        let alert = selectedAlert

        return VStack(spacing: 0) {
            if let alert {
                let platformColor = spaceColor(alert.platform.color)
                let catColor = alert.categoryType.color

                // Clean Header
                HStack(spacing: 10) {
                    PlatformLogo(platform: alert.platform, size: 24)

                    VStack(alignment: .leading, spacing: 1) {
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
                            .background(catColor.opacity(0.12), in: Capsule())
                            .foregroundStyle(catColor)
                        }

                        HStack(spacing: 5) {
                            Text(alert.platform.name)
                                .font(.system(size: 10, weight: .medium))
                            Text("·")
                                .foregroundStyle(Palette.muted.opacity(0.6))
                            Text(alert.account.name)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                            Text("·")
                                .foregroundStyle(Palette.muted.opacity(0.6))
                            Text(alert.displayTime)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                        }
                    }

                    Spacer()

                    // Action Buttons
                    HStack(spacing: 6) {
                        if let url = alert.directURL {
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

                            Button {
                                store.openPlatformNotifications(accountID: alert.account.id, notificationURL: url.absoluteString)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Open Tab")
                                    Image(systemName: "arrow.up.forward.app")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(platformColor)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Menu {
                                Button("Copy Direct Link") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                    store.showToast("Copied notice URL")
                                }
                                Button("Open in Browser") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Palette.panel)

                Divider()
                    .background(Palette.border)

                // AI Alert Notice Responder
                aiAlertResponderSection(alert: alert)

                Divider()
                    .background(Palette.border)

                // Embedded WebKit Portal
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
            return "Security notice or login alert. Verify session details below."
        case .request:
            return "Connection or invite request. Review profile and respond below."
        case .reaction:
            return "New engagement activity on your content."
        case .reply:
            return "Thread reply or comment received. Continue the conversation below."
        case .stream, .all:
            return "Live notification feed for \(alert.platform.name)."
        }
    }

    private var emptyReaderPane: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.2")
                .font(.system(size: 36))
                .foregroundStyle(Palette.muted.opacity(0.6))

            Text(selectedFolder == .unread ? "Inbox Zero" : "Select a Conversation")
                .font(.system(size: 15, weight: .semibold))

            Text(selectedFolder == .unread ? "No unread messages to display. You're completely caught up!" : "Choose a message from the list to view the live conversation.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var emptyStreamCard: some View {
        VStack(spacing: 12) {
            Spacer()
            if !query.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.muted)
                Text("No messages match \"\(query)\"")
                    .font(.system(size: 12, weight: .semibold))
                Button("Clear Filter") {
                    searchQuery = ""
                    selectedIntentFilter = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if selectedFolder == .unread {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.green)
                }
                Text("Inbox Zero — All Caught Up!")
                    .font(.system(size: 13, weight: .bold))
                Text(selectedPlatformID != nil ? "No unread messages on this platform." : "No unread messages across your connected platforms.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)

                Button {
                    selectedFolder = .all
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "archivebox")
                        Text("View All Messages (History)")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 24))
                    .foregroundStyle(Palette.muted)
                Text("No messages in this view")
                    .font(.system(size: 12, weight: .semibold))
                Text("Connect accounts or wait for messages to arrive.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
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

    // MARK: - AI Alert Notice Responder
    @ViewBuilder
    private func aiAlertResponderSection(alert: UnifiedAlertItem) -> some View {
        let analysis = AIService.shared.analyzeAlert(
            title: alert.title,
            alertText: alert.alertText,
            category: alert.category,
            platformName: alert.platform.name,
            preferences: store.preferences
        )

        VStack(spacing: 8) {
            // Header & Context Row
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.purple)

                Text(analysis.providerName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primary)

                if analysis.requiresReply {
                    Text("Reply Recommended")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Color.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                }

                Text("·")
                    .foregroundStyle(Palette.muted.opacity(0.5))

                Text(analysis.contextSummary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)

                Spacer()

                let currentDraft = alertDraftedReply ?? analysis.suggestedReplies.first?.text ?? ""
                if !currentDraft.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(currentDraft, forType: .string)
                        store.showToast("Copied active draft to clipboard! (⌘V)")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                            Text("Copy Draft")
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            // Suggested Multi-Tone Reply Pills
            if !analysis.suggestedReplies.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(analysis.suggestedReplies) { opt in
                            let isSelected = (alertDraftedReply == opt.text) || (alertDraftedReply == nil && opt == analysis.suggestedReplies.first)
                            Button {
                                alertDraftedReply = opt.text
                                selectedAlertTone = opt.tone
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(opt.text, forType: .string)
                                store.showToast("Selected \(opt.tone.rawValue) & copied to clipboard!")
                            } label: {
                                HStack(spacing: 4) {
                                    Text(opt.tone.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                    Text("— \(opt.text)")
                                        .font(.system(size: 10))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(
                                    isSelected ? Color.purple.opacity(0.18) : Palette.card,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().stroke(
                                        isSelected ? Color.purple.opacity(0.6) : Palette.border,
                                        lineWidth: 1
                                    )
                                )
                                .foregroundStyle(isSelected ? Color.purple : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Editable Draft & Refine Input Row
            HStack(spacing: 8) {
                TextField("AI Drafted reply...", text: Binding(
                    get: { alertDraftedReply ?? analysis.suggestedReplies.first?.text ?? "" },
                    set: { alertDraftedReply = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border, lineWidth: 1))

                // Quick Ask / Refine
                HStack(spacing: 4) {
                    TextField("Tweak instructions (e.g. say unavailable until Friday)...", text: $alertCustomPrompt)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                        .onSubmit {
                            refineAlertReply(alert: alert)
                        }

                    Button {
                        refineAlertReply(alert: alert)
                    } label: {
                        if isDraftingAlertReply {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isDraftingAlertReply || alertCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border.opacity(0.6), lineWidth: 1))
                .frame(maxWidth: 240)

                Button {
                    let textToInsert = alertDraftedReply ?? analysis.suggestedReplies.first?.text ?? ""
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(textToInsert, forType: .string)
                    store.showToast("Copied to clipboard! Paste directly into thread below (⌘V)")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("Copy to Thread")
                    }
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.04))
    }

    private func refineAlertReply(alert: UnifiedAlertItem) {
        let prompt = alertCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        isDraftingAlertReply = true
        Task {
            let refined = await AIService.shared.askThreadCoPilot(
                prompt: prompt,
                messageContext: alert.alertText,
                sender: alert.title,
                platformName: alert.platform.name,
                tone: selectedAlertTone,
                preferences: store.preferences
            )
            await MainActor.run {
                self.alertDraftedReply = refined
                self.isDraftingAlertReply = false
                self.alertCustomPrompt = ""
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(refined, forType: .string)
                self.store.showToast("Refined reply & copied to clipboard!")
            }
        }
    }

    // MARK: - Batch Auto-Reply Queue Generator
    private func generateQueue() {
        isGeneratingQueue = true
        Task {
            let unreadMsgs = unreadUnifiedMessages
            let actionableAlerts = allAlerts
            let generated = await AIService.shared.generateAutoReplyQueue(
                messages: unreadMsgs,
                alerts: actionableAlerts,
                preferences: store.preferences
            )
            await MainActor.run {
                self.autoReplyQueue = generated
                self.isGeneratingQueue = false
                self.isShowingAutoReplyQueue = true
            }
        }
    }

    // MARK: - Auto-Reply Queue Review Sheet
    private var autoReplyQueueSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("AI Auto-Reply Queue")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.primary)

                        let isGemini = store.preferences.aiProvider == "gemini"
                        let isLoggedIn = isGemini ? store.preferences.isGeminiLoggedIn : store.preferences.isChatGptLoggedIn
                        let providerName = isGemini ? "Google Gemini" : "OpenAI ChatGPT"

                        HStack(spacing: 4) {
                            Circle()
                                .fill(isLoggedIn ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            Text(isLoggedIn ? "\(providerName) Connected" : "\(providerName) Session")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.card, in: Capsule())
                    }

                    Text("AI synthesized drafts for \(autoReplyQueue.count) unread messages & mentions across platforms.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Button {
                    isShowingAutoReplyQueue = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Palette.panel)

            Divider().background(Palette.border)

            // Toolbar
            HStack(spacing: 8) {
                Text("Global Tone:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.muted)

                ForEach([AIReplyTone.professional, .friendly, .concise, .casual], id: \.self) { tone in
                    Button {
                        applyGlobalTone(tone)
                    } label: {
                        Text(tone.rawValue)
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Palette.card, in: Capsule())
                            .overlay(Capsule().stroke(Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    copyAllReplies()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy All (\(autoReplyQueue.count))")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(autoReplyQueue.isEmpty)

                Button {
                    generateQueue()
                } label: {
                    HStack(spacing: 4) {
                        if isGeneratingQueue {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Regenerate")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isGeneratingQueue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(Palette.background)

            Divider().background(Palette.border)

            // Body List
            if autoReplyQueue.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Palette.muted.opacity(0.4))
                    Text("No Pending Drafts in Queue")
                        .font(.system(size: 14, weight: .bold))
                    Text("All unread messages and notifications are caught up, or no actionable items detected.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach($autoReplyQueue) { $item in
                            autoReplyQueueCard(item: $item)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 800, minHeight: 520, idealHeight: 620)
        .background(Palette.background)
    }

    // MARK: - Auto-Reply Queue Item Card
    private func autoReplyQueueCard(item: Binding<AIAutoReplyItem>) -> some View {
        let val = item.wrappedValue
        return VStack(alignment: .leading, spacing: 10) {
            // Top Row
            HStack(spacing: 8) {
                // Source badge
                HStack(spacing: 4) {
                    Image(systemName: val.sourceType == .chat ? "bubble.left.fill" : "bell.badge.fill")
                        .font(.system(size: 9))
                    Text(val.sourceType == .chat ? "Chat" : "Notice")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (val.sourceType == .chat ? Color.blue : Color.orange).opacity(0.12),
                    in: Capsule()
                )
                .foregroundStyle(val.sourceType == .chat ? Color.blue : Color.orange)

                // Platform badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(spaceColor(val.platformColor))
                        .frame(width: 6, height: 6)
                    Text(val.platformName)
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("·")
                        .foregroundStyle(Palette.muted.opacity(0.5))
                    Text(val.accountName)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                if val.isDispatched {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9.5))
                        Text("Dispatched")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12), in: Capsule())
                }

                Button {
                    if let idx = autoReplyQueue.firstIndex(where: { $0.id == val.id }) {
                        autoReplyQueue.remove(at: idx)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .help("Dismiss from queue")
            }

            // Sender & Context
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(val.senderOrTitle)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Color.primary)

                    Text(val.detectedContext)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Palette.accent.opacity(0.1), in: Capsule())
                }

                Text(val.originalContent)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 6))
            }

            // Tone Switcher Chips for this item
            HStack(spacing: 5) {
                Text("Tone:")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.muted)

                ForEach([AIReplyTone.professional, .friendly, .concise, .casual, .politeDecline], id: \.self) { tone in
                    let isCurrent = val.selectedTone == tone
                    Button {
                        regenerateSingleItem(id: val.id, tone: tone)
                    } label: {
                        Text(tone.rawValue)
                            .font(.system(size: 9.5, weight: isCurrent ? .bold : .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                isCurrent ? Color.purple.opacity(0.2) : Palette.panel,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(
                                    isCurrent ? Color.purple.opacity(0.6) : Palette.border.opacity(0.6),
                                    lineWidth: 1
                                )
                            )
                            .foregroundStyle(isCurrent ? Color.purple : Palette.muted)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Draft Editor
            TextEditor(text: item.draftedReply)
                .font(.system(size: 11.5))
                .scrollContentBackground(.hidden)
                .background(Palette.background)
                .frame(minHeight: 52, maxHeight: 90)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border, lineWidth: 1))

            // Action Buttons
            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(val.draftedReply, forType: .string)
                    item.isDispatched.wrappedValue = true
                    store.showToast("Copied reply for \(val.senderOrTitle)!")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Reply")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    dispatchAutoReplyItem(val)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: val.sourceType == .chat ? "arrow.up.right.bubble.fill" : "arrow.up.right.app.fill")
                        Text(val.sourceType == .chat ? "Open Chat & Paste" : "Open Thread & Paste")
                    }
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
    }

    private func dispatchAutoReplyItem(_ val: AIAutoReplyItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(val.draftedReply, forType: .string)

        if let idx = autoReplyQueue.firstIndex(where: { $0.id == val.id }) {
            autoReplyQueue[idx].isDispatched = true
        }

        isShowingAutoReplyQueue = false

        if val.sourceType == .chat {
            let msgID = val.id.replacingOccurrences(of: "msg-", with: "")
            selectedFolder = .all
            selectedMessageID = msgID
            draftedReplyText = val.draftedReply
            store.selectAccount(val.accountID, navigate: true)
            store.showToast("Opened chat with \(val.senderOrTitle) · Reply copied to clipboard (⌘V)")
        } else {
            selectedFolder = .alerts
            let alertID = val.id.replacingOccurrences(of: "alert-", with: "")
            selectedAlertID = alertID
            alertDraftedReply = val.draftedReply
            if let direct = val.directURL {
                store.openPlatformNotifications(accountID: val.accountID, notificationURL: direct)
            } else {
                store.selectAccount(val.accountID, navigate: true)
            }
            store.showToast("Opened notice · Reply copied to clipboard (⌘V)")
        }
    }

    private func applyGlobalTone(_ tone: AIReplyTone) {
        for idx in autoReplyQueue.indices {
            autoReplyQueue[idx].selectedTone = tone
            if autoReplyQueue[idx].sourceType == .chat {
                let analysis = AIService.shared.analyzeChat(
                    sender: autoReplyQueue[idx].senderOrTitle,
                    messageText: autoReplyQueue[idx].originalContent,
                    platformName: autoReplyQueue[idx].platformName,
                    accountName: autoReplyQueue[idx].accountName,
                    preferences: store.preferences
                )
                if let matched = analysis.replies.first(where: { $0.tone == tone })?.text {
                    autoReplyQueue[idx].draftedReply = matched
                }
            } else {
                let analysis = AIService.shared.analyzeAlert(
                    title: autoReplyQueue[idx].senderOrTitle,
                    alertText: autoReplyQueue[idx].originalContent,
                    category: "mention",
                    platformName: autoReplyQueue[idx].platformName,
                    preferences: store.preferences
                )
                if let matched = analysis.suggestedReplies.first(where: { $0.tone == tone })?.text {
                    autoReplyQueue[idx].draftedReply = matched
                }
            }
        }
        store.showToast("Switched all drafts to \(tone.rawValue) tone")
    }

    private func copyAllReplies() {
        guard !autoReplyQueue.isEmpty else { return }
        var combined = "=== PINGGO AI AUTO-REPLY DRAFTS ===\n\n"
        for item in autoReplyQueue {
            combined += "[\(item.platformName) - \(item.senderOrTitle)] (\(item.sourceType.rawValue))\n"
            combined += "Context: \(item.detectedContext)\n"
            combined += "Reply:\n\(item.draftedReply)\n\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combined, forType: .string)
        for idx in autoReplyQueue.indices {
            autoReplyQueue[idx].isDispatched = true
        }
        store.showToast("Copied all \(autoReplyQueue.count) drafts to clipboard!")
    }

    private func regenerateSingleItem(id: String, tone: AIReplyTone) {
        guard let idx = autoReplyQueue.firstIndex(where: { $0.id == id }) else { return }
        autoReplyQueue[idx].selectedTone = tone
        if autoReplyQueue[idx].sourceType == .chat {
            let analysis = AIService.shared.analyzeChat(
                sender: autoReplyQueue[idx].senderOrTitle,
                messageText: autoReplyQueue[idx].originalContent,
                platformName: autoReplyQueue[idx].platformName,
                accountName: autoReplyQueue[idx].accountName,
                preferences: store.preferences
            )
            if let matched = analysis.replies.first(where: { $0.tone == tone })?.text {
                autoReplyQueue[idx].draftedReply = matched
            }
        } else {
            let analysis = AIService.shared.analyzeAlert(
                title: autoReplyQueue[idx].senderOrTitle,
                alertText: autoReplyQueue[idx].originalContent,
                category: "mention",
                platformName: autoReplyQueue[idx].platformName,
                preferences: store.preferences
            )
            if let matched = analysis.suggestedReplies.first(where: { $0.tone == tone })?.text {
                autoReplyQueue[idx].draftedReply = matched
            }
        }
    }
}
