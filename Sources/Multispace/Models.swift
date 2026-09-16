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
        let address = websiteURL ?? Self.defaultWebsites[id]
            ?? Self.defaultWebsites[officialIdentity?.id ?? ""] ?? officialIdentity?.websiteURL
        guard let address, let url = URL(string: address),
              url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    var usesOfficialLogo: Bool {
        officialIdentity != nil && customIcon != true
    }

    static let defaultWebsites: [String: String] = [
        "whatsapp": "https://web.whatsapp.com/",
        "instagram": "https://www.instagram.com/",
        "telegram": "https://web.telegram.org/a/",
        "facebook": "https://www.facebook.com/"
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

struct PlatformMessagePreview: Identifiable, Hashable {
    let id: String
    let sender: String
    let text: String
}

struct PlatformActivitySnapshot {
    var unreadCount: Int?
    var messages: [PlatformMessagePreview]
    var notifications: [String]
    var updatedAt: Date
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
    case feed
    case inbox
    case platform(String)
    case channel(UUID)
    case conversation(UUID)
    case profile
}
