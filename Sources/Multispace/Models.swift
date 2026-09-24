import Foundation
import Security

struct Member: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var handle: String
    var color: String
    var status: String = "Available"
}

struct Space: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var detail: String
    var symbol: String
    var color: String
}

struct Channel: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var spaceID: UUID
    var name: String
    var topic: String
}

struct SocialPlatform: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var color: String
    var websiteURL: String? = nil
    var customIcon: Bool? = nil

    var officialIdentity: SocialPlatform? {
        (Self.defaults + Self.suggestions).first {
            $0.id == id || $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    var resolvedWebsiteURL: URL? {
        var address = websiteURL ?? Self.defaultWebsites[id]
            ?? Self.defaultWebsites[officialIdentity?.id ?? ""] ?? officialIdentity?.websiteURL
        if (id == "linkedin" || officialIdentity?.id == "linkedin") && (address == nil || address == "https://www.linkedin.com/login") {
            address = "https://www.linkedin.com/feed/"
        }
        guard let address, let url = URL(string: address),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    var inboxURL: URL? {
        let targetId = officialIdentity?.id ?? id
        let directAddress: String? = {
            switch targetId {
            case "whatsapp": return "https://web.whatsapp.com/"
            case "telegram": return "https://web.telegram.org/a/"
            case "instagram": return "https://www.instagram.com/direct/inbox/"
            case "facebook": return "https://www.facebook.com/messages/t/"
            case "linkedin": return "https://www.linkedin.com/messaging/"
            case "x": return "https://x.com/messages"
            case "discord": return "https://discord.com/channels/@me"
            case "snapchat": return "https://web.snapchat.com/"
            case "slack": return "https://app.slack.com/client"
            case "reddit": return "https://www.reddit.com/message/inbox"
            case "teams": return "https://teams.microsoft.com"
            default: return nil
            }
        }()
        if let directAddress, let url = URL(string: directAddress) {
            return url
        }
        return resolvedWebsiteURL
    }

    var notificationsURL: URL? {
        let targetId = officialIdentity?.id ?? id
        let directAddress: String? = {
            switch targetId {
            case "linkedin": return "https://www.linkedin.com/notifications/"
            case "x": return "https://x.com/notifications"
            case "instagram": return "https://www.instagram.com/accounts/activity/"
            case "facebook": return "https://www.facebook.com/notifications"
            case "reddit": return "https://www.reddit.com/notifications"
            case "discord": return "https://discord.com/channels/@me"
            case "slack": return "https://app.slack.com/client"
            case "threads": return "https://www.threads.net/activity"
            case "tiktok": return "https://www.tiktok.com/inbox"
            case "github": return "https://github.com/notifications"
            case "youtube": return "https://www.youtube.com/feed/subscriptions"
            case "whatsapp": return "https://web.whatsapp.com/"
            case "telegram": return "https://web.telegram.org/a/"
            default: return inboxURL?.absoluteString ?? resolvedWebsiteURL?.absoluteString
            }
        }()
        if let directAddress, let url = URL(string: directAddress) {
            return url
        }
        return inboxURL ?? resolvedWebsiteURL
    }

    var usesOfficialLogo: Bool {
        officialIdentity != nil && customIcon != true
    }

    static let defaultWebsites: [String: String] = [
        "whatsapp": "https://web.whatsapp.com/",
        "instagram": "https://www.instagram.com/",
        "telegram": "https://web.telegram.org/a/",
        "facebook": "https://www.facebook.com/",
        "linkedin": "https://www.linkedin.com/feed/",
        "x": "https://x.com/home",
        "slack": "https://app.slack.com/client",
        "reddit": "https://www.reddit.com/",
        "teams": "https://teams.microsoft.com",
        "discord": "https://discord.com/channels/@me"
    ]

    static let defaults: [SocialPlatform] = [
        .init(id: "whatsapp", name: "WhatsApp", symbol: "phone.bubble.fill", color: "green"),
        .init(id: "instagram", name: "Instagram", symbol: "camera.fill", color: "pink"),
        .init(id: "telegram", name: "Telegram", symbol: "paperplane.fill", color: "blue"),
        .init(id: "facebook", name: "Facebook", symbol: "person.2.fill", color: "blue")
    ]

    static let suggestions: [SocialPlatform] = [
        .init(id: "discord", name: "Discord", symbol: "bubble.left.and.bubble.right.fill", color: "purple", websiteURL: "https://discord.com/app"),
        .init(id: "linkedin", name: "LinkedIn", symbol: "person.2.fill", color: "blue", websiteURL: "https://www.linkedin.com/feed/"),
        .init(id: "x", name: "X", symbol: "at", color: "purple", websiteURL: "https://x.com/home"),
        .init(id: "snapchat", name: "Snapchat", symbol: "camera.fill", color: "orange", websiteURL: "https://web.snapchat.com/"),
        .init(id: "tiktok", name: "TikTok", symbol: "video.fill", color: "pink", websiteURL: "https://www.tiktok.com/")
    ]
}

struct PlatformMessagePreview: Identifiable, Hashable, Codable {
    let id: String
    let sender: String
    let text: String
    var time: String? = nil
    var linkURL: String? = nil
    var isUnread: Bool? = nil

    var unread: Bool {
        isUnread ?? false
    }
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

enum AlertCategoryType: String, CaseIterable, Codable {
    case all = "All"
    case mention = "Mentions"
    case request = "Requests"
    case security = "Security"
    case reaction = "Reactions"
    case reply = "Replies"
    case stream = "Notices Hub"

    var icon: String {
        switch self {
        case .all: return "tray.2"
        case .mention: return "at"
        case .request: return "person.badge.shield.checkmark"
        case .security: return "lock.shield"
        case .reaction: return "hand.thumbsup"
        case .reply: return "arrowshape.turn.up.left"
        case .stream: return "bell.badge"
        }
    }
}

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

struct PlatformNotificationPreview: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let text: String
    var time: String? = nil
    var linkURL: String? = nil
    var category: String = "general"
}

struct PlatformActivitySnapshot: Codable, Equatable {
    var unreadCount: Int?
    var messages: [PlatformMessagePreview]
    var notifications: [String]
    var notificationPreviews: [PlatformNotificationPreview]? = nil
    var updatedAt: Date

    var allNotificationPreviews: [PlatformNotificationPreview] {
        if let previews = notificationPreviews, !previews.isEmpty {
            return previews
        }
        return notifications.enumerated().map { idx, str in
            PlatformNotificationPreview(
                id: "legacy-\(idx)-\(str.hashValue)",
                title: "Alert",
                text: str,
                time: nil,
                linkURL: nil,
                category: "general"
            )
        }
    }
}

struct ActiveChatMessage: Identifiable, Hashable, Codable {
    var id: String = UUID().uuidString
    var sender: String
    var text: String
    var isFromMe: Bool
    var time: String? = nil
}

struct AIChatPhoneNumberItem: Identifiable, Equatable, Hashable, Codable {
    var id: String { "\(name)-\(number)" }
    var name: String
    var number: String
    var context: String
}

struct AIChatMemberItem: Identifiable, Equatable, Hashable, Codable {
    var id: String { name }
    var name: String
    var role: String
    var activity: String
    var messageCount: Int
    var phoneNumber: String? = nil
}

enum AIResponseSource: Equatable, Codable {
    case providerGenerated(provider: String, model: String)
    case localHeuristic(engineName: String)
    case structuredExtraction
    case cachedAIResponse

    var badgeText: String {
        switch self {
        case .providerGenerated(let provider, let model):
            return "Powered by \(provider) · \(model)"
        case .localHeuristic(let engine):
            return "Generated locally · \(engine)"
        case .structuredExtraction:
            return "Extracted locally · Pinggo Smart Engine"
        case .cachedAIResponse:
            return "Cached AI Response"
        }
    }
}

struct AITaskItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var assignee: String? = nil
    var createdBy: String? = nil
    var dueDate: String? = nil
    var sourceMessageId: String? = nil
    var isCompleted: Bool = false
}

struct ConversationAIState: Equatable {
    var questionDraft: String = ""
    var history: [AIChatMessage] = []
    var analysis: ChatIntelligenceAnalysis? = nil
    var customPromptInput: String = ""
    var draftedReplyText: String? = nil
    var isDrafting: Bool = false
    var isResponding: Bool = false
    var errorMessage: String? = nil
    var activeTab: AIPanelTab = .ask
    var pendingConfirmationAction: String? = nil
}

enum ConversationNavTab: String, CaseIterable, Identifiable, Codable {
    case summary = "Summary"
    case messages = "Messages"
    case files = "Files"
    case tasks = "Tasks"
    case links = "Links"
    case activity = "Activity"
    case insights = "Insights"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .summary: return "text.quote"
        case .messages: return "message.fill"
        case .files: return "folder.fill"
        case .tasks: return "checkmark.circle.fill"
        case .links: return "link"
        case .activity: return "chart.xyaxis.line"
        case .insights: return "sparkles"
        }
    }
}

