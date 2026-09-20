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
        if (id == "linkedin" || officialIdentity?.id == "linkedin") && (address == nil || address == "https://www.linkedin.com/feed/") {
            address = "https://www.linkedin.com/login"
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
        "linkedin": "https://www.linkedin.com/login"
    ]

    static let defaults: [SocialPlatform] = [
        .init(id: "whatsapp", name: "WhatsApp", symbol: "phone.bubble.fill", color: "green"),
        .init(id: "instagram", name: "Instagram", symbol: "camera.fill", color: "pink"),
        .init(id: "telegram", name: "Telegram", symbol: "paperplane.fill", color: "blue"),
        .init(id: "facebook", name: "Facebook", symbol: "person.2.fill", color: "blue")
    ]

    static let suggestions: [SocialPlatform] = [
        .init(id: "discord", name: "Discord", symbol: "bubble.left.and.bubble.right.fill", color: "purple", websiteURL: "https://discord.com/app"),
        .init(id: "linkedin", name: "LinkedIn", symbol: "person.2.fill", color: "blue", websiteURL: "https://www.linkedin.com/login"),
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
    case inbox
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

    // MARK: - AI Assistant & Stealth Mode Preferences
    var aiEnabled: Bool = true
    var aiProvider: String = "gemini" // "gemini" or "chatgpt"
    var isGeminiLoggedIn: Bool = false
    var geminiAccountEmail: String = ""
    var isChatGptLoggedIn: Bool = false
    var chatGptAccountEmail: String = ""
    var geminiApiKey: String = ""
    var openAiApiKey: String = ""
    var aiModelTier: String = "gemini-1.5-flash"
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
        case geminiApiKey, openAiApiKey, aiModelTier
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
        geminiApiKey = try c.decodeIfPresent(String.self, forKey: .geminiApiKey) ?? ""
        openAiApiKey = try c.decodeIfPresent(String.self, forKey: .openAiApiKey) ?? ""
        aiModelTier = try c.decodeIfPresent(String.self, forKey: .aiModelTier) ?? "gemini-1.5-flash"
        stealthModeDefault = try c.decodeIfPresent(Bool.self, forKey: .stealthModeDefault) ?? true
        defaultReplyTone = try c.decodeIfPresent(String.self, forKey: .defaultReplyTone) ?? "Professional"
        customAiPrompt = try c.decodeIfPresent(String.self, forKey: .customAiPrompt) ?? ""
        adBlockBlockAds = try c.decodeIfPresent(Bool.self, forKey: .adBlockBlockAds) ?? true
        adBlockBlockTrackers = try c.decodeIfPresent(Bool.self, forKey: .adBlockBlockTrackers) ?? true
        adBlockBlockCookieBanners = try c.decodeIfPresent(Bool.self, forKey: .adBlockBlockCookieBanners) ?? true
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
    var email: String = "local.user@pinggo.internal"
    var displayName: String = "Nikita"
    var avatarColor: String = "indigo"
    var subscriptionTier: String = "Free"
    var subscriptionStatus: String = "Active"
    var subscriptionRenewsAt: Date = Date().addingTimeInterval(86400 * 365)
    var lastCloudBackup: Date? = nil
    var autoCloudSync: Bool = true
    var cloudStorageUsage: String = "1.4 MB of 50 GB used"
}

// MARK: - Apple Keychain / Passwords Helper
enum KeychainHelper {
    static let serviceName = "app.pinggo.desktop"
    static let defaultAccount = "PINGGO App Lock"

    @discardableResult
    static func savePassword(_ password: String, service: String = serviceName, account: String = defaultAccount) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        deletePassword(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "PINGGO App Lock Password",
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

