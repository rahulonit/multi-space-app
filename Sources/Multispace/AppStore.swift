import Foundation
import Combine
import AppKit
import LocalAuthentication
import CryptoKit

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
    @Published var userProfile: UserProfile = .init() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(userProfile), forKey: "userProfile") }
    }
    @Published var activeSpaceID: UUID?
    @Published var searchText = ""
    @Published private(set) var socialPlatforms: [SocialPlatform] = SocialPlatform.defaults
    @Published private(set) var platformAccounts: [PlatformAccount] = []
    @Published private(set) var selectedAccountIDs: [String: UUID] = [:]

    @Published var editingPlatform: SocialPlatform?
    @Published private(set) var platformActivity: [UUID: PlatformActivitySnapshot] = [:]
    @Published var platformSummaries: [String: PlatformConversationSummary] = [:]
    @Published var isSplitView: Bool = false
    @Published var splitDestination: AppDestination? = nil
    @Published var splitAccountIDs: [String: UUID] = [:]
    @Published var showingCommandPalette: Bool = false
    @Published var isAppLocked: Bool = false
    @Published var lastActiveTime: Date = .now
    @Published var toastMessage: String?

    private var cancellables = Set<AnyCancellable>()
    private let fileURL: URL

    init() {
        // Keep app data in Application Support so it survives app launches without a server.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("PINGGO", isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent("Multispace", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let primaryFileURL = directory.appendingPathComponent("data.json")
        let legacyFileURL = legacyDir.appendingPathComponent("data.json")
        fileURL = primaryFileURL
        if let saved = (try? Data(contentsOf: primaryFileURL)) ?? (try? Data(contentsOf: legacyFileURL)),
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
        saveAccounts()
        if let saved = UserDefaults.standard.data(forKey: "appPreferences"),
           let decoded = try? JSONDecoder().decode(AppPreferences.self, from: saved) {
            preferences = decoded
        }
        if let saved = UserDefaults.standard.data(forKey: "userProfile"),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: saved) {
            userProfile = decoded
        } else {
            userProfile.displayName = data.me.name
        }
        if preferences.openTo == "Last Platform",
           let id = UserDefaults.standard.string(forKey: "lastPlatformID"), platform(id) != nil {
            destination = .platform(id)
        }
        if preferences.appLockEnabled {
            isAppLocked = true
        }
        loadPlatformActivity()
        refreshSummaries()

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

    func splitAccount(for platformID: String) -> PlatformAccount? {
        let list = accounts(for: platformID)
        if let id = splitAccountIDs[platformID], let match = list.first(where: { $0.id == id }) {
            return match
        }
        let primaryID = selectedAccount(for: platformID)?.id
        return list.first(where: { $0.id != primaryID }) ?? list.first
    }

    func selectSplitAccount(_ id: UUID) {
        guard let account = account(id) else { return }
        splitAccountIDs[account.platformID] = id
        // Ensure primary pane doesn't show the exact same account
        if selectedAccountIDs[account.platformID] == id {
            if let alternative = accounts(for: account.platformID).first(where: { $0.id != id }) {
                selectedAccountIDs[account.platformID] = alternative.id
                saveAccounts()
            }
        }
    }

    func ensureDifferentSplitAccount(for platformID: String) {
        let all = accounts(for: platformID)
        let primaryID = selectedAccount(for: platformID)?.id
        if let other = all.first(where: { $0.id != primaryID }) {
            splitAccountIDs[platformID] = other.id
        } else {
            // Only 1 account exists: auto-create a 2nd account for this platform
            if let newAcc = addAccount(to: platformID, name: "Work", selectAsPrimary: false) {
                splitAccountIDs[platformID] = newAcc.id
            }
        }
    }

    func account(_ id: UUID) -> PlatformAccount? { platformAccounts.first { $0.id == id } }

    func selectAccount(_ id: UUID, navigate: Bool = true) {
        guard let account = account(id) else { return }
        selectedAccountIDs[account.platformID] = id
        // If split view is active on the same platform and showing the same account, switch split pane
        if isSplitView, splitAccountIDs[account.platformID] == id {
            if let alternative = accounts(for: account.platformID).first(where: { $0.id != id }) {
                splitAccountIDs[account.platformID] = alternative.id
            }
        }
        saveAccounts()
        if navigate {
            destination = .platform(account.platformID)
            if isSplitView {
                splitDestination = .platform(account.platformID)
                ensureDifferentSplitAccount(for: account.platformID)
            }
        }
    }

    @discardableResult
    func addAccount(to platformID: String, name: String, selectAsPrimary: Bool = true) -> PlatformAccount? {
        guard platform(platformID) != nil else { return nil }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = accounts(for: platformID).count + 1
        let defaultName = count == 2 ? "Work" : "Account \(count)"
        let account = PlatformAccount(platformID: platformID,
                                      name: clean.isEmpty ? defaultName : String(clean.prefix(50)))
        platformAccounts.append(account)
        if selectAsPrimary {
            selectAccount(account.id)
        } else {
            saveAccounts()
        }
        return account
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

    func updatePlatformActivity(accountID: UUID, title: String, messages: [[String: String]], notifications: [String], rawNotifications: [[String: String]] = []) {
        guard account(accountID) != nil else { return }
        let unread: Int? = {
            guard title.first == "(", let end = title.firstIndex(of: ")") else { return nil }
            return Int(title[title.index(after: title.startIndex)..<end])
        }()
        let previews = messages.prefix(15).enumerated().compactMap { index, item -> PlatformMessagePreview? in
            let sender = (item["sender"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let content = (item["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let time = (item["time"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let link = (item["link"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isUnreadExplicit = item["unread"] == "true"
            let isUnreadByCount = (unread ?? 0) > 0 && index < (unread ?? 0)
            let unreadFlag = isUnreadExplicit || isUnreadByCount

            guard !content.isEmpty else { return nil }
            return .init(id: "\(accountID)-\(index)-\(sender)-\(content)",
                         sender: String(sender.prefix(80)),
                         text: String(content.prefix(240)),
                         time: time.isEmpty ? nil : String(time.prefix(30)),
                         linkURL: link.isEmpty ? nil : link,
                         isUnread: unreadFlag)
        }
        let alerts = Array(Set(notifications.map {
            String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        }.filter { !$0.isEmpty })).sorted().prefix(12)

        let notifPreviews: [PlatformNotificationPreview] = rawNotifications.prefix(15).enumerated().compactMap { index, item in
            let itemTitle = (item["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let itemText = (item["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let itemTime = (item["time"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let itemLink = (item["link"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let itemCat = (item["category"] ?? "general").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !itemText.isEmpty || !itemTitle.isEmpty else { return nil }
            return PlatformNotificationPreview(
                id: "\(accountID)-notif-\(index)-\(itemTitle)-\(itemText)",
                title: itemTitle.isEmpty ? "Notice" : String(itemTitle.prefix(80)),
                text: itemText.isEmpty ? itemTitle : String(itemText.prefix(240)),
                time: itemTime.isEmpty ? nil : String(itemTime.prefix(40)),
                linkURL: itemLink.isEmpty ? nil : itemLink,
                category: itemCat.isEmpty ? "general" : itemCat
            )
        }

        let next = PlatformActivitySnapshot(
            unreadCount: unread,
            messages: previews,
            notifications: Array(alerts),
            notificationPreviews: notifPreviews.isEmpty ? nil : notifPreviews,
            updatedAt: .now
        )
        if let previous = platformActivity[accountID],
           previous.unreadCount == next.unreadCount,
           previous.messages == next.messages,
           previous.notifications == next.notifications,
           previous.notificationPreviews == next.notificationPreviews { return }
        platformActivity[accountID] = next
        savePlatformActivity()
        updateDockBadge()
        refreshSummaries()
    }

    func refreshSummaries() {
        var map: [String: PlatformConversationSummary] = [:]
        for platform in socialPlatforms {
            let accs = accounts(for: platform.id)
            var msgs: [PlatformMessagePreview] = []
            var unread = 0
            for acc in accs {
                if let snap = platformActivity[acc.id] {
                    msgs.append(contentsOf: snap.messages)
                    unread += snap.unreadCount ?? 0
                }
            }
            map[platform.id] = ConversationSummaryService.shared.generateSummary(
                for: platform,
                accounts: accs,
                messages: msgs,
                unreadCount: unread
            )
        }
        map["all"] = ConversationSummaryService.shared.generateExecutiveBriefing(
            platforms: socialPlatforms,
            accounts: platformAccounts,
            activity: platformActivity
        )
        self.platformSummaries = map
    }

    private func loadPlatformActivity() {
        if let saved = UserDefaults.standard.data(forKey: "savedPlatformActivity"),
           let decoded = try? JSONDecoder().decode([String: PlatformActivitySnapshot].self, from: saved) {
            var restored: [UUID: PlatformActivitySnapshot] = [:]
            for (key, val) in decoded {
                if let uuid = UUID(uuidString: key) {
                    restored[uuid] = val
                }
            }
            self.platformActivity = restored
            updateDockBadge()
            refreshSummaries()
        }
    }

    private func savePlatformActivity() {
        var encodable: [String: PlatformActivitySnapshot] = [:]
        for (key, val) in platformActivity {
            encodable[key.uuidString] = val
        }
        if let encoded = try? JSONEncoder().encode(encodable) {
            UserDefaults.standard.set(encoded, forKey: "savedPlatformActivity")
        }
    }

    func openPlatformInbox(accountID: UUID, messageURL: String? = nil) {
        guard let account = account(accountID) else { return }
        selectAccount(accountID, navigate: true)
        let session = PortalSessionRegistry.shared.existingSession(for: accountID)
        session?.wake()
        session?.resume()
        if let messageURL, let url = URL(string: messageURL), url.scheme == "https" {
            session?.load(url)
        } else if let platform = platform(account.platformID), let inboxURL = platform.inboxURL {
            let currentStr = session?.currentURL?.absoluteString ?? ""
            if !currentStr.contains(inboxURL.path) && !currentStr.isEmpty {
                session?.load(inboxURL)
            }
        }
    }

    func openPlatformNotifications(accountID: UUID, notificationURL: String? = nil) {
        guard let account = account(accountID) else { return }
        selectAccount(accountID, navigate: true)
        let session = PortalSessionRegistry.shared.existingSession(for: accountID)
        session?.wake()
        session?.resume()
        if let notificationURL, let url = URL(string: notificationURL), url.scheme?.hasPrefix("http") == true {
            session?.load(url)
        } else if let platform = platform(account.platformID), let notifURL = platform.notificationsURL ?? platform.resolvedWebsiteURL {
            session?.load(notifURL)
        }
    }

    func refreshAllPortals() {
        for account in platformAccounts {
            PortalSessionRegistry.shared.wakeSession(accountID: account.id)
            if let session = PortalSessionRegistry.shared.existingSession(for: account.id) {
                session.wake()
                session.resume()
                session.forceCollect()
            }
        }
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
            let targetPlatformID: String? = {
                if case .platform(let id) = destination { return id }
                return socialPlatforms.first?.id
            }()
            if let platformID = targetPlatformID {
                destination = .platform(platformID)
                splitDestination = .platform(platformID)
                ensureDifferentSplitAccount(for: platformID)
            } else {
                splitDestination = .inbox
            }
            isSplitView = true
        }
    }

    func openInSplitView(platformID: String, accountID: UUID? = nil) {
        destination = .platform(platformID)
        splitDestination = .platform(platformID)
        let all = accounts(for: platformID)
        if let accountID {
            splitAccountIDs[platformID] = accountID
            if let other = all.first(where: { $0.id != accountID }) {
                selectedAccountIDs[platformID] = other.id
            } else {
                selectedAccountIDs[platformID] = accountID
                if let newAcc = addAccount(to: platformID, name: "Work", selectAsPrimary: false) {
                    splitAccountIDs[platformID] = newAcc.id
                }
            }
        } else {
            ensureDifferentSplitAccount(for: platformID)
        }
        saveAccounts()
        isSplitView = true
    }

    func openInSplitView(_ dest: AppDestination) {
        if case .platform(let platformID) = dest {
            openInSplitView(platformID: platformID, accountID: nil)
        } else {
            splitDestination = dest
            isSplitView = true
        }
    }

    func closeSplitView() {
        isSplitView = false
    }

    var currentActiveAccountIDs: [UUID] {
        var ids: [UUID] = []
        if case .platform(let id) = destination, let account = selectedAccount(for: id) {
            ids.append(account.id)
        }
        if isSplitView, case .platform(let id) = splitDestination, let account = splitAccount(for: id) {
            ids.append(account.id)
        }
        return ids
    }

    var totalUnreadCount: Int {
        platformActivity.values.reduce(0) { $0 + ($1.unreadCount ?? 0) }
    }

    func isSessionHibernated(accountID: UUID) -> Bool {
        PortalSessionRegistry.shared.isHibernated(accountID: accountID)
    }

    func isSessionMuted(accountID: UUID) -> Bool {
        PortalSessionRegistry.shared.isMuted(accountID: accountID)
    }

    func toggleSessionMute(accountID: UUID) {
        PortalSessionRegistry.shared.toggleMute(accountID: accountID)
        objectWillChange.send()
    }

    func wakeSession(accountID: UUID) {
        PortalSessionRegistry.shared.wakeSession(accountID: accountID)
        objectWillChange.send()
    }

    func sleepingSessionCount() -> Int {
        PortalSessionRegistry.shared.sleepingSessionCount()
    }

    func hibernateInactiveNow() {
        PortalSessionRegistry.shared.hibernateAllInactive(activeAccountIDs: Set(currentActiveAccountIDs))
        objectWillChange.send()
    }

    func triggerAddPlatform() {
        NotificationCenter.default.post(name: Notification.Name("ShowAddPlatformSheet"), object: nil)
    }

    func recordActivity() {
        lastActiveTime = .now
    }

    func lockApp() {
        isAppLocked = true
    }

    private func hashPin(_ pin: String, salt: String) -> String {
        let combined = salt + ":" + pin + ":pinggo_secure_salt"
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    var hasCustomPin: Bool {
        !preferences.customPinHash.isEmpty && !preferences.customPinSalt.isEmpty
    }

    func setCustomPin(_ newPin: String, hint: String? = nil) {
        let salt = UUID().uuidString
        let hash = hashPin(newPin, salt: salt)
        preferences.customPinSalt = salt
        preferences.customPinHash = hash
        preferences.customPinHint = hint ?? ""
        objectWillChange.send()
    }

    func removeCustomPin() {
        preferences.customPinSalt = ""
        preferences.customPinHash = ""
        preferences.customPinHint = ""
        if preferences.lockMethod == "customPin" {
            preferences.lockMethod = "biometric"
        }
        objectWillChange.send()
    }

    func verifyCustomPin(_ pin: String) -> Bool {
        guard hasCustomPin else { return false }
        let calculated = hashPin(pin, salt: preferences.customPinSalt)
        return calculated == preferences.customPinHash
    }

    func unlockWithPin(_ pin: String) -> Bool {
        if verifyCustomPin(pin) {
            isAppLocked = false
            recordActivity()
            return true
        }
        return false
    }

    func unlockWithDeviceOwnerFallback() async -> Bool {
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
                localizedReason: "Unlock PINGGO with Mac administrator credentials"
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

    func unlockApp() async -> Bool {
        if preferences.lockMethod == "customPin" {
            return false
        }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if hasCustomPin {
                return false
            }
            isAppLocked = false
            recordActivity()
            return true
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock PINGGO to access your social apps"
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

    func signInWith(provider: String, name: String, email: String, tier: String = "PINGGO Pro (Active)") {
        userProfile.isSignedIn = true
        userProfile.provider = provider
        userProfile.displayName = name
        userProfile.email = email
        userProfile.subscriptionTier = tier
        userProfile.subscriptionStatus = "Active"
        userProfile.lastCloudBackup = .now
        data.me.name = name
        save()
        showToast("Signed in with \(provider). Subscription & spaces synced to cloud.")
        objectWillChange.send()
    }

    func signOutProfile() {
        userProfile.isSignedIn = false
        userProfile.provider = nil
        userProfile.subscriptionTier = "Free"
        userProfile.subscriptionStatus = "Active"
        showToast("Signed out. Operating in local mode.")
        objectWillChange.send()
    }

    func triggerCloudSync() {
        userProfile.lastCloudBackup = .now
        showToast("Cloud sync complete: \(socialPlatforms.count) platforms, \(platformAccounts.count) accounts & subscription synced.")
        objectWillChange.send()
    }

    func exportUserDataJSON() -> String {
        let exportData: [String: Any] = [
            "exportDate": ISO8601DateFormatter().string(from: .now),
            "app": "PINGGO",
            "profile": [
                "displayName": userProfile.displayName,
                "email": userProfile.email,
                "provider": userProfile.provider ?? "None",
                "subscriptionTier": userProfile.subscriptionTier
            ],
            "platforms": socialPlatforms.map { ["id": $0.id, "name": $0.name, "url": $0.websiteURL ?? ""] },
            "accounts": platformAccounts.map { ["id": $0.id.uuidString, "platformID": $0.platformID, "name": $0.name] },
            "preferences": [
                "appearance": preferences.appearance,
                "accent": preferences.accent,
                "compactMode": preferences.compactMode,
                "autoLockMinutes": preferences.autoLockMinutes,
                "lockMethod": preferences.lockMethod
            ]
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
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

    func updateProfileDetails(name: String, email: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty {
            data.me.name = cleanName
            userProfile.displayName = cleanName
        }
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanEmail.isEmpty {
            userProfile.email = cleanEmail
        }
        save()
        showToast("Profile details updated!")
        objectWillChange.send()
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if self.toastMessage == message {
                self.toastMessage = nil
            }
        }
    }

    func importSessionCookies(accountID: UUID, platformID: String, rawInput: String) async {
        guard let platform = platform(platformID),
              let host = platform.resolvedWebsiteURL?.host else { return }

        // Derive root cookie domain (e.g. "www.linkedin.com" -> ".linkedin.com")
        let domain: String
        let parts = host.split(separator: ".")
        if parts.count >= 2 {
            domain = "." + parts.suffix(2).joined(separator: ".")
        } else {
            domain = host
        }

        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If the string does not contain "=", treat it as a direct session token (e.g. li_at for LinkedIn)
        if !trimmed.contains("=") {
            let tokenKey = platformID == "linkedin" ? "li_at" : "session"
            await PortalSessionRegistry.shared.injectTokenAndReload(
                accountID: accountID,
                tokenName: tokenKey,
                tokenValue: trimmed,
                domain: domain
            )
            showToast("Imported \(platform.name) session token!")
            return
        }

        // Otherwise parse cookie string "name=value; name2=value2"
        await PortalSessionRegistry.shared.injectCookiesAndReload(
            accountID: accountID,
            cookies: trimmed,
            domain: domain
        )
        showToast("Imported \(platform.name) session cookies!")
    }

    func detectAndImportClipboardSession(accountID: UUID, platformID: String) async -> Bool {
        guard let clipboardString = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clipboardString.isEmpty else { return false }

        // Case 1: Clipboard contains pinggo://auth-sync URL
        if (clipboardString.hasPrefix("pinggo://auth-sync") || clipboardString.hasPrefix("multispace://auth-sync")),
           let url = URL(string: clipboardString) {
            handleDeepLink(url)
            return true
        }

        // Case 2: Clipboard contains cookie string or session token
        if clipboardString.contains("=") || (platformID == "linkedin" && clipboardString.count > 20) {
            await importSessionCookies(accountID: accountID, platformID: platformID, rawInput: clipboardString)
            return true
        }

        return false
    }

    func handleDeepLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "multispace" || scheme == "pinggo" else { return }
        let hostAction = url.host?.lowercased() ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let queryItems = components.queryItems ?? []

        func value(for name: String) -> String? {
            queryItems.first(where: { $0.name.lowercased() == name.lowercased() })?.value
        }

        switch hostAction {
        case "auth-sync", "import-cookies", "sync":
            let platformParam = value(for: "platform")?.lowercased()
            let hostParam = value(for: "host")?.lowercased()
            let cookiesParam = value(for: "cookies") ?? value(for: "cookie") ?? ""
            let accountIDParam = value(for: "accountid")

            // Identify platform
            let targetPlatform: SocialPlatform?
            if let p = platformParam, let found = socialPlatforms.first(where: { $0.id.lowercased() == p }) {
                targetPlatform = found
            } else if let h = hostParam {
                targetPlatform = socialPlatforms.first(where: {
                    guard let host = $0.resolvedWebsiteURL?.host?.lowercased() else { return false }
                    return host == h || host.hasSuffix(".\(h)") || h.hasSuffix(".\(host)")
                })
            } else {
                targetPlatform = socialPlatforms.first(where: { $0.id == "linkedin" })
            }

            guard let platform = targetPlatform else {
                showToast("Unknown platform for sync link")
                return
            }

            // Find account
            let account: PlatformAccount?
            if let accStr = accountIDParam, let uuid = UUID(uuidString: accStr) {
                account = platformAccounts.first(where: { $0.id == uuid })
            } else {
                account = selectedAccount(for: platform.id)
            }

            guard let targetAccount = account else {
                showToast("No account found for \(platform.name)")
                return
            }

            if !cookiesParam.isEmpty {
                Task {
                    await self.importSessionCookies(accountID: targetAccount.id, platformID: platform.id, rawInput: cookiesParam)
                }
            }
            destination = .platform(platform.id)

        case "import-token":
            let platformParam = value(for: "platform")?.lowercased() ?? "linkedin"
            let tokenParam = value(for: "token") ?? ""
            guard let platform = socialPlatforms.first(where: { $0.id.lowercased() == platformParam }),
                  let account = selectedAccount(for: platform.id),
                  !tokenParam.isEmpty else { return }
            Task {
                await self.importSessionCookies(accountID: account.id, platformID: platform.id, rawInput: tokenParam)
            }
            destination = .platform(platform.id)

        case "open":
            if let platformParam = value(for: "platform")?.lowercased(),
               let platform = socialPlatforms.first(where: { $0.id.lowercased() == platformParam }) {
                destination = .platform(platform.id)
            }

        default:
            break
        }
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
