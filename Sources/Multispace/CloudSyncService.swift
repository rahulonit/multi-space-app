import SwiftUI
import Foundation

// MARK: - Cloud Sync Models
struct CloudSyncPayload: Codable, Sendable {
    let deviceId: String
    let platform: String
    let timestamp: Date
    let spaces: [Space]?
    let preferences: SyncedPreferencesPayload?
    let bookmarks: [SyncedBookmarkItem]?
    let briefings: [SyncedBriefingItem]?

    init(
        deviceId: String,
        platform: String = "macOS",
        timestamp: Date = Date(),
        spaces: [Space]? = nil,
        preferences: SyncedPreferencesPayload? = nil,
        bookmarks: [SyncedBookmarkItem]? = nil,
        briefings: [SyncedBriefingItem]? = nil
    ) {
        self.deviceId = deviceId
        self.platform = platform
        self.timestamp = timestamp
        self.spaces = spaces
        self.preferences = preferences
        self.bookmarks = bookmarks
        self.briefings = briefings
    }
}

struct SyncedPreferencesPayload: Codable, Sendable {
    var appearance: String = "Follow System"
    var accent: String = "indigo"
    var compactMode: Bool = false
    var openLinksInAppBrowser: Bool = true
    var showVideoHoverPill: Bool = true
    var videoDownloadFolder: String = ""

    // AI & Credentials Settings
    var aiEnabled: Bool = true
    var aiProvider: String = "gemini"
    var openAiApiKey: String = ""
    var openAiModelTier: String = "gpt-4o-mini"
    var geminiApiKey: String = ""
    var geminiModelTier: String = "gemini-2.5-flash"
    var ollamaEndpoint: String = "http://localhost:11434"
    var ollamaModel: String = "llama3.2"
    var personaStyle: String = "direct"
    var defaultReplyTone: String = "Professional"
    var customAiPrompt: String = ""
    var syncAiSettings: Bool = true

    enum CodingKeys: String, CodingKey {
        case appearance, accent, compactMode, openLinksInAppBrowser, showVideoHoverPill, videoDownloadFolder
        case aiEnabled, aiProvider, openAiApiKey, openAiModelTier, geminiApiKey, geminiModelTier
        case ollamaEndpoint, ollamaModel, personaStyle, defaultReplyTone, customAiPrompt, syncAiSettings
    }

    init(
        appearance: String = "Follow System",
        accent: String = "indigo",
        compactMode: Bool = false,
        openLinksInAppBrowser: Bool = true,
        showVideoHoverPill: Bool = true,
        videoDownloadFolder: String = "",
        aiEnabled: Bool = true,
        aiProvider: String = "gemini",
        openAiApiKey: String = "",
        openAiModelTier: String = "gpt-4o-mini",
        geminiApiKey: String = "",
        geminiModelTier: String = "gemini-2.5-flash",
        ollamaEndpoint: String = "http://localhost:11434",
        ollamaModel: String = "llama3.2",
        personaStyle: String = "direct",
        defaultReplyTone: String = "Professional",
        customAiPrompt: String = "",
        syncAiSettings: Bool = true
    ) {
        self.appearance = appearance
        self.accent = accent
        self.compactMode = compactMode
        self.openLinksInAppBrowser = openLinksInAppBrowser
        self.showVideoHoverPill = showVideoHoverPill
        self.videoDownloadFolder = videoDownloadFolder
        self.aiEnabled = aiEnabled
        self.aiProvider = aiProvider
        self.openAiApiKey = openAiApiKey
        self.openAiModelTier = openAiModelTier
        self.geminiApiKey = geminiApiKey
        self.geminiModelTier = geminiModelTier
        self.ollamaEndpoint = ollamaEndpoint
        self.ollamaModel = ollamaModel
        self.personaStyle = personaStyle
        self.defaultReplyTone = defaultReplyTone
        self.customAiPrompt = customAiPrompt
        self.syncAiSettings = syncAiSettings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "Follow System"
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? "indigo"
        compactMode = try c.decodeIfPresent(Bool.self, forKey: .compactMode) ?? false
        openLinksInAppBrowser = try c.decodeIfPresent(Bool.self, forKey: .openLinksInAppBrowser) ?? true
        showVideoHoverPill = try c.decodeIfPresent(Bool.self, forKey: .showVideoHoverPill) ?? true
        videoDownloadFolder = try c.decodeIfPresent(String.self, forKey: .videoDownloadFolder) ?? ""
        aiEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiEnabled) ?? true
        aiProvider = try c.decodeIfPresent(String.self, forKey: .aiProvider) ?? "gemini"
        openAiApiKey = try c.decodeIfPresent(String.self, forKey: .openAiApiKey) ?? ""
        openAiModelTier = try c.decodeIfPresent(String.self, forKey: .openAiModelTier) ?? "gpt-4o-mini"
        geminiApiKey = try c.decodeIfPresent(String.self, forKey: .geminiApiKey) ?? ""
        geminiModelTier = try c.decodeIfPresent(String.self, forKey: .geminiModelTier) ?? "gemini-2.5-flash"
        ollamaEndpoint = try c.decodeIfPresent(String.self, forKey: .ollamaEndpoint) ?? "http://localhost:11434"
        ollamaModel = try c.decodeIfPresent(String.self, forKey: .ollamaModel) ?? "llama3.2"
        personaStyle = try c.decodeIfPresent(String.self, forKey: .personaStyle) ?? "direct"
        defaultReplyTone = try c.decodeIfPresent(String.self, forKey: .defaultReplyTone) ?? "Professional"
        customAiPrompt = try c.decodeIfPresent(String.self, forKey: .customAiPrompt) ?? ""
        syncAiSettings = try c.decodeIfPresent(Bool.self, forKey: .syncAiSettings) ?? true
    }
}

