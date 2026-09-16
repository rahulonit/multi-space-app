import Foundation
import Combine
import AppKit
import LocalAuthentication

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var data: AppData
    @Published var destination: AppDestination = .home {
        didSet {
            recordActivity()
            if case .platform(let id) = destination {
                UserDefaults.standard.set(id, forKey: "lastPlatformID")
            }
        }
    }
    @Published var preferences: AppPreferences = .init() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(preferences), forKey: "appPreferences") }
    }
    @Published var activeSpaceID: UUID?
    @Published var searchText = ""
    @Published private(set) var socialPlatforms: [SocialPlatform] = SocialPlatform.defaults
    @Published private(set) var platformAccounts: [PlatformAccount] = []
    @Published private(set) var selectedAccountIDs: [String: UUID] = [:]
    @Published var selectedFeedAccountID: UUID? {
        didSet { UserDefaults.standard.set(selectedFeedAccountID?.uuidString, forKey: "selectedFeedAccountID") }
    }
    @Published var editingPlatform: SocialPlatform?
    @Published private(set) var platformActivity: [UUID: PlatformActivitySnapshot] = [:]
    @Published var isSplitView: Bool = false
    @Published var splitDestination: AppDestination? = nil
    @Published var showingCommandPalette: Bool = false
    @Published var isAppLocked: Bool = false
    @Published var lastActiveTime: Date = .now

    private var cancellables = Set<AnyCancellable>()
    private let fileURL: URL

    init() {
        // Keep app data in Application Support so it survives app launches without a server.
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
        // Migrate the earlier custom-only preference without changing existing app data.
        if let saved = UserDefaults.standard.data(forKey: "socialPlatforms"),
           let decoded = try? JSONDecoder().decode([SocialPlatform].self, from: saved) {
            socialPlatforms = decoded
        } else if let saved = UserDefaults.standard.data(forKey: "addedSocialPlatforms"),
                  let decoded = try? JSONDecoder().decode([SocialPlatform].self, from: saved) {
            socialPlatforms = SocialPlatform.defaults + decoded
        }
        socialPlatforms = socialPlatforms.map { platform in
            var updated = platform
            if updated.websiteURL == nil,
               let match = SocialPlatform.suggestions.first(where: {
                   $0.name.localizedCaseInsensitiveCompare(updated.name) == .orderedSame
               }) {
                updated.websiteURL = match.websiteURL
            }
            return updated
        }
        if let saved = UserDefaults.standard.data(forKey: "platformAccounts"),
           let decoded = try? JSONDecoder().decode([PlatformAccount].self, from: saved) {
            platformAccounts = decoded
        }
        for platform in socialPlatforms where !platformAccounts.contains(where: { $0.platformID == platform.id }) {
            platformAccounts.append(PlatformAccount(platformID: platform.id, name: "Personal", usesLegacyStore: true))
        }
        platformAccounts.removeAll { account in !socialPlatforms.contains(where: { $0.id == account.platformID }) }
        if let saved = UserDefaults.standard.data(forKey: "selectedAccountIDs"),
           let decoded = try? JSONDecoder().decode([String: UUID].self, from: saved) {
            selectedAccountIDs = decoded
        }
        if let saved = UserDefaults.standard.string(forKey: "selectedFeedAccountID"),
           let id = UUID(uuidString: saved), account(id) != nil {
            selectedFeedAccountID = id
        }
        saveAccounts()
        if let saved = UserDefaults.standard.data(forKey: "appPreferences"),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: saved) {
            preferences = decoded
        }
        if preferences.openTo == "Last Platform",
           let id = UserDefaults.standard.string(forKey: "lastPlatformID"), platform(id) != nil {
            destination = .platform(id)
        }
        if preferences.appLockEnabled {
            isAppLocked = true
        }

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.preferences.appLockEnabled else { return }
                self.isAppLocked = true
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.preferences.appLockEnabled else { return }
                self.isAppLocked = true
            }
            .store(in: &cancellables)

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.checkAutoLock()
                if self.preferences.tabFreezingEnabled {
                    let active = Set(self.currentActiveAccountIDs)
                    PortalSessionRegistry.shared.cleanupInactiveSessions(
                        activeAccountIDs: active,
                        timeout: Double(self.preferences.tabFreezeMinutes * 60)
                    )
                }
            }
            .store(in: &cancellables)
    }

    var me: Member { data.me }
    var activeSpace: Space? { data.spaces.first { $0.id == activeSpaceID } }
    var activeChannels: [Channel] { data.channels.filter { $0.spaceID == activeSpaceID } }
    var activePosts: [Post] { data.posts.filter { $0.spaceID == activeSpaceID }.sorted { $0.createdAt > $1.createdAt } }
    func platform(_ id: String) -> SocialPlatform? { socialPlatforms.first { $0.id == id } }
    func accounts(for platformID: String) -> [PlatformAccount] {
        platformAccounts.filter { $0.platformID == platformID }
    }
    func selectedAccount(for platformID: String) -> PlatformAccount? {
        let list = accounts(for: platformID)
        return list.first { $0.id == selectedAccountIDs[platformID] } ?? list.first
    }
    func account(_ id: UUID) -> PlatformAccount? { platformAccounts.first { $0.id == id } }

    func selectAccount(_ id: UUID, navigate: Bool = true) {
        guard let account = account(id) else { return }
        selectedAccountIDs[account.platformID] = id
        if ["instagram", "facebook", "x", "linkedin", "tiktok"].contains(account.platformID) {
            selectedFeedAccountID = id
        }
        saveAccounts()
        if navigate { destination = .platform(account.platformID) }
    }

    func addAccount(to platformID: String, name: String) {
        guard platform(platformID) != nil else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = accounts(for: platformID).count + 1
        let account = PlatformAccount(platformID: platformID,
                                      name: clean.isEmpty ? "Account \(count)" : String(clean.prefix(50)))
        platformAccounts.append(account)
        selectAccount(account.id)
    }

    func renameAccount(_ id: UUID, to name: String) {
        guard let index = platformAccounts.firstIndex(where: { $0.id == id }) else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        platformAccounts[index].name = String(clean.prefix(50))
        saveAccounts()
    }

    func removeAccount(_ id: UUID) {
        guard let account = account(id), !account.usesLegacyStore,
              accounts(for: account.platformID).count > 1 else { return }
        PortalSessionRegistry.shared.forget(account)
        platformAccounts.removeAll { $0.id == id }
        platformActivity.removeValue(forKey: id)
        if selectedFeedAccountID == id { selectedFeedAccountID = nil }
        if selectedAccountIDs[account.platformID] == id {
            selectedAccountIDs[account.platformID] = accounts(for: account.platformID).first?.id
        }
        saveAccounts()
        updateDockBadge()
    }

    private func saveAccounts() {
        UserDefaults.standard.set(try? JSONEncoder().encode(platformAccounts), forKey: "platformAccounts")
        UserDefaults.standard.set(try? JSONEncoder().encode(selectedAccountIDs), forKey: "selectedAccountIDs")
    }

    func isPlatformNameAvailable(_ name: String, excluding id: String? = nil) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clean.isEmpty && !socialPlatforms.contains {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame
        }
    }

    func addPlatform(name: String, websiteURL: String? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let existing = socialPlatforms.first(where: { $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }) {
            destination = .platform(existing.id)
            return
        }
        let platform = (SocialPlatform.defaults + SocialPlatform.suggestions).first { $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame }
            ?? SocialPlatform(id: UUID().uuidString, name: clean, symbol: "bubble.left.and.bubble.right.fill", color: "purple", websiteURL: websiteURL)
        if socialPlatforms.contains(where: { $0.id == platform.id }) {
            destination = .platform(platform.id)
            return
        }
        socialPlatforms.append(platform)
        platformAccounts.append(PlatformAccount(platformID: platform.id, name: "Personal", usesLegacyStore: true))
        saveAccounts()
        savePlatforms()
        destination = .platform(platform.id)
    }

    func updatePlatform(id: String, name: String, symbol: String, color: String, websiteURL: String?) {
        guard let index = socialPlatforms.firstIndex(where: { $0.id == id }),
              isPlatformNameAvailable(name, excluding: id) else { return }
        let original = socialPlatforms[index].officialIdentity
        socialPlatforms[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        socialPlatforms[index].symbol = symbol
        socialPlatforms[index].color = color
        socialPlatforms[index].websiteURL = websiteURL
        socialPlatforms[index].customIcon = original.map { symbol != $0.symbol }
        savePlatforms()
    }

    func removePlatform(_ id: String) {
        socialPlatforms.removeAll { $0.id == id }
        for account in accounts(for: id) {
            platformActivity.removeValue(forKey: account.id)
            PortalSessionRegistry.shared.forget(account)
            if selectedFeedAccountID == account.id { selectedFeedAccountID = nil }
        }
        platformAccounts.removeAll { $0.platformID == id }
        selectedAccountIDs.removeValue(forKey: id)
        saveAccounts()
        if destination == .platform(id) { destination = .home }
        if editingPlatform?.id == id { editingPlatform = nil }
        savePlatforms()
        updateDockBadge()
    }

    private func savePlatforms() {
        UserDefaults.standard.set(try? JSONEncoder().encode(socialPlatforms), forKey: "socialPlatforms")
    }

    func updatePlatformActivity(accountID: UUID, title: String, messages: [[String: String]], notifications: [String]) {
        guard account(accountID) != nil else { return }
        let unread: Int? = {
            guard title.first == "(", let end = title.firstIndex(of: ")") else { return nil }
            return Int(title[title.index(after: title.startIndex)..<end])
        }()
        let previews = messages.prefix(8).enumerated().compactMap { index, item -> PlatformMessagePreview? in
            let sender = (item["sender"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let content = (item["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return .init(id: "\(accountID)-\(index)-\(sender)-\(content)",
                         sender: String(sender.prefix(80)), text: String(content.prefix(240)))
        }
        let alerts = Array(Set(notifications.map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        }.filter { !$0.isEmpty })).sorted().prefix(8)
        let next = PlatformActivitySnapshot(unreadCount: unread, messages: previews,
                                            notifications: Array(alerts), updatedAt: .now)
        if let previous = platformActivity[accountID], previous.unreadCount == next.unreadCount,
           previous.messages == next.messages, previous.notifications == next.notifications { return }
        platformActivity[accountID] = next
        updateDockBadge()
    }

    func updateDockBadge() {
        let totalUnread = platformAccounts.compactMap { platformActivity[$0.id]?.unreadCount }.reduce(0, +)
        if totalUnread > 0 {
            NSApp.dockTile.badgeLabel = "\(totalUnread)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    func toggleSplitView() {
        if isSplitView {
            isSplitView = false
        } else {
            if splitDestination == nil {
                let currentPlatformID: String? = {
                    if case .platform(let id) = destination { return id }
                    return nil
                }()
                let alternative = socialPlatforms.first { $0.id != currentPlatformID } ?? socialPlatforms.first
                if let alternative {
                    splitDestination = .platform(alternative.id)
                } else {
                    splitDestination = .feed
                }
            }
            isSplitView = true
        }
    }

    func openInSplitView(_ dest: AppDestination) {
        splitDestination = dest
        isSplitView = true
    }

    func closeSplitView() {
        isSplitView = false
    }

    var currentActiveAccountIDs: [UUID] {
        var ids: [UUID] = []
        if case .platform(let id) = destination, let account = selectedAccount(for: id) {
            ids.append(account.id)
        }
        if isSplitView, case .platform(let id) = splitDestination, let account = selectedAccount(for: id) {
            ids.append(account.id)
        }
        return ids
    }

    func recordActivity() {
        lastActiveTime = .now
    }

    func lockApp() {
        isAppLocked = true
    }

    func unlockApp() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isAppLocked = false
            recordActivity()
            return true
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Multispace to access your social apps"
            )
            if success {
                self.isAppLocked = false
                self.recordActivity()
            }
            return success
        } catch {
            return false
        }
    }

    func checkAutoLock() {
        guard preferences.appLockEnabled, !isAppLocked else { return }
        if preferences.autoLockMinutes > 0 {
            let elapsed = Date.now.timeIntervalSince(lastActiveTime)
            if elapsed >= Double(preferences.autoLockMinutes * 60) {
                isAppLocked = true
            }
        }
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
        // A message belongs to either a channel or a direct conversation, never both.
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
        // Atomic writes prevent a partially written JSON file if the app closes during a save.
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: fileURL, options: .atomic)
    }

    private static func sampleData() -> AppData {
        // The sample graph gives a first launch useful content while all mutations remain local.
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
