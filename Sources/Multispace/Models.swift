import Foundation

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
}

struct PlatformActivitySnapshot: Codable, Equatable {
    var unreadCount: Int?
    var messages: [PlatformMessagePreview]
    var notifications: [String]
    var updatedAt: Date
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
}