enum AIPanelTab: String, CaseIterable, Identifiable, Codable {
    case ask = "Ask"
    case tasks = "Tasks"
    case files = "Files"
    case activity = "Activity"
    case actions = "Actions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ask: return "bubble.left.and.bubble.right.fill"
        case .tasks: return "checklist"
        case .files: return "doc.text.fill"
        case .activity: return "waveform.path.ecg"
        case .actions: return "bolt.fill"
        }
    }
}

enum CertaintyLevel: String, CaseIterable, Identifiable, Codable {
    case confirmed = "Confirmed"
    case tentative = "Tentative"
    case aiInferred = "AI Inferred"

    var id: String { rawValue }
}

struct ProjectDecisionItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var text: String
    var status: String = "Approved" // Approved, Pending Confirmation, In Review
    var certainty: CertaintyLevel = .confirmed
    var source: String = "Message #4"
    var sourceMessageId: String? = nil
    var timeString: String = "Today"
}

struct ProjectTaskItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var owner: String = "You" // You, Team, Unassigned, or explicit role
    var dueDate: String = "Tomorrow"
    var certainty: CertaintyLevel = .confirmed
    var status: String = "In Progress" // In Progress, Pending, Completed
    var source: String = "Message #2"
    var sourceMessageId: String? = nil
    var isDone: Bool = false
}

