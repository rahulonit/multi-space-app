import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published var destination: AppDestination = .home
    @Published var activeSpaceID: UUID?
    @Published var searchText = ""
    @Published private(set) var addedPlatforms: [SocialPlatform] = []

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Multispace", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("data.json")
        if let saved = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: saved) {
            data = decoded
        } else {
            data = Self.sampleData()
        }
        activeSpaceID = data.spaces.first?.id
        if let saved = UserDefaults.standard.data(forKey: "addedSocialPlatforms"),
           let decoded = try? JSONDecoder().decode([SocialPlatform].self, from: saved) {
            addedPlatforms = decoded
        }
    }

    var me: Member { data.me }
    var activeSpace: Space? { data.spaces.first { $0.id == activeSpaceID } }
    var activeChannels: [Channel] { data.channels.filter { $0.spaceID == activeSpaceID } }
    var activePosts: [Post] { data.posts.filter { $0.spaceID == activeSpaceID }.sorted { $0.createdAt > $1.createdAt } }
    var socialPlatforms: [SocialPlatform] { SocialPlatform.defaults + addedPlatforms }

    func platform(_ id: String) -> SocialPlatform? { socialPlatforms.first { $0.id == id } }

    func addPlatform(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let existing = socialPlatforms.first(where: { $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            destination = .platform(existing.id)
            return
        }
        let id = UUID().uuidString
        let platform = SocialPlatform(id: id, name: clean, symbol: "bubble.left.and.bubble.right.fill", color: "purple")
        addedPlatforms.append(platform)
        UserDefaults.standard.set(try? JSONEncoder().encode(addedPlatforms), forKey: "addedSocialPlatforms")
        destination = .platform(id)
    }

    func member(_ id: UUID) -> Member? {
        if data.me.id == id { return data.me }
        return data.members.first { $0.id == id }
    }

    func chooseSpace(_ id: UUID) {
        activeSpaceID = id
        destination = .home
    }

    func createSpace(name: String, detail: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let space = Space(name: clean, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines), symbol: "circle.grid.2x2.fill", color: "purple")
        data.spaces.append(space)
        data.channels.append(Channel(spaceID: space.id, name: "general", topic: "A place for everyone"))
        chooseSpace(space.id)
        save()
    }

    func createChannel(name: String, topic: String) {
        guard let spaceID = activeSpaceID else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "-")
        guard !clean.isEmpty, !data.channels.contains(where: { $0.spaceID == spaceID && $0.name == clean }) else { return }
        let channel = Channel(spaceID: spaceID, name: clean, topic: topic.trimmingCharacters(in: .whitespacesAndNewlines))
        data.channels.append(channel)
        destination = .channel(channel.id)
        save()
    }

    func startConversation(with memberID: UUID) {
        if let existing = data.conversations.first(where: { $0.memberID == memberID }) {
            destination = .conversation(existing.id)
        } else {
            let conversation = Conversation(memberID: memberID)
            data.conversations.append(conversation)
            destination = .conversation(conversation.id)
            save()
        }
    }

    func send(_ text: String, to destination: AppDestination) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        switch destination {
        case .channel(let id):
            data.messages.append(Message(channelID: id, authorID: me.id, text: clean))
        case .conversation(let id):
            data.messages.append(Message(conversationID: id, authorID: me.id, text: clean))
        default: return
        }
        save()
    }

    func messages(for destination: AppDestination) -> [Message] {
        switch destination {
        case .channel(let id): return data.messages.filter { $0.channelID == id }.sorted { $0.sentAt < $1.sentAt }
        case .conversation(let id): return data.messages.filter { $0.conversationID == id }.sorted { $0.sentAt < $1.sentAt }
        default: return []
        }
    }

    func publish(_ text: String) {
        guard let spaceID = activeSpaceID else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        data.posts.append(Post(spaceID: spaceID, authorID: me.id, text: clean))
        save()
    }

    func toggleLike(_ postID: UUID) {
        guard let index = data.posts.firstIndex(where: { $0.id == postID }) else { return }
        if data.posts[index].likedBy.contains(me.id) {
            data.posts[index].likedBy.remove(me.id)
        } else {
            data.posts[index].likedBy.insert(me.id)
        }
        save()
    }

    func updateProfile(name: String, handle: String, status: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHandle = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanHandle.isEmpty else { return }
        data.me.name = cleanName
        data.me.handle = cleanHandle
        data.me.status = status.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    private func save() {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }

    private static func sampleData() -> AppData {
        let me = Member(name: "You", handle: "you", color: "purple", status: "Exploring spaces")
        let maya = Member(name: "Maya Chen", handle: "mayachen", color: "pink")
        let noah = Member(name: "Noah Williams", handle: "noahw", color: "blue")
        let ari = Member(name: "Ari Patel", handle: "arip", color: "orange")
        let design = Space(name: "Design Circle", detail: "A home for curious creators", symbol: "paintpalette.fill", color: "purple")
        let makers = Space(name: "Makers Club", detail: "Build, share, learn", symbol: "hammer.fill", color: "orange")
        let general = Channel(spaceID: design.id, name: "general", topic: "Good conversations start here")
        let inspiration = Channel(spaceID: design.id, name: "inspiration", topic: "Things worth sharing")
        let feedback = Channel(spaceID: design.id, name: "feedback", topic: "Thoughtful work in progress")
        let makerGeneral = Channel(spaceID: makers.id, name: "general", topic: "The makers' lounge")
        let projects = Channel(spaceID: makers.id, name: "projects", topic: "What are you building?")
        let mayaChat = Conversation(memberID: maya.id)
        let noahChat = Conversation(memberID: noah.id)
        return AppData(
            me: me, members: [maya, noah, ari], spaces: [design, makers],
            channels: [general, inspiration, feedback, makerGeneral, projects],
            conversations: [mayaChat, noahChat],
            messages: [
                Message(channelID: general.id, authorID: maya.id, text: "Welcome to Design Circle! Share what you're working on this week.", sentAt: .now.addingTimeInterval(-7200)),
                Message(channelID: general.id, authorID: noah.id, text: "I’m exploring a new way to bring community and conversations together.", sentAt: .now.addingTimeInterval(-5400)),
                Message(channelID: inspiration.id, authorID: ari.id, text: "Found a beautiful type specimen today. The little details make it sing.", sentAt: .now.addingTimeInterval(-3600)),
                Message(conversationID: mayaChat.id, authorID: maya.id, text: "Hey! Great to see you here 👋", sentAt: .now.addingTimeInterval(-1800)),
                Message(conversationID: noahChat.id, authorID: noah.id, text: "Let me know when you have a moment to catch up.", sentAt: .now.addingTimeInterval(-900))
            ],
            posts: [
                Post(spaceID: design.id, authorID: maya.id, text: "A little reminder to share the messy middle. The best ideas often start as rough sketches.", createdAt: .now.addingTimeInterval(-10800), likedBy: [noah.id, ari.id]),
                Post(spaceID: design.id, authorID: noah.id, text: "What’s one small detail in an app that made you smile recently?", createdAt: .now.addingTimeInterval(-86400), likedBy: [maya.id]),
                Post(spaceID: makers.id, authorID: ari.id, text: "This week’s goal: ship a tiny project and share what I learned.", createdAt: .now.addingTimeInterval(-18000), likedBy: [maya.id])
            ]
        )
    }
}
