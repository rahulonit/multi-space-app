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

    static let defaults: [SocialPlatform] = [
        .init(id: "whatsapp", name: "WhatsApp", symbol: "phone.bubble.fill", color: "green"),
        .init(id: "instagram", name: "Instagram", symbol: "camera.fill", color: "pink"),
        .init(id: "telegram", name: "Telegram", symbol: "paperplane.fill", color: "blue"),
        .init(id: "facebook", name: "Facebook", symbol: "person.2.fill", color: "blue")
    ]
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