struct ProjectStatusInfo: Equatable, Codable {
    var status: String = "On Track"
    var upcomingDeadline: String = "Tomorrow morning"
    var latestActivity: String = "Design review completed"
    var source: String = "Sprint Deliverables Matrix"
    var sourceMessageId: String? = nil
}

struct NeedsAttentionItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var urgency: String = "High"
    var category: String = "Confirmation"
    var source: String = "Message #4"
    var sourceMessageId: String? = nil
}

struct ConversationTimelineItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var timeString: String
    var role: String = "Team"
    var event: String
    var source: String
    var dayGroup: String = "Today"
}

struct ConversationChangeItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var text: String
    var source: String = "AI Delta"
    var timestamp: String = "Today"
}

struct SharedFileItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var filename: String
    var sizeString: String
    var fileType: String
    var sharedTime: String
    var sourceMessageId: String? = nil
}

struct SharedLinkItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var url: String
    var domain: String
    var sharedTime: String
    var sourceMessageId: String? = nil
}

struct KeyContributorItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var roleName: String
    var contributionCount: Int
    var decisionsCount: Int
    var openActionsCount: Int
    var isConfirmedRole: Bool = false
}

struct UpcomingDeadlineItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var title: String
    var timeString: String
    var certainty: CertaintyLevel = .confirmed
    var source: String = "Message #1"
    var sourceMessageId: String? = nil
}