struct CloudPullResponse: Codable {
    let spaces: [Space]?
    let preferences: SyncedPreferencesPayload?
    let bookmarks: [SyncedBookmarkItem]?
    let briefings: [SyncedBriefingItem]?
    let pulledAt: String?
}

struct SyncedBookmarkItem: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let url: String
    let folder: String?
    let tags: [String]?
    let createdAt: Date
}

struct SyncedBriefingItem: Codable, Sendable, Identifiable {
    let id: String
    let dateString: String
    let headline: String
    let narrativeSummary: String
    let actionItems: [String]?
    let keyTopics: [String]?
    let createdAt: Date
}

struct CloudAuthResponse: Codable {
    let token: String
    let user: CloudUserResponse
}

struct CloudUserResponse: Codable {
    let id: String
    let email: String
    let displayName: String?
    let tier: String?
    let tierExpiresAt: String?
    let subscriptionStatus: String?
    let daysRemaining: Int?
    let isExpired: Bool?
    let planName: String?
}

struct CloudSubscriptionStatus: Codable, Sendable {
    let tier: String
    let subscriptionStatus: String
    let tierExpiresAt: String?
    let daysRemaining: Int
    let isExpired: Bool
    let needsRenewal: Bool
    let canRenew: Bool
    let planName: String?
}

struct CloudSubscriptionActionResponse: Codable, Sendable {
    let success: Bool
    let message: String
    let tier: String
    let subscriptionStatus: String
    let tierExpiresAt: String?
    let daysRemaining: Int
    let isExpired: Bool
    let planName: String?
}

// MARK: - Cloud Sync Service (Singleton)
@MainActor
final class CloudSyncService: ObservableObject {
    static let shared = CloudSyncService()

    @Published var isSyncing: Bool = false
    @Published var lastSyncedAt: Date? = nil
    @Published var syncStatusMessage: String = "Not Connected"
    @Published var syncError: String? = nil
    @Published var isCloudConnected: Bool = false
    @Published var currentUserEmail: String = ""

    private let deviceIdKey = "pinggo_device_id"

    private init() {
        let savedToken = UserDefaults.standard.data(forKey: "appPreferences")
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.cloudAuthToken ?? ""
        let savedEmail = UserDefaults.standard.data(forKey: "appPreferences")
            .flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }?.cloudUserEmail ?? ""

        if !savedToken.isEmpty {
            self.isCloudConnected = true
            self.currentUserEmail = savedEmail
            self.syncStatusMessage = "Ready to Sync"
        }
    }

    var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceIdKey) {
            return id
        }
        let newID = "mac-\(UUID().uuidString.prefix(8).lowercased())"
        UserDefaults.standard.set(newID, forKey: deviceIdKey)
        return newID
    }

    // MARK: - Authentication Methods
    enum CloudAuthResult: Sendable {
        case success(String)
        case failure(String)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .success(let m), .failure(let m): return m
            }
        }
    }

    func login(email: String, password: String, store: AppStore) async -> CloudAuthResult {
        isSyncing = true
        syncError = nil
        syncStatusMessage = "Checking account…"

        let baseURL = store.preferences.cloudServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(baseURL)/api/v1/auth/login") else {
            isSyncing = false
            syncError = "Invalid server URL"
            return .failure("Invalid server URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body: [String: Any] = [
            "email": cleanEmail,
            "password": password,
            "deviceId": deviceID,
            "platform": "macOS"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResp = response as? HTTPURLResponse else {
                isSyncing = false
                return .failure("Server unreachable. Please check connection.")
            }

            if httpResp.statusCode == 200 {
                let authResult = try JSONDecoder().decode(CloudAuthResponse.self, from: data)
                self.isCloudConnected = true
                self.currentUserEmail = authResult.user.email
                self.syncStatusMessage = "Connected as \(authResult.user.email)"
                self.syncError = nil

                store.preferences.cloudAuthToken = authResult.token
                store.preferences.cloudUserEmail = authResult.user.email
                store.preferences.cloudSyncEnabled = true

                // Synchronize store profile state
                let displayName = authResult.user.displayName ?? (cleanEmail.components(separatedBy: "@").first ?? "User")
                store.completeUserSignIn(name: displayName, email: authResult.user.email, provider: "Cloud Account")

                // Restore user subscription plan & validity
                self.applyUserSubscription(user: authResult.user, store: store)
                connectRealTimeWebSocket(store: store)

                // Automatically restore user settings, spaces, AI credentials, and bookmarks from database
                let hasRemote = await pullFromCloud(store: store)
                isSyncing = false

                if hasRemote {
                    store.showToast("Welcome back! Settings, spaces & plan restored.")
                } else {
                    await syncNow(store: store)
                    store.showToast("Signed in! Workspaces linked to account.")
                }
                return .success("Signed in successfully")
            } else if httpResp.statusCode == 401 {
                isSyncing = false
                let msg = "No account found for this email or password incorrect. If you don't have an account, please switch to Create Account."
                self.syncError = msg
                return .failure(msg)
            } else {
                isSyncing = false
                let errMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Authentication failed (HTTP \(httpResp.statusCode))"
                self.syncError = errMsg
                return .failure(errMsg)
            }
        } catch {
            isSyncing = false
            syncError = error.localizedDescription
            return .failure("Could not connect to server: \(error.localizedDescription)")
        }
    }

    func register(name: String, email: String, password: String, store: AppStore) async -> CloudAuthResult {
        isSyncing = true
        syncError = nil
        syncStatusMessage = "Creating account…"

        let baseURL = store.preferences.cloudServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(baseURL)/api/v1/auth/register") else {
            isSyncing = false
            return .failure("Invalid server URL")
        }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (cleanEmail.components(separatedBy: "@").first ?? "User") : name.trimmingCharacters(in: .whitespacesAndNewlines)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "email": cleanEmail,
            "password": password,
            "displayName": cleanName,
            "deviceId": deviceID,
            "platform": "macOS"
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResp = response as? HTTPURLResponse else {
                isSyncing = false
                return .failure("Server unreachable. Please check connection.")
            }

            if httpResp.statusCode == 200 || httpResp.statusCode == 201 {
                let authResult = try JSONDecoder().decode(CloudAuthResponse.self, from: data)
                self.isCloudConnected = true
                self.currentUserEmail = authResult.user.email
                self.syncStatusMessage = "Connected as \(authResult.user.email)"
                self.syncError = nil

                store.preferences.cloudAuthToken = authResult.token
                store.preferences.cloudUserEmail = authResult.user.email
                store.preferences.cloudSyncEnabled = true

                // Update profile in store
                store.completeUserSignIn(name: authResult.user.displayName ?? cleanName, email: authResult.user.email, provider: "Cloud Account")

                self.applyUserSubscription(user: authResult.user, store: store)
                connectRealTimeWebSocket(store: store)

                // Immediately upload and back up current local spaces and settings into the new account
                await syncNow(store: store)
                isSyncing = false
                store.showToast("Account created! All spaces & settings saved to cloud.")
                return .success("Account created and settings saved")
            } else if httpResp.statusCode == 409 {
                isSyncing = false
                let msg = "An account with this email already exists. Please switch to Sign In to restore your settings."
                self.syncError = msg
                return .failure(msg)
            } else {
                isSyncing = false
                let errMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Registration failed (HTTP \(httpResp.statusCode))"
                self.syncError = errMsg
                return .failure(errMsg)
            }
        } catch {
            isSyncing = false
            syncError = error.localizedDescription
            return .failure("Could not connect to server: \(error.localizedDescription)")
        }
    }

    func loginOrRegister(email: String, password: String, serverURL: String, store: AppStore) async -> Bool {
        store.preferences.cloudServerURL = serverURL
        let res = await login(email: email, password: password, store: store)
        switch res {
        case .success:
            return true
        case .failure:
            let regRes = await register(name: "", email: email, password: password, store: store)
            return regRes.isSuccess
        }
    }

    private func applyUserSubscription(user: CloudUserResponse, store: AppStore) {
        store.preferences.cloudTier = user.tier ?? "free"
        store.preferences.cloudSubscriptionStatus = user.subscriptionStatus ?? "free"
        store.preferences.cloudDaysRemaining = user.daysRemaining ?? 0
        store.preferences.cloudPlanName = user.planName ?? (user.tier == "pro" ? "PINGGO Pro" : "PINGGO Free")
        if let expStr = user.tierExpiresAt {
            store.preferences.cloudTierExpiresAt = ISO8601DateFormatter().date(from: expStr)
        } else {
            store.preferences.cloudTierExpiresAt = nil
        }

        store.userProfile.subscriptionTier = store.preferences.cloudPlanName
        store.userProfile.subscriptionStatus = (user.isExpired == true) ? "Expired" : "Active"

        if user.isExpired == true {
            store.showToast("⚠️ Your Pro plan has expired. Switched to Free tier.")
        }
    }

    func refreshSubscriptionStatus(store: AppStore) async {
        guard isCloudConnected && !store.preferences.cloudAuthToken.isEmpty else { return }
        let baseURL = store.preferences.cloudServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: "\(baseURL)/api/v1/subscription/status") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(store.preferences.cloudAuthToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else { return }
            let sub = try JSONDecoder().decode(CloudSubscriptionStatus.self, from: data)

            store.preferences.cloudTier = sub.tier
            store.preferences.cloudSubscriptionStatus = sub.subscriptionStatus
            store.preferences.cloudDaysRemaining = sub.daysRemaining
            store.preferences.cloudPlanName = sub.planName ?? (sub.tier == "pro" ? "PINGGO Pro" : "PINGGO Free")
            if let expStr = sub.tierExpiresAt {
                store.preferences.cloudTierExpiresAt = ISO8601DateFormatter().date(from: expStr)
            } else {
                store.preferences.cloudTierExpiresAt = nil
            }

            if sub.isExpired {
                store.showToast("⚠️ Plan expired. Switched to Free tier — tap to renew.")
            }
        } catch {
            print("[CloudSyncService] Error refreshing subscription: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func renewOrUpgrade(plan: String = "monthly", durationDays: Int? = nil, store: AppStore) async -> Bool {
        guard isCloudConnected && !store.preferences.cloudAuthToken.isEmpty else {
            store.triggerUpgrade(reason: "Please connect to your MongoDB account to activate PINGGO Pro.")
            return false
        }

        isSyncing = true
        syncStatusMessage = "Processing plan payment..."
        let baseURL = store.preferences.cloudServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let endpoint = store.preferences.cloudSubscriptionStatus == "expired" ? "renew" : "upgrade"
        guard let url = URL(string: "\(baseURL)/api/v1/subscription/\(endpoint)") else {
            isSyncing = false
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(store.preferences.cloudAuthToken)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["plan": plan, "paymentMethod": "In-App Payment / Card"]
        if let durationDays = durationDays {
            body["durationDays"] = durationDays
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                isSyncing = false
                store.showToast("Payment processing failed. Please try again.")
                return false
            }

            let actionRes = try JSONDecoder().decode(CloudSubscriptionActionResponse.self, from: data)
            store.preferences.cloudTier = actionRes.tier
            store.preferences.cloudSubscriptionStatus = actionRes.subscriptionStatus
            store.preferences.cloudDaysRemaining = actionRes.daysRemaining
            store.preferences.cloudPlanName = actionRes.planName ?? "PINGGO Pro"
            if let expStr = actionRes.tierExpiresAt {
                store.preferences.cloudTierExpiresAt = ISO8601DateFormatter().date(from: expStr)
            }

            isSyncing = false
            syncStatusMessage = "Plan Active: \(actionRes.planName ?? "Pro")"
            store.showToast(actionRes.message)
            return true
        } catch {
            isSyncing = false
            store.showToast("Subscription error: \(error.localizedDescription)")
            return false
        }
    }

    func disconnect(store: AppStore) {
        disconnectWebSocket()
        store.preferences.cloudAuthToken = ""
        store.preferences.cloudUserEmail = ""
        store.preferences.cloudSyncEnabled = false
        store.preferences.cloudTier = "free"
        store.preferences.cloudSubscriptionStatus = "free"
        store.preferences.cloudTierExpiresAt = nil
        store.preferences.cloudDaysRemaining = 0
        store.preferences.cloudPlanName = "PINGGO Free"

        self.isCloudConnected = false
        self.currentUserEmail = ""
        self.syncStatusMessage = "Not Connected"
        self.syncError = nil

        store.userProfile.isSignedIn = false
        store.userProfile.provider = nil
        store.userProfile.subscriptionTier = "Free"
        store.userProfile.subscriptionStatus = "Active"
        store.showToast("Signed out. Operating in local mode.")
    }

    // MARK: - Real-Time WebSocket Synchronization
    private var webSocketTask: URLSessionWebSocketTask?
    @Published var isRealTimeLive: Bool = false

    func connectRealTimeWebSocket(store: AppStore) {
        guard isCloudConnected, !store.preferences.cloudAuthToken.isEmpty else { return }
        disconnectWebSocket()

        let baseURL = store.preferences.cloudServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let wsScheme = baseURL.lowercased().hasPrefix("https") ? "wss" : "ws"
        let hostAndPort = baseURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")

        let token = store.preferences.cloudAuthToken
        guard let wsURL = URL(string: "\(wsScheme)://\(hostAndPort)/ws?token=\(token)") else { return }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: wsURL)
        self.webSocketTask = task
        task.resume()
        self.isRealTimeLive = true
        print("[CloudSyncService] WebSocket connected to \(wsURL.host ?? "gateway")")

        listenToWebSocket(store: store)
    }

    private func listenToWebSocket(store: AppStore) {
        guard let task = webSocketTask else { return }
        task.receive { [weak self, weak store] result in
            Task { @MainActor in
                guard let self = self, let store = store else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message {
                        if let data = text.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let type = json["type"] as? String {
                            if type == "SYNC_UPDATE" {
                                let remoteDeviceId = json["deviceId"] as? String
                                if remoteDeviceId != self.deviceID {
                                    print("[CloudSyncService] Real-time delta received from \(remoteDeviceId ?? "remote"). Syncing now...")
                                    await self.syncNow(store: store)
                                }
                            } else if type == "SUBSCRIPTION_UPDATED" {
                                let tier = json["tier"] as? String ?? "free"
                                let status = json["subscriptionStatus"] as? String ?? "free"
                                let days = json["daysRemaining"] as? Int ?? 0
                                let plan = json["planName"] as? String ?? "PINGGO Pro"
                                store.preferences.cloudTier = tier
                                store.preferences.cloudSubscriptionStatus = status
                                store.preferences.cloudDaysRemaining = days
                                store.preferences.cloudPlanName = plan
                                if let expStr = json["tierExpiresAt"] as? String {
                                    store.preferences.cloudTierExpiresAt = ISO8601DateFormatter().date(from: expStr)
                                } else {
                                    store.preferences.cloudTierExpiresAt = nil
                                }
                                if let msg = json["message"] as? String {
                                    store.showToast(msg)
                                }
                            }
                        }
                    }
                    self.listenToWebSocket(store: store)

                case .failure(let error):
                    print("[CloudSyncService] WebSocket disconnected: \(error.localizedDescription)")
                    self.isRealTimeLive = false
                    self.webSocketTask = nil
                    try? await Task.sleep(for: .seconds(10))
                    if self.isCloudConnected {
                        self.connectRealTimeWebSocket(store: store)
                    }
                }
            }
        }
    }

    func disconnectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isRealTimeLive = false
    }

    // MARK: - Pull from Cloud
    @discardableResult
    func pullFromCloud(store: AppStore) async -> Bool {
        guard isCloudConnected && !store.preferences.cloudAuthToken.isEmpty else { return false }
        let baseURL = store.preferences.cloudServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let pullURL = URL(string: "\(baseURL)/api/v1/sync/pull") else { return false }

        var request = URLRequest(url: pullURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(store.preferences.cloudAuthToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return false
            }

            let pullData = try JSONDecoder().decode(CloudPullResponse.self, from: data)

            if let remotePrefs = pullData.preferences {
                store.restorePreferencesFromCloud(remotePrefs)
            }

            if let remoteSpaces = pullData.spaces, !remoteSpaces.isEmpty, store.preferences.syncSpaces {
                store.updateRemoteSpaces(remoteSpaces)
            }

            self.lastSyncedAt = Date()
            self.syncStatusMessage = "Synced at \(Self.timeFormatter.string(from: Date()))"
            self.syncError = nil
            return pullData.preferences != nil
        } catch {
            print("[CloudSyncService] Pull error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Debounced Push on Preferences Change
    private var pushDebounceTask: Task<Void, Never>? = nil

    func pushPreferencesDebounced(store: AppStore) {
        guard isCloudConnected && !store.preferences.cloudAuthToken.isEmpty else { return }
        pushDebounceTask?.cancel()
        pushDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await self.syncNow(store: store)
        }
    }

    // MARK: - Synchronize Data with MongoDB Gateway
    func syncNow(store: AppStore) async {
        guard !isSyncing else { return }
        guard isCloudConnected && !store.preferences.cloudAuthToken.isEmpty else {
            syncStatusMessage = "Not connected to cloud"
            return
        }

        isSyncing = true
        syncError = nil
        syncStatusMessage = "Syncing with MongoDB…"

        let baseURL = store.preferences.cloudServerURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let syncURL = URL(string: "\(baseURL)/api/v1/sync/push") else {
            syncError = "Invalid server URL"
            isSyncing = false
            return
        }

        let syncedPrefs = SyncedPreferencesPayload(
            appearance: store.preferences.appearance,
            accent: store.preferences.accent,
            compactMode: store.preferences.compactMode,
            openLinksInAppBrowser: store.preferences.openLinksInAppBrowser,
            showVideoHoverPill: store.preferences.showVideoHoverPill,
            videoDownloadFolder: store.preferences.videoDownloadFolder,
            aiEnabled: store.preferences.aiEnabled,
            aiProvider: store.preferences.aiProvider,
            openAiApiKey: store.preferences.openAiApiKey,
            openAiModelTier: store.preferences.openAiModelTier,
            geminiApiKey: store.preferences.geminiApiKey,
            geminiModelTier: store.preferences.geminiModelTier,
            ollamaEndpoint: store.preferences.ollamaEndpoint,
            ollamaModel: store.preferences.ollamaModel,
            personaStyle: store.preferences.personaStyle,
            defaultReplyTone: store.preferences.defaultReplyTone,
            customAiPrompt: store.preferences.customAiPrompt,
            syncAiSettings: store.preferences.syncAiSettings
        )

        let payload = CloudSyncPayload(
            deviceId: deviceID,
            platform: "macOS",
            timestamp: Date(),
            spaces: store.preferences.syncSpaces ? store.data.spaces : nil,
            preferences: syncedPrefs,
            bookmarks: nil,
            briefings: nil
        )

        var request = URLRequest(url: syncURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(store.preferences.cloudAuthToken)", forHTTPHeaderField: "Authorization")

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(payload)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse else {
                syncError = "No response from cloud gateway"
                isSyncing = false
                return
            }

            if httpResp.statusCode == 200 {
                // If server returned updated remote data (delta pull), merge into local store
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let remoteSpacesData = json["spaces"] {
                    let spacesData = try JSONSerialization.data(withJSONObject: remoteSpacesData)
                    if let remoteSpaces = try? JSONDecoder().decode([Space].self, from: spacesData), !remoteSpaces.isEmpty {
                        store.updateRemoteSpaces(remoteSpaces)
                    }
                }

                self.lastSyncedAt = Date()
                self.syncStatusMessage = "Synced at \(Self.timeFormatter.string(from: Date()))"
                self.syncError = nil
            } else if httpResp.statusCode == 401 {
                self.syncError = "Session expired. Please reconnect."
                self.syncStatusMessage = "Session expired"
                self.isCloudConnected = false
            } else {
                self.syncError = "Server returned code \(httpResp.statusCode)"
                self.syncStatusMessage = "Sync failed"
            }
        } catch {
            self.syncError = "Network error: \(error.localizedDescription)"
            self.syncStatusMessage = "Sync failed"
        }

        isSyncing = false
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}