struct WorkstreamStatusItem: Identifiable, Equatable, Hashable, Codable {
    var id: String = UUID().uuidString
    var name: String
    var progressPercent: Int
    var statusString: String
}

struct ConversationContext: Identifiable, Equatable, Codable {
    var id: String { conversationId }
    var workspaceId: String = "work-workspace"
    var accountId: UUID? = nil
    var conversationId: String
    var conversationTitle: String
    var platformId: String = "platform"
    var platformName: String = "Messaging Platform"
    var isPreview: Bool = false

    // Single source of truth message set
    var messages: [PlatformMessagePreview] = []
    var indexedMessageCount: Int { messages.count }
    var latestMessageId: String? = nil
    var lastIndexedMessageId: String? = nil
    var lastAnalyzedAt: Date = Date()
    var isStale: Bool = false

    // Structured intelligence items strictly bound to this conversation
    var summaryText: String = ""
    var topics: [String] = []
    var decisions: [ProjectDecisionItem] = []
    var tasks: [ProjectTaskItem] = []
    var deadlines: [UpcomingDeadlineItem] = []
    var files: [SharedFileItem] = []
    var links: [SharedLinkItem] = []
    var contributors: [KeyContributorItem] = []
    var timeline: [ConversationTimelineItem] = []
    var recentChanges: [ConversationChangeItem] = []
    var needsAttention: [NeedsAttentionItem] = []
    var openQuestions: [String] = []
    var statusInfo: ProjectStatusInfo = ProjectStatusInfo()

    // Derived counts - NEVER maintained independently in UI
    var taskCount: Int { tasks.count }
    var completedTaskCount: Int { tasks.filter(\.isDone).count }
    var deadlineCount: Int { deadlines.count }
    var fileCount: Int { files.count }
    var decisionCount: Int { decisions.count }
    var topicCount: Int { topics.count }

    // Calculated Task Progress (0..100)
    var progressPercent: Int {
        guard !tasks.isEmpty else { return 0 }
        return (completedTaskCount * 100) / tasks.count
    }
}

struct AIChatMessage: Identifiable, Equatable, Codable {
    var id: String
    var isUser: Bool
    var text: String
    var timestamp: Date
    var actionItems: [String]? = nil
    var phoneNumbers: [AIChatPhoneNumberItem]? = nil
    var members: [AIChatMemberItem]? = nil
    var relatedPrompts: [String]? = nil
    var source: AIResponseSource? = nil
    var tasks: [AITaskItem]? = nil
    var sourceMessageId: String? = nil
}

struct ActiveThreadContext: Hashable, Codable {
    var contactName: String
    var platformID: String
    var messages: [ActiveChatMessage]
    var groupMemberCount: Int? = nil
    var groupSubtitle: String? = nil
    var groupMembers: [AIChatMemberItem]? = nil
    var updatedAt: Date = .now

    var contextSnippet: String {
        if messages.isEmpty {
            return contactName.isEmpty ? "" : "Active conversation with \(contactName)."
        }
        let list = messages.map { "\($0.isFromMe ? "You" : $0.sender): \($0.text)" }.joined(separator: "\n")
        return "Conversation with \(contactName):\n\(list)"
    }

    var isGroupChat: Bool {
        if let count = groupMemberCount, count > 2 { return true }
        if let sub = groupSubtitle, !sub.isEmpty {
            let low = sub.lowercased()
            if low.contains("participant") || low.contains("member") || low.contains("subscriber") || low.contains(",") {
                return true
            }
        }
        if let members = groupMembers, members.count > 1 { return true }
        let senders = Set(messages.map(\.sender).filter { !$0.isEmpty && $0.lowercased() != "you" && $0.lowercased() != "me" && $0.lowercased() != "contact" })
        return senders.count > 1
    }

    var effectiveMembers: [AIChatMemberItem] {
        var map: [String: AIChatMemberItem] = [:]
        for m in groupMembers ?? [] {
            map[m.name.lowercased()] = m
        }
        for msg in messages {
            let s = msg.sender.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty && s.lowercased() != "you" && s.lowercased() != "me" && s.lowercased() != "contact" {
                if let existing = map[s.lowercased()] {
                    var updated = existing
                    let count = messages.filter { $0.sender.localizedCaseInsensitiveCompare(s) == .orderedSame }.count
                    updated.messageCount = max(updated.messageCount, count)
                    map[s.lowercased()] = updated
                } else {
                    let count = messages.filter { $0.sender.localizedCaseInsensitiveCompare(s) == .orderedSame }.count
                    map[s.lowercased()] = AIChatMemberItem(name: s, role: "Member", activity: "Active in chat", messageCount: count)
                }
            }
        }
        return map.values.sorted {
            if $0.role.lowercased().contains("admin") && !$1.role.lowercased().contains("admin") { return true }
            if !$0.role.lowercased().contains("admin") && $1.role.lowercased().contains("admin") { return false }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var groupAdmins: [AIChatMemberItem] {
        effectiveMembers.filter { $0.role.lowercased().contains("admin") || $0.role.lowercased().contains("owner") || $0.role.lowercased().contains("creator") }
    }

    var fullTranscript: String {
        guard !messages.isEmpty else {
            return contactName.isEmpty ? "No active messages." : "Conversation with \(contactName)."
        }
        return messages.enumerated().map { idx, msg in
            let timeStr = (msg.time?.isEmpty == false) ? " [\(msg.time!)]" : ""
            let sender = msg.isFromMe ? "You" : msg.sender
            return "[#\(idx + 1) | \(sender)\(timeStr)]: \(msg.text)"
        }.joined(separator: "\n")
    }

    var topicSummary: String {
        if messages.isEmpty {
            return "Active conversation with \(contactName). Awaiting incoming messages."
        }
        let incoming = messages.filter { !$0.isFromMe }
        if let last = incoming.last?.text, !last.isEmpty {
            let truncated = last.count > 120 ? String(last.prefix(117)) + "..." : last
            return "\"\(truncated)\""
        } else if let last = messages.last?.text, !last.isEmpty {
            let truncated = last.count > 120 ? String(last.prefix(117)) + "..." : last
            return "\"\(truncated)\""
        }
        return "Conversation with \(contactName) (\(messages.count) messages exchanged)."
    }
}

struct SentimentResult: Hashable, Codable {
    var score: Double = 0.0
    var classification: String = "Neutral / Professional"
    var detectedLanguage: String = "English"
}

struct PlatformAccount: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var platformID: String
    var name: String
    var usesLegacyStore: Bool = false
}

struct Conversation: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var memberID: UUID
}

struct Message: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var channelID: UUID?
    var conversationID: UUID?
    var authorID: UUID
    var text: String
    var sentAt: Date = .now
}

struct Post: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var spaceID: UUID
    var authorID: UUID
    var text: String
    var createdAt: Date = .now
    var likedBy: Set<UUID> = []
}

struct AppData: Codable {
    var me: Member
    var members: [Member]
    var spaces: [Space]
    var channels: [Channel]
    var conversations: [Conversation]
    var messages: [Message]
    var posts: [Post]
}

enum AppDestination: Hashable {
    case home
    case browser
    case platform(String)
    case channel(UUID)
    case conversation(UUID)
    case profile
    case settings
}

struct AppPreferences: Codable, Equatable {
    var language = "Follow System"
    var appearance = "Follow System"
    var accent = "indigo"
    var compactMode = false
    var openTo = "Home"
    var launchWebsites = true
    var launchDelay = 0
    var showWebsiteAlerts = true
    var appLockEnabled = false
    var autoLockMinutes = 5
    var tabFreezingEnabled = true
    var tabFreezeMinutes = 15
    var lockMethod: String = "biometric" // "biometric", "customPin", "both"
    var customPinHash: String = ""
    var customPinSalt: String = ""
    var customPinHint: String = ""

    // MARK: - AI Assistant & Private Preview Preferences
    var aiEnabled: Bool = true
    var aiProvider: String = "gemini" // "gemini", "chatgpt", "ollama", "smart"
    var isGeminiLoggedIn: Bool = false
    var geminiAccountEmail: String = ""
    var isChatGptLoggedIn: Bool = false
    var chatGptAccountEmail: String = ""
    var geminiApiKey: String = ""
    var openAiApiKey: String = ""
    var aiModelTier: String = "gemini-2.5-flash"
    var geminiModelTier: String = "gemini-2.5-flash"
    var openAiModelTier: String = "gpt-4o-mini"
    var ollamaModelTier: String = "llama3.2"
    var ollamaEndpoint: String = "http://localhost:11434"
    var ollamaModel: String = "llama3.2"
    var personaStyle: String = "direct"
    var stealthModeDefault: Bool = true
    var defaultReplyTone: String = "Professional"
    var customAiPrompt: String = ""

    // MARK: - Browser & AdBlock Preferences
    var adBlockBlockAds: Bool = true
    var adBlockBlockTrackers: Bool = true
    var adBlockBlockCookieBanners: Bool = true

    enum CodingKeys: String, CodingKey {
        case language, appearance, accent, compactMode, openTo, launchWebsites, launchDelay
        case showWebsiteAlerts, appLockEnabled, autoLockMinutes, tabFreezingEnabled, tabFreezeMinutes
        case lockMethod, customPinHash, customPinSalt, customPinHint
        case aiEnabled, aiProvider, isGeminiLoggedIn, geminiAccountEmail, isChatGptLoggedIn, chatGptAccountEmail
        // API credentials deliberately stay out of Codable/UserDefaults. AppStore
        // loads and persists them through KeychainHelper instead.
        case aiModelTier, geminiModelTier, openAiModelTier, ollamaModelTier, ollamaEndpoint, ollamaModel, personaStyle
        case stealthModeDefault, defaultReplyTone, customAiPrompt
        case adBlockBlockAds, adBlockBlockTrackers, adBlockBlockCookieBanners
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "Follow System"
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "Follow System"
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "indigo"
        compactMode = try c.decodeIfPresent(Bool.self, forKey: .compactMode) ?? false
        openTo = try c.decodeIfPresent(String.self, forKey: .openTo) ?? "Home"
        launchWebsites = try c.decodeIfPresent(Bool.self, forKey: .launchWebsites) ?? true
        launchDelay = try c.decodeIfPresent(Int.self, forKey: .launchDelay) ?? 0
        showWebsiteAlerts = try c.decodeIfPresent(Bool.self, forKey: .showWebsiteAlerts) ?? true
        appLockEnabled = try c.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
        autoLockMinutes = try c.decodeIfPresent(Int.self, forKey: .autoLockMinutes) ?? 5
        tabFreezingEnabled = try c.decodeIfPresent(Bool.self, forKey: .tabFreezingEnabled) ?? true
        tabFreezeMinutes = try c.decodeIfPresent(Int.self, forKey: .tabFreezeMinutes) ?? 15
        lockMethod = try c.decodeIfPresent(String.self, forKey: .lockMethod) ?? "biometric"
        customPinHash = try c.decodeIfPresent(String.self, forKey: .customPinHash) ?? ""
        customPinSalt = try c.decodeIfPresent(String.self, forKey: .customPinSalt) ?? ""
        customPinHint = try c.decodeIfPresent(String.self, forKey: .customPinHint) ?? ""
        aiEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? true
        aiProvider = try c.decodeIfPresent(String.self, forKey: .aiProvider) ?? "gemini"
        isGeminiLoggedIn = try c.decodeIfPresent(Bool.self, forKey: .isGeminiLoggedIn) ?? false
        geminiAccountEmail = try c.decodeIfPresent(String.self, forKey: .geminiAccountEmail) ?? ""
        isChatGptLoggedIn = try c.decodeIfPresent(Bool.self, forKey: .isChatGptLoggedIn) ?? false
        chatGptAccountEmail = try c.decodeIfPresent(String.self, forKey: .chatGptAccountEmail) ?? ""
        geminiApiKey = ""
        openAiApiKey = ""
        let rawAiModel = try c.decodeIfPresent(String.self, forKey: .aiModelTier) ?? "gemini-2.5-flash"
        aiModelTier = rawAiModel.contains("gemini-3.5") ? "gemini-2.5-flash" : rawAiModel
        let rawGeminiModel = try c.decodeIfPresent(String.self, forKey: .geminiModelTier) ?? "gemini-2.5-flash"
        geminiModelTier = rawGeminiModel.contains("gemini-3.5") ? "gemini-2.5-flash" : rawGeminiModel
        openAiModelTier = try c.decodeIfPresent(String.self, forKey: .openAiModelTier) ?? (aiModelTier.contains("gpt") ? aiModelTier : "gpt-4o-mini")
        ollamaModelTier = try c.decodeIfPresent(String.self, forKey: .ollamaModelTier) ?? (try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "llama3.2")
        ollamaEndpoint = try c.decodeIfPresent(String.self, forKey: .ollamaEndpoint) ?? "http://localhost:11434"
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? ollamaModelTier
        personaStyle = try c.decodeIfPresent(String.self, forKey: .personaStyle) ?? "direct"
        stealthModeDefault = try c.decodeIfPresent(Bool.self, forKey: .stealthModeDefault) ?? true
        defaultReplyTone = try c.decodeIfPresent(String.self, forKey: .defaultReplyTone) ?? "Professional"
        customAiPrompt = try c.decodeIfPresent(String.self, forKey: .customAiPrompt) ?? ""
        adBlockBlockAds = try c.decodeIfPresent(Bool.self, forKey: .adBlockBlockAds) ?? true
        adBlockBlockTrackers = try c.decodeIfPresent(Bool.self, forKey: .adBlockBlockTrackers) ?? true
        adBlockBlockCookieBanners = try c.decodeIfPresent(Bool.self, forKey: .adBlockBlockCookieBanners) ?? true
    }

}

struct CopilotMessage: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var role: String // "user" or "assistant"
    var content: String
    var timestamp: Date = .now
}

enum PersonaStyle: String, CaseIterable, Identifiable {
    case direct = "Direct & Crisp"
    case friendly = "Casual & Warm"
    case executive = "Executive & Formal"
    case technical = "Technical & Precise"

    var id: String { rawValue }

    var systemInstruction: String {
        switch self {
        case .direct:
            return "Adopt a direct, concise, and action-oriented communication style. Omit pleasantries and fluff."
        case .friendly:
            return "Adopt a warm, friendly, empathetic, and approachable conversational style."
        case .executive:
            return "Adopt an executive, structured, highly professional, and diplomatic communication style."
        case .technical:
            return "Adopt a precise, technically accurate, analytical, and structured communication style."
        }
    }
}

enum AIReplyTone: String, CaseIterable, Codable, Identifiable {
    case professional = "Professional"
    case friendly = "Friendly"
    case concise = "Concise"
    case casual = "Casual"
    case politeDecline = "Polite Decline"
    case proposeTime = "Propose Time"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .professional: return "briefcase.fill"
        case .friendly: return "face.smiling.fill"
        case .concise: return "bolt.fill"
        case .casual: return "hand.wave.fill"
        case .politeDecline: return "hand.raised.fill"
        case .proposeTime: return "calendar.badge.clock"
        }
    }
}

enum AIMessagePriority: String, CaseIterable, Codable {
    case urgent = "Urgent Action"
    case question = "Awaiting Reply"
    case meeting = "Meeting Request"
    case review = "Review / Task"
    case normal = "General Update"

    var icon: String {
        switch self {
        case .urgent: return "flame.fill"
        case .question: return "questionmark.bubble.fill"
        case .meeting: return "calendar.badge.clock"
        case .review: return "doc.text.magnifyingglass"
        case .normal: return "bubble.left"
        }
    }

    var shortTag: String {
        switch self {
        case .urgent: return "🔥 Urgent"
        case .question: return "❓ Question"
        case .meeting: return "📅 Meeting"
        case .review: return "📝 Review"
        case .normal: return "💬 Update"
        }
    }
}

struct AICalendarEvent: Identifiable, Equatable, Codable {
    var id: String = UUID().uuidString
    let title: String
    let dateSuggestion: String
    let startTime: String?
    let locationOrLink: String?
    let notes: String
}

struct AICoPilotMessage: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    let isUser: Bool
    let text: String
    var timestamp: Date = .now
    let modelProvider: String
}

struct AIReplyOption: Identifiable, Equatable, Codable {
    var id: String
    let tone: AIReplyTone
    let text: String
}

struct ConversationDailySummary: Identifiable, Equatable, Codable {
    var id: String
    let sender: String
    let platformName: String
    let accountName: String
    let summaryDate: Date
    let headline: String
    let executiveOverview: String
    let keyTopics: [String]
    let decisionsMade: [String]
    let pendingQuestions: [String]
    let actionItems: [String]
    let sentiment: String
    let relationshipContext: String
    let providerName: String
    let messageCount: Int
}

struct AIAnalysisResult: Equatable, Codable {
    let sender: String
    let contextSummary: String
    let detectedIntent: String
    let detectedQuestion: String?
    let actionItem: String?
    let urgency: SummaryUrgency
    let sentiment: String
    let replies: [AIReplyOption]
    let providerName: String
    let isStealthMode: Bool
    let analyzedAt: Date
    var aiPriority: AIMessagePriority = .normal
    var detectedCalendarEvent: AICalendarEvent? = nil
    var detectedLanguage: String? = nil
    var translatedText: String? = nil
    var dailySummary: ConversationDailySummary? = nil
}

enum AIAutoReplySource: String, Codable {
    case chat = "Chat Message"
    case alert = "Notification / Alert"
}

struct AIAutoReplyItem: Identifiable, Equatable, Codable {
    var id: String
    let sourceType: AIAutoReplySource
    let platformID: String
    let platformName: String
    let platformColor: String
    let accountID: UUID
    let accountName: String
    let senderOrTitle: String
    let originalContent: String
    let detectedContext: String
    var draftedReply: String
    var selectedTone: AIReplyTone
    let directURL: String?
    var isDispatched: Bool = false
}

struct AIAlertAnalysisResult: Equatable, Codable {
    let title: String
    let alertText: String
    let category: String
    let requiresReply: Bool
    let contextSummary: String
    let suggestedReplies: [AIReplyOption]
    let providerName: String
}

struct UserProfile: Codable, Equatable {
    var isSignedIn: Bool = false
    var provider: String? = nil // "Apple", "Google", "Microsoft"
    var email: String = ""
    var displayName: String = "You"
    var avatarColor: String = "indigo"
    var subscriptionTier: String = "Free"
    var subscriptionStatus: String = "Active"
    var subscriptionRenewsAt: Date = Date().addingTimeInterval(86400 * 365)
    var lastCloudBackup: Date? = nil
    var autoCloudSync: Bool = true
    var cloudStorageUsage: String = "0 B of 50 GB used"
}

// MARK: - Apple Keychain / Passwords Helper
enum KeychainHelper {
    static let serviceName = "app.pinggo.desktop"
    static let defaultAccount = "PINGGO App Lock"
    static let geminiAPIAccount = "PINGGO Gemini API"
    static let openAIAPIAccount = "PINGGO OpenAI API"

    @discardableResult
    static func savePassword(_ password: String, service: String = serviceName, account: String = defaultAccount) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        deletePassword(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func getPassword(service: String = serviceName, account: String = defaultAccount) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func deletePassword(service: String = serviceName, account: String = defaultAccount) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
