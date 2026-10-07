import SwiftUI
import WebKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General"
    case account = "Account & Cloud"
    case ai = "AI Co-Pilot"
    case security = "Security & Lock"
    case performance = "Performance"
    case about = "About & Support"

    var id: String { rawValue }

    // Backward-compatibility aliases
    static var profile: SettingsPage { .account }
    static var launch: SettingsPage { .performance }
    static var interaction: SettingsPage { .general }
    static var subscription: SettingsPage { .account }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .account: return "person.crop.circle.fill"
        case .ai: return "sparkles"
        case .security: return "lock.shield.fill"
        case .performance: return "bolt.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .cyan
        case .account: return .indigo
        case .ai: return .purple
        case .security: return .green
        case .performance: return .orange
        case .about: return .blue
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Appearance, startup, and dashboard settings"
        case .account: return "Cloud profile, sign-in, and synchronization"
        case .ai: return "AI engines, persona, and API credentials"
        case .security: return "Touch ID, custom PIN, and app lock"
        case .performance: return "Memory saver, tab freezing, and optimization"
        case .about: return "App information, shortcuts, and privacy"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    var initialPage: SettingsPage? = nil
    @State private var page: SettingsPage = .general
    @State private var detail: String?
    @State private var hibernatedFeedback = false
    @State private var showingPinSetupSheet = false
    @State private var pinSetupIsChanging = false
    @State private var selectedSocialLoginProvider: String? = nil
    @State private var showingEditProfileSheet = false
    @State private var showGeminiApiKey = false
    @State private var showOpenAiApiKey = false
    @State private var testingAiConnection = false
    @State private var aiTestResult: (success: Bool, message: String)? = nil
    @State private var keychainDiagnosticResult: String? = nil
    @State private var ollamaIsOnline: Bool? = nil
    @State private var ollamaInstalledModels: [String] = []
    @State private var isCheckingOllama: Bool = false
    @State private var ollamaStatusDetail: String? = nil
    @ObservedObject private var cloudSync = CloudSyncService.shared
    enum AuthTab: String, CaseIterable, Identifiable {
        case signIn = "Sign In"
        case createAccount = "Create Account"
        var id: String { rawValue }
    }
    @State private var authTab: AuthTab = .signIn
    @State private var authFullName: String = ""
    @State private var authEmail: String = ""
    @State private var authPassword: String = ""
    @State private var authErrorMessage: String? = nil
    @State private var isAuthenticating: Bool = false
    @State private var cloudLoginEmail: String = ""
    @State private var cloudLoginPassword: String = ""

    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 750
            HStack(spacing: 0) {
                if !narrow { settingsSidebar }
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if narrow {
                            HStack {
                                Button { store.destination = .home } label: {
                                    Label("Back", systemImage: "chevron.left")
                                }
                                Spacer()
                                Picker("Settings", selection: $page) {
                                    ForEach(SettingsPage.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 190)
                            }
                        }

                        // Page Header
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Image(systemName: page.symbol)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(page.color)
                                    .frame(width: 32, height: 32)
                                    .background(page.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                                Text(page.rawValue)
                                    .font(.system(size: 24, weight: .bold))

                                Spacer()
                            }
                            Text(page.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(.bottom, 6)

                        // Render active page
                        switch page {
                        case .general: generalPage
                        case .account: accountPage
                        case .ai: aiSettingsPage
                        case .security: securityPage
                        case .performance: performancePage
                        case .about: aboutPage
                        }
                    }
                    .padding(narrow ? 20 : 32)
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .background(Palette.background)
            }
        }
        .onAppear {
            if let initialPage {
                page = initialPage
            } else if store.destination == .profile {
                page = .account
            } else if store.destination == .settings {
                page = .general
            }
        }
        .onChange(of: store.destination) { _, newDestination in
            if newDestination == .profile {
                page = .account
            } else if newDestination == .settings && page == .account {
                page = .general
            }
        }
        .sheet(item: Binding(
            get: { detail.map(DetailSheet.init) },
            set: { detail = $0?.id }
        )) { item in
            detailSheet(item.id)
        }
        .sheet(isPresented: $showingPinSetupSheet) {
            CustomPinSetupSheet(isChangingExisting: pinSetupIsChanging)
        }
        .sheet(item: Binding(
            get: { selectedSocialLoginProvider.map { SocialLoginItem(provider: $0) } },
            set: { selectedSocialLoginProvider = $0?.provider }
        )) { item in
            SocialLoginSheet(providerName: item.provider)
        }
        .sheet(isPresented: $showingEditProfileSheet) {
            EditProfileSheet()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { store.destination = .home } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Overview")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 14)

            HStack {
                Text("Preferences")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { item in
                    let isSelected = (page == item)
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            page = item
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : item.color)
                                .frame(width: 26, height: 26)
                                .background(isSelected ? item.color : item.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                            Text(item.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? .primary : Palette.muted)

                            Spacer()

                            if isSelected {
                                Circle()
                                    .fill(Palette.accent)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(
                            isSelected ? Palette.accent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(isSelected ? Palette.accent.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            // Footer user info
            Divider()
                .padding(.horizontal, 10)

            HStack(spacing: 10) {
                Avatar(member: store.me, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.userProfile.isSignedIn ? store.userProfile.displayName : store.me.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(store.userProfile.isSignedIn ? (store.userProfile.provider ?? "Cloud Account") : "Local Offline")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { page = .account } label: {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .help("Manage Account")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .frame(width: 220)
        .background(Palette.sidebar)
    }

    private var accountPage: some View {
        VStack(spacing: 20) {
            if store.userProfile.isSignedIn || cloudSync.isCloudConnected {
                unifiedAccountProfileCard
            } else {
                accountAuthCard
                syncBenefitsCard
            }
        }
    }

    private var effectiveUserEmail: String {
        if !cloudSync.currentUserEmail.isEmpty {
            return cloudSync.currentUserEmail
        }
        if store.userProfile.isSignedIn && !store.userProfile.email.isEmpty {
            return store.userProfile.email
        }
        return "guest@pinggo.app"
    }

    private var userInitials: String {
        let name = store.userProfile.isSignedIn ? store.userProfile.displayName : (cloudSync.currentUserEmail.isEmpty ? "U" : cloudSync.currentUserEmail)
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var unifiedAccountProfileCard: some View {
        settingsCard("Account & Cloud Synchronization", symbol: "person.crop.circle.badge.checkmark", color: .indigo) {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Hero Profile Header & Plan Status
                HStack(alignment: .center, spacing: 14) {
                    // Avatar with Google/Provider badge
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Palette.accent.opacity(0.18))
                            .frame(width: 52, height: 52)
                            .overlay(
                                Text(userInitials)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                            )

                        if let provider = store.userProfile.provider {
                            Image(systemName: providerSymbol(provider))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3.5)
                                .background(providerColor(provider), in: Circle())
                                .offset(x: 2, y: 2)
                        }
                    }

                    // Name, Email, Validity & Cloud Indicator
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(store.userProfile.isSignedIn ? store.userProfile.displayName : (cloudSync.currentUserEmail.isEmpty ? "Local User" : cloudSync.currentUserEmail.components(separatedBy: "@").first ?? "User"))
                                .font(.system(size: 16, weight: .bold))

                            // Tier Badge
                            if store.isCloudProExpired {
                                HStack(spacing: 3) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("PLAN EXPIRED")
                                }
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color.orange, in: Capsule())
                            } else if store.isPro {
                                HStack(spacing: 3) {
                                    Image(systemName: "crown.fill")
                                    Text("PRO")
                                }
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color.green, in: Capsule())
                            } else {
                                Text("FREE TIER")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2.5)
                                    .background(Color.gray.opacity(0.18), in: Capsule())
                            }

                            // Cloud Status indicator
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(cloudSync.isCloudConnected ? Color.green : Color.gray.opacity(0.5))
                                    .frame(width: 7, height: 7)
                                Text(cloudSync.isCloudConnected ? "Cloud Active" : "Local Only")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(cloudSync.isCloudConnected ? Color.green : Palette.muted)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.panel, in: Capsule())
                        }

                        // Email & Plan Validity text
                        HStack(spacing: 6) {
                            Text(effectiveUserEmail)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)

                            Text("•")
                                .foregroundStyle(Palette.muted.opacity(0.5))

                            if store.isCloudProExpired {
                                Text("Repayment required to restore Pro")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.orange)
                            } else if store.isPro {
                                if let expires = store.preferences.cloudTierExpiresAt {
                                    Text("Valid until \(expires.formatted(date: .abbreviated, time: .omitted)) (\(store.subscriptionDaysRemaining)d left)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.green)
                                } else {
                                    Text("Lifetime license active")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.green)
                                }
                            } else {
                                Text("Free Tier (3 workspaces limit)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                    }

                    Spacer()

                    // Right header buttons: Renew / Upgrade & Sign Out
                    VStack(alignment: .trailing, spacing: 6) {
                        if store.isCloudProExpired || !store.isPro {
                            Button {
                                store.triggerUpgrade(reason: store.isCloudProExpired ? "Renew PINGGO Pro to restore unlimited workspaces" : "Upgrade to PINGGO Pro")
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: store.isCloudProExpired ? "arrow.clockwise.circle.fill" : "crown.fill")
                                    Text(store.isCloudProExpired ? "Renew Plan" : "Upgrade to Pro")
                                }
                                .font(.system(size: 11.5, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(store.isCloudProExpired ? Color.orange : Palette.accent)
                            .controlSize(.small)
                        } else {
                            Button("Manage Pro") {
                                store.triggerUpgrade(reason: "Manage your active subscription.")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if store.userProfile.isSignedIn || cloudSync.isCloudConnected {
                            Button("Sign Out", role: .destructive) {
                                cloudSync.disconnect(store: store)
                                store.signOutProfile()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red.opacity(0.85))
                        }
                    }
                }
                .padding(12)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))


                // 3. Data to Synchronize toggles
                VStack(alignment: .leading, spacing: 8) {
                    Text("DATA TO SYNCHRONIZE")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Palette.muted)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        Toggle("Spaces, Layouts & Ordering", isOn: $store.preferences.syncSpaces)
                            .font(.system(size: 11.5))
                            .tint(Palette.accent)

                        Toggle("Daily AI Briefings & Actions", isOn: $store.preferences.syncBriefings)
                            .font(.system(size: 11.5))
                            .tint(Palette.accent)

                        Toggle("Browser Bookmarks & Tags", isOn: $store.preferences.syncBookmarks)
                            .font(.system(size: 11.5))
                            .tint(Palette.accent)

                        Toggle("AI Provider, Keys & Models", isOn: $store.preferences.syncAiSettings)
                            .font(.system(size: 11.5))
                            .tint(Palette.accent)
                    }
                }
                .padding(.vertical, 4)

                Divider()

                // 4. Action & Sync Bar
                HStack {
                    if let lastSync = cloudSync.lastSyncedAt {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            Text("Last Synced: \(lastSync.formatted(date: .omitted, time: .shortened))")
                                .foregroundStyle(Palette.muted)
                        }
                        .font(.system(size: 11))
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "circle")
                                .foregroundStyle(Palette.muted)
                            Text(cloudSync.isCloudConnected ? "Ready to sync" : "Not connected to cloud")
                                .foregroundStyle(Palette.muted)
                        }
                        .font(.system(size: 11))
                    }

                    Spacer()

                    Button {
                        Task {
                            let restored = await cloudSync.pullFromCloud(store: store)
                            if restored {
                                store.showToast("Settings and AI keys restored from MongoDB")
                            } else {
                                store.showToast("No remote settings found in cloud")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                            Text("Restore from Cloud")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(cloudSync.isSyncing || !cloudSync.isCloudConnected)

                    Button {
                        Task {
                            await cloudSync.syncNow(store: store)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if cloudSync.isSyncing {
                                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Sync Now")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Palette.accent)
                    .disabled(cloudSync.isSyncing || !cloudSync.isCloudConnected)
                }


            }
        }
    }

    private var accountAuthCard: some View {
        settingsCard("Account Sign In & Cloud Backup", symbol: "person.crop.circle.badge.plus", color: .indigo) {
            VStack(alignment: .leading, spacing: 16) {
                // Auth Tab Picker
                Picker("", selection: $authTab) {
                    ForEach(AuthTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 2)

                if authTab == .signIn {
                    // MARK: - Sign In Tab (Restores Settings & Plan)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.arrow.right")
                                .font(.system(size: 16))
                                .foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign In to Restore Your Setup")
                                    .font(.system(size: 14, weight: .bold))
                                Text("If your account is in the database, all spaces, AI keys, and Pro subscription will be automatically restored.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.muted)
                            }
                        }

                        VStack(spacing: 8) {
                            TextField("Email Address", text: $authEmail)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))

                            SecureField("Password", text: $authPassword)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        if let error = authErrorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }

                        HStack {
                            Button {
                                authTab = .createAccount
                                authErrorMessage = nil
                            } label: {
                                Text("Don't have an account? Create one")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.accent)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                Task {
                                    isAuthenticating = true
                                    authErrorMessage = nil
                                    let res = await cloudSync.login(email: authEmail, password: authPassword, store: store)
                                    isAuthenticating = false
                                    switch res {
                                    case .success:
                                        authPassword = ""
                                        authErrorMessage = nil
                                    case .failure(let err):
                                        authErrorMessage = err
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if isAuthenticating {
                                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    Text(isAuthenticating ? "Signing In…" : "Sign In & Restore")
                                }
                                .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .tint(Palette.accent)
                            .disabled(authEmail.isEmpty || authPassword.isEmpty || isAuthenticating)
                        }

                        Divider()

                        // Quick 1-Click Demo Accounts
                        VStack(alignment: .leading, spacing: 6) {
                            Text("QUICK 1-CLICK DEMO ACCOUNTS")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Palette.muted)

                            HStack(spacing: 8) {
                                Button("Google (rahulonit@gmail.com)") {
                                    authEmail = "rahulonit@gmail.com"
                                    authPassword = "mypassword123"
                                    Task {
                                        isAuthenticating = true
                                        authErrorMessage = nil
                                        let res = await cloudSync.login(email: authEmail, password: authPassword, store: store)
                                        isAuthenticating = false
                                        if case .failure(let err) = res {
                                            authErrorMessage = err
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                } else {
                    // MARK: - Create Account Tab (Stores Details & Settings)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 16))
                                .foregroundStyle(Palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create Account & Store Details")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Register an account in the database to store and back up all your current local workspaces and AI keys.")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.muted)
                            }
                        }

                        VStack(spacing: 8) {
                            TextField("Full Name (e.g. Rahul Kumar)", text: $authFullName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))

                            TextField("Email Address", text: $authEmail)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))

                            SecureField("Password (minimum 6 characters)", text: $authPassword)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        if let error = authErrorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }

                        HStack {
                            Button {
                                authTab = .signIn
                                authErrorMessage = nil
                            } label: {
                                Text("Already have an account? Sign In")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.accent)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                Task {
                                    isAuthenticating = true
                                    authErrorMessage = nil
                                    let res = await cloudSync.register(name: authFullName, email: authEmail, password: authPassword, store: store)
                                    isAuthenticating = false
                                    switch res {
                                    case .success:
                                        authPassword = ""
                                        authErrorMessage = nil
                                    case .failure(let err):
                                        authErrorMessage = err
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    if isAuthenticating {
                                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "cloud.fill")
                                    }
                                    Text(isAuthenticating ? "Saving…" : "Create Account & Store Details")
                                }
                                .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                            .tint(Palette.accent)
                            .disabled(authEmail.isEmpty || authPassword.isEmpty || isAuthenticating)
                        }
                    }
                }
            }
        }
    }

    private var syncBenefitsCard: some View {
        settingsCard("What Gets Stored in Cloud?", symbol: "checkmark.shield.fill", color: .green) {
            VStack(alignment: .leading, spacing: 10) {
                benefitRow(icon: "crown.fill", color: .yellow, title: "PINGGO Pro Subscription", desc: "Restore subscription status across any Mac without repurchasing.")
                Divider()
                benefitRow(icon: "square.grid.2x2.fill", color: .blue, title: "Social Platforms & Custom URLs", desc: "\(store.socialPlatforms.count) connected social apps and custom website configurations.")
                Divider()
                benefitRow(icon: "person.2.fill", color: .purple, title: "Multi-Account Profiles", desc: "\(store.platformAccounts.count) multi-account setups and split view layouts.")
                Divider()
                benefitRow(icon: "lock.shield.fill", color: .indigo, title: "Encrypted Security & Preferences", desc: "App lock settings, themes, and notification preferences securely backed up.")
            }
        }
    }

    private func benefitRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
        }
    }



    private func providerSymbol(_ provider: String) -> String {
        switch provider {
        case "Apple": return "apple.logo"
        case "Google": return "g.circle.fill"
        case "Microsoft": return "square.grid.2x2.fill"
        default: return "cloud.fill"
        }
    }

    private func providerColor(_ provider: String) -> Color {
        switch provider {
        case "Apple": return .primary
        case "Google": return Color(red: 0.92, green: 0.26, blue: 0.21)
        case "Microsoft": return Color(red: 0.0, green: 0.63, blue: 0.94)
        default: return Palette.accent
        }
    }



    private var aiSettingsPage: some View {
        VStack(spacing: 24) {
            // Hero Intro Card
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [.purple, .indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 42, height: 42)
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("AI Assistant & Smart Replies")
                                .font(.system(size: 17, weight: .bold))
                            Text("In-App Web Login")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundStyle(.green)
                        }
                        Text("Connect Gemini or OpenAI with a validated API credential. Credentials are stored in macOS Keychain and never in app preferences.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08)))

            // General AI settings
            settingsCard("AI Configuration", symbol: "sparkles", color: .purple) {
                settingsRow("Enable AI Assistant", "Activate conversation analysis, question detection, and multi-tone smart replies.") {
                    Toggle("Enable AI Assistant", isOn: $store.preferences.aiEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                settingsRow("Active AI Engine", "Choose which connected service is prioritized for reply synthesis and drafting.") {
                    Picker("Active Engine", selection: $store.preferences.aiProvider) {
                        Text("Google Gemini").tag("gemini")
                        Text("OpenAI ChatGPT").tag("chatgpt")
                        Text("Local LLM (Ollama)").tag("ollama")
                        Text("Smart Engine (Built-in)").tag("smart")
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                Divider()

                settingsRow("Personal Persona Style", "Steer the default tone, verbosity, and personality across all Co-Pilot interactions.") {
                    Picker("Persona Style", selection: $store.preferences.personaStyle) {
                        ForEach(PersonaStyle.allCases) { style in
                            Text(style.rawValue).tag(style.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                Divider()

                settingsRow("Private Preview Default", "When opening unread chats, inspect captured messages and private AI analysis without loading the interactive portal.") {
                    Toggle("Private Preview", isOn: $store.preferences.stealthModeDefault)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Divider()

                settingsRow("Default Reply Tone", "Tone pre-selected when generating contextual reply suggestions.") {
                    Picker("Reply Tone", selection: $store.preferences.defaultReplyTone) {
                        ForEach(AIReplyTone.allCases) { tone in
                            Text(tone.rawValue).tag(tone.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom AI Instructions (Persona)")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Optional rules or context to guide AI reply generation.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                    TextField("e.g. Keep responses friendly, concise, and prefer meeting on Thursdays.", text: $store.preferences.customAiPrompt)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
            }

            // Master AI Providers & Model Integration Card
            settingsCard("AI Providers & Model Integration", symbol: "brain.head.profile", color: .blue) {
                // Intro & Security Callout
                VStack(alignment: .leading, spacing: 8) {
                    Text("Connect your preferred AI engines to unlock context-aware smart replies, conversation summaries, action item extraction, and real-time translation across all messaging spaces. When no external provider is configured, PINGGO falls back to its built-in local smart engine.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 13))
                        Text("Hardware-Secured: API keys are encrypted and stored locally in your macOS Keychain. They are never sent to third-party tracking servers and communicate directly with each provider's official API endpoints.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }

                Divider()

                // 1. Google Gemini Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Google Gemini")
                                    .font(.system(size: 13, weight: .bold))

                                if !store.preferences.geminiApiKey.isEmpty && store.preferences.isGeminiLoggedIn {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 6, height: 6)
                                        Text("Connected")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.green)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                } else if !store.preferences.geminiApiKey.isEmpty {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                                        Text("Key Saved (Untested)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                                } else {
                                    Text("Not Configured")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.muted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Palette.card.opacity(0.6), in: Capsule())
                                }
                            }

                            Text("Gemini 2.5 multimodal models with ultra-low latency, 1M+ token context, and deep multilingual understanding.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.muted)
                        }

                        Spacer()

                        Picker("Model", selection: $store.preferences.geminiModelTier) {
                            Text("gemini-2.5-flash (Fastest)").tag("gemini-2.5-flash")
                            Text("gemini-2.5-pro (Reasoning)").tag("gemini-2.5-pro")
                            Text("gemini-1.5-flash").tag("gemini-1.5-flash")
                            Text("gemini-1.5-pro").tag("gemini-1.5-pro")
                        }
                        .labelsHidden()
                        .frame(width: 175)
                    }

                    // Key input and action buttons
                    HStack(spacing: 8) {
                        Group {
                            if showGeminiApiKey {
                                TextField("Enter Gemini API key (AIzaSy...)", text: aiCredentialBinding(provider: "gemini"))
                            } else {
                                SecureField("Enter Gemini API key (AIzaSy...)", text: aiCredentialBinding(provider: "gemini"))
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                        Button {
                            showGeminiApiKey.toggle()
                        } label: {
                            Image(systemName: showGeminiApiKey ? "eye.slash" : "eye")
                                .foregroundStyle(Palette.muted)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            testingAiConnection = true
                            aiTestResult = nil
                            Task {
                                let res = await AIService.shared.testAPIConnection(
                                    provider: "gemini",
                                    apiKey: store.preferences.geminiApiKey,
                                    model: store.preferences.geminiModelTier
                                )
                                testingAiConnection = false
                                aiTestResult = res
                                store.preferences.isGeminiLoggedIn = res.success
                            }
                        } label: {
                            if testingAiConnection {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("Test Key")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.preferences.geminiApiKey.isEmpty || testingAiConnection)

                        if !store.preferences.geminiApiKey.isEmpty {
                            Button("Disconnect") {
                                Task {
                                    await AIService.shared.signOut(provider: "gemini", store: store)
                                    aiTestResult = nil
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    // Direct helper link
                    HStack(spacing: 4) {
                        Text("Need a Gemini API key?")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                        Link("Get a free key from Google AI Studio", destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                    }
                }

                Divider()

                // 2. OpenAI ChatGPT Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.06, green: 0.65, blue: 0.53).opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(red: 0.06, green: 0.65, blue: 0.53))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("OpenAI ChatGPT")
                                    .font(.system(size: 13, weight: .bold))

                                if !store.preferences.openAiApiKey.isEmpty && store.preferences.isChatGptLoggedIn {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.green).frame(width: 6, height: 6)
                                        Text("Connected")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.green)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                                } else if !store.preferences.openAiApiKey.isEmpty {
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                                        Text("Key Saved (Untested)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.orange)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                                } else {
                                    Text("Not Configured")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Palette.muted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Palette.card.opacity(0.6), in: Capsule())
                                }
                            }

                            Text("GPT-4o & GPT-4o-mini models for natural conversational flow, nuanced tone matching, and precise reasoning.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.muted)
                        }

                        Spacer()

                        Picker("Model", selection: $store.preferences.openAiModelTier) {
                            Text("gpt-4o-mini (Fast & Low Cost)").tag("gpt-4o-mini")
                            Text("gpt-4o (High Precision)").tag("gpt-4o")
                        }
                        .labelsHidden()
                        .frame(width: 175)
                    }

                    // Key input and action buttons
                    HStack(spacing: 8) {
                        Group {
                            if showOpenAiApiKey {
                                TextField("Enter OpenAI API key (sk-proj-...)", text: aiCredentialBinding(provider: "chatgpt"))
                            } else {
                                SecureField("Enter OpenAI API key (sk-proj-...)", text: aiCredentialBinding(provider: "chatgpt"))
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))

                        Button {
                            showOpenAiApiKey.toggle()
                        } label: {
                            Image(systemName: showOpenAiApiKey ? "eye.slash" : "eye")
                                .foregroundStyle(Palette.muted)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)

                        Button {
                            testingAiConnection = true
                            aiTestResult = nil
                            Task {
                                let res = await AIService.shared.testAPIConnection(
                                    provider: "chatgpt",
                                    apiKey: store.preferences.openAiApiKey,
                                    model: store.preferences.openAiModelTier
                                )
                                testingAiConnection = false
                                aiTestResult = res
                                store.preferences.isChatGptLoggedIn = res.success
                            }
                        } label: {
                            if testingAiConnection {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text("Test Key")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.preferences.openAiApiKey.isEmpty || testingAiConnection)

                        if !store.preferences.openAiApiKey.isEmpty {
                            Button("Disconnect") {
                                Task {
                                    await AIService.shared.signOut(provider: "chatgpt", store: store)
                                    aiTestResult = nil
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    // Direct helper link
                    HStack(spacing: 4) {
                        Text("Need an OpenAI secret key?")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                        Link("Generate a key in OpenAI API Keys Dashboard", destination: URL(string: "https://platform.openai.com/api-keys")!)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color(red: 0.06, green: 0.65, blue: 0.53))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color(red: 0.06, green: 0.65, blue: 0.53))
                    }
                }

                Divider()

                // 3. Ollama Local LLM Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.purple)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Ollama Local LLM")
                                    .font(.system(size: 13, weight: .bold))

                                if isCheckingOllama {
                                    HStack(spacing: 4) {
                                        ProgressView().controlSize(.mini)
                                        Text("Detecting...")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.muted)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.card, in: Capsule())
                                } else if let online = ollamaIsOnline {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(online ? Color.green : Color.orange)
                                            .frame(width: 6, height: 6)
                                        Text(online ? "Active (\(ollamaInstalledModels.count) models)" : "Offline")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(online ? .green : .orange)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((online ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                                }
                            }

                            Text("Run open-weights models completely offline on your Mac's Apple Silicon GPU. Zero cloud data sharing.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.muted)
                        }

                        Spacer()
                    }

                    // Model Selection & Presets
                    HStack(spacing: 10) {
                        Text("Active Model:")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.muted)

                        if !ollamaInstalledModels.isEmpty {
                            Picker("Model", selection: $store.preferences.ollamaModelTier) {
                                ForEach(ollamaInstalledModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                            .onChange(of: store.preferences.ollamaModelTier) { _, newModel in
                                store.preferences.ollamaModel = newModel
                            }
                        } else {
                            TextField("llama3.2", text: $store.preferences.ollamaModelTier)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                                .frame(width: 140)
                                .onChange(of: store.preferences.ollamaModelTier) { _, newModel in
                                    store.preferences.ollamaModel = newModel
                                }
                        }

                        Spacer()

                        // Quick Model Preset Pills
                        HStack(spacing: 4) {
                            ForEach(["llama3.2", "mistral", "qwen2.5", "deepseek-r1"], id: \.self) { preset in
                                Button(preset) {
                                    store.preferences.ollamaModelTier = preset
                                    store.preferences.ollamaModel = preset
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 9.5, weight: store.preferences.ollamaModelTier.contains(preset) ? .bold : .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(store.preferences.ollamaModelTier.contains(preset) ? Palette.accent.opacity(0.2) : Palette.card, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(store.preferences.ollamaModelTier.contains(preset) ? Palette.accent : Palette.muted)
                            }
                        }
                    }

                    // Endpoint & Actions
                    HStack(spacing: 8) {
                        TextField("http://localhost:11434", text: $store.preferences.ollamaEndpoint)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button {
                            checkOllamaServer()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Detect Status")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isCheckingOllama)

                        Button("Test Prompt") {
                            testingAiConnection = true
                            aiTestResult = nil
                            Task {
                                let res = await AIService.shared.testAPIConnection(
                                    provider: "ollama",
                                    apiKey: store.preferences.ollamaEndpoint,
                                    model: store.preferences.ollamaModel
                                )
                                testingAiConnection = false
                                aiTestResult = res
                                if res.success {
                                    store.preferences.isOllamaLoggedIn = true
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(testingAiConnection)
                    }

                    HStack(spacing: 4) {
                        Text("Get Ollama for macOS:")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                        Link("ollama.com", destination: URL(string: "https://ollama.com")!)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.purple)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.purple)
                    }

                    if let detail = ollamaStatusDetail {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(ollamaIsOnline == true ? .green : Palette.muted)
                    }
                }
                .onAppear {
                    if ollamaIsOnline == nil {
                        checkOllamaServer()
                    }
                }

                // Feedback Banner
                if let res = aiTestResult {
                    HStack(spacing: 8) {
                        Image(systemName: res.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(res.success ? .green : .red)
                        Text(res.message)
                            .font(.system(size: 11.5))
                            .foregroundStyle(res.success ? .green : .red)
                        Spacer()
                        Button {
                            aiTestResult = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((res.success ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func aiCredentialBinding(provider: String) -> Binding<String> {
        Binding(
            get: {
                provider == "gemini" ? store.preferences.geminiApiKey : store.preferences.openAiApiKey
            },
            set: { newValue in
                if provider == "gemini" {
                    store.preferences.isGeminiLoggedIn = false
                    store.preferences.geminiApiKey = newValue
                } else {
                    store.preferences.isChatGptLoggedIn = false
                    store.preferences.openAiApiKey = newValue
                }
            }
        )
    }

    private func checkOllamaServer() {
        guard !isCheckingOllama else { return }
        isCheckingOllama = true
        ollamaStatusDetail = nil
        Task {
            let res = await AIService.shared.fetchOllamaStatus(endpoint: store.preferences.ollamaEndpoint)
            isCheckingOllama = false
            ollamaIsOnline = res.isOnline
            ollamaInstalledModels = res.models
            if res.isOnline {
                ollamaStatusDetail = res.models.isEmpty
                    ? "Ollama is running, but no models are downloaded yet (run 'ollama pull llama3.2')."
                    : "Connected to Ollama! \(res.models.count) model\(res.models.count == 1 ? "" : "s") available on-device."
                if !res.models.isEmpty && !res.models.contains(store.preferences.ollamaModelTier) {
                    if let first = res.models.first {
                        store.preferences.ollamaModelTier = first
                        store.preferences.ollamaModel = first
                    }
                }
                store.preferences.isOllamaLoggedIn = res.isOnline && !res.models.isEmpty
            } else {
                store.preferences.isOllamaLoggedIn = false
                ollamaStatusDetail = "Ollama is not running. Start Ollama or download it from ollama.com to enable offline AI."
            }
        }
    }

    private var generalPage: some View {
        VStack(spacing: 20) {
            settingsCard("Appearance", symbol: "paintpalette.fill", color: .cyan) {
                settingsRow("Theme", "Choose light, dark, or automatic system appearance.") {
                    Picker("Appearance", selection: $store.preferences.appearance) {
                        Text("Follow System").tag("Follow System")
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }

                Divider()

                settingsRow("Accent Color", "Custom color applied to active tabs, buttons, and badges.") {
                    HStack(spacing: 10) {
                        ForEach(["blue", "cyan", "indigo", "orange", "green", "pink"], id: \.self) { color in
                            Button { store.preferences.accent = color } label: {
                                ZStack {
                                    Circle()
                                        .fill(accentColor(color))
                                        .frame(width: 22, height: 22)
                                    if store.preferences.accent == color {
                                        Circle()
                                            .strokeBorder(Color.white, lineWidth: 2)
                                            .frame(width: 14, height: 14)
                                    }
                                }
                                .padding(2)
                                .overlay(
                                    Circle()
                                        .stroke(store.preferences.accent == color ? accentColor(color) : Color.clear, lineWidth: 2)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(color.capitalized) accent")
                        }
                    }
                }

                Divider()

                settingsRow("Compact Mode", "Compress vertical spacing and margins for smaller displays.") {
                    Toggle("Compact Mode", isOn: $store.preferences.compactMode)
                        .labelsHidden()
                        .tint(Palette.accent)
                }
            }

            settingsCard("Startup & Launch", symbol: "house.fill", color: .blue) {
                settingsRow("Open On Launch", "Choose the initial workspace screen when PINGGO opens.") {
                    Picker("Open To", selection: $store.preferences.openTo) {
                        Text("Overview Dashboard").tag("Home")
                        Text("Last Active Platform").tag("Last Platform")
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                Divider()

                settingsRow("Initialize Portals", "Pre-load and monitor connected social portals upon application launch.") {
                    Toggle("Websites", isOn: $store.preferences.launchWebsites)
                        .labelsHidden()
                        .tint(Palette.accent)
                }

                if store.preferences.launchWebsites {
                    Divider()

                    settingsRow("Launch Stagger Delay", "Delay before starting background connections to prevent startup lag.") {
                        Picker("Delay", selection: $store.preferences.launchDelay) {
                            Text("Instant (No Delay)").tag(0)
                            Text("5 Seconds").tag(5)
                            Text("15 Seconds").tag(15)
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
            }

            settingsCard("Dashboard & Live Activity", symbol: "bell.badge.fill", color: .indigo) {
                settingsRow("Show Website Alerts", "Stream unread badges and notification summaries onto the Overview screen.") {
                    Toggle("Website Alerts", isOn: $store.preferences.showWebsiteAlerts)
                        .labelsHidden()
                        .tint(Palette.accent)
                }

                Divider()

                settingsRow("Interface Language", "Language for menus, prompts, and interface controls.") {
                    Picker("Language", selection: $store.preferences.language) {
                        Text("Follow System").tag("Follow System")
                        Text("English").tag("English")
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
            }

            settingsCard("Web Links & Browser", symbol: "safari.fill", color: .teal) {
                settingsRow("Open in PINGGO Browser", "Open external articles and web links inside PINGGO's built-in tabbed browser instead of external Safari/Chrome.") {
                    Toggle("In-App Browser", isOn: $store.preferences.openLinksInAppBrowser)
                        .labelsHidden()
                        .tint(Palette.accent)
                }
            }

            settingsCard("Media & Video Downloads", symbol: "arrow.down.circle.fill", color: .green) {
                settingsRow("Download Location", "Folder where saved videos, clips, and status media are stored.") {
                    HStack(spacing: 8) {
                        Text(store.preferences.videoDownloadFolder.isEmpty ? "~/Downloads" : (URL(fileURLWithPath: store.preferences.videoDownloadFolder).lastPathComponent))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .frame(maxWidth: 160, alignment: .trailing)

                        Button("Choose Folder…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            panel.prompt = "Select Download Folder"
                            if panel.runModal() == .OK, let url = panel.url {
                                store.preferences.videoDownloadFolder = url.path
                            }
                        }
                        .controlSize(.small)

                        if !store.preferences.videoDownloadFolder.isEmpty {
                            Button("Reset") {
                                store.preferences.videoDownloadFolder = ""
                            }
                            .controlSize(.small)
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                        }
                    }
                }

                Divider()

                settingsRow("Floating Video Download Pill", "Show a floating download button when hovering over videos in feeds and players.") {
                    Toggle("Hover Pill", isOn: $store.preferences.showVideoHoverPill)
                        .labelsHidden()
                        .tint(Palette.accent)
                }
            }
        }
    }

    private var securityPage: some View {
        VStack(spacing: 24) {
            settingsCard("App Lock", symbol: "lock.shield.fill", color: .purple) {
                settingsRow("Enable App Lock", "Require authentication to access your connected social accounts.") {
                    Toggle("App Lock", isOn: $store.preferences.appLockEnabled)
                        .labelsHidden()
                        .tint(Palette.accent)
                }

                if store.preferences.appLockEnabled {
                    Divider()

                    settingsRow("Lock Method", "Choose whether to use macOS Touch ID or a dedicated PINGGO PIN / Password.") {
                        Picker("Lock Method", selection: $store.preferences.lockMethod) {
                            Text("Touch ID / Mac Passcode").tag("biometric")
                            Text("PINGGO Custom PIN / Password").tag("customPin")
                        }
                        .labelsHidden()
                        .frame(width: 230)
                        .onChange(of: store.preferences.lockMethod) { _, newMethod in
                            if newMethod == "customPin" && !store.hasCustomPin {
                                pinSetupIsChanging = false
                                showingPinSetupSheet = true
                            } else if newMethod == "biometric" && store.hasCustomPin {
                                store.removeCustomPin()
                            }
                        }
                    }

                    if store.preferences.lockMethod == "customPin" || store.hasCustomPin {
                        Divider()

                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("PINGGO PIN / Password")
                                        .font(.system(size: 13, weight: .semibold))
                                    if store.hasCustomPin {
                                        HStack(spacing: 3) {
                                            Image(systemName: "checkmark.shield.fill")
                                                .foregroundStyle(.green)
                                            Text("Strict Custom Lock Active")
                                                .foregroundStyle(.green)
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.12), in: Capsule())
                                    } else {
                                        HStack(spacing: 3) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.orange)
                                            Text("Not Set")
                                                .foregroundStyle(.orange)
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                    }
                                }

                                if store.hasCustomPin {
                                    if !store.preferences.customPinHint.isEmpty {
                                        Text("Hint: \"\(store.preferences.customPinHint)\"")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Palette.muted)
                                    }
                                    Text("Touch ID and Mac system passcode are disabled. PINGGO unlocks strictly with your custom password.")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Palette.muted)
                                } else {
                                    Text("Set a dedicated password specifically for PINGGO to unlock without Touch ID.")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Palette.muted)
                                }
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                if store.hasCustomPin {
                                    Button("Change Password") {
                                        pinSetupIsChanging = true
                                        showingPinSetupSheet = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Remove (Use Touch ID)", role: .destructive) {
                                        store.removeCustomPin()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button("Set Password Now") {
                                        pinSetupIsChanging = false
                                        showingPinSetupSheet = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(Palette.accent)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Divider()

                    settingsRow("Auto-Lock", "Automatically lock after inactivity or when the display sleeps.") {
                        Picker("Auto-Lock", selection: $store.preferences.autoLockMinutes) {
                            Text("Immediately").tag(0)
                            Text("After 1 minute").tag(1)
                            Text("After 5 minutes").tag(5)
                            Text("After 15 minutes").tag(15)
                            Text("After 30 minutes").tag(30)
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }

                    Divider()

                    settingsRow("Lock Immediately", "Lock PINGGO now. You can also press ⌘L anywhere.") {
                        Button("Lock Now") {
                            store.lockApp()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // Apple Keychain & Passwords Diagnostics
            settingsCard("Apple Keychain & Passwords Diagnostics", symbol: "key.fill", color: .green) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("iCloud Keychain Status")
                                .font(.system(size: 13, weight: .semibold))
                            if KeychainHelper.getPassword() != nil {
                                HStack(spacing: 3) {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                    Text("Password Stored in Keychain")
                                        .foregroundStyle(.green)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12), in: Capsule())
                            } else {
                                HStack(spacing: 3) {
                                    Circle().fill(Color.secondary).frame(width: 6, height: 6)
                                    Text("No Password in Keychain")
                                        .foregroundStyle(Palette.muted)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.card, in: Capsule())
                            }
                        }
                        Text("PINGGO App Lock credentials can be synced with Apple Passwords and macOS Keychain for biometric autofill.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button("Verify Keychain") {
                            if let saved = KeychainHelper.getPassword() {
                                keychainDiagnosticResult = "✅ Keychain verified! Stored password (\(saved.count) chars) retrieved successfully."
                            } else {
                                keychainDiagnosticResult = "ℹ️ No App Lock password is currently stored in Apple Keychain."
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords") {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            } else if let url = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                            store.showToast("Opening Apple Passwords...")
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.forward.app")
                                Text("Open Passwords")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(Palette.accent)
                    }
                }
                .padding(.vertical, 4)

                if let diag = keychainDiagnosticResult {
                    Text(diag)
                        .font(.system(size: 11.5, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var performancePage: some View {
        VStack(spacing: 20) {
            settingsCard("Memory Saver & Tab Freezing", symbol: "bolt.fill", color: .orange) {
                settingsRow("Smart Tab Freezing", "Automatically hibernate background web portals to dramatically conserve RAM and battery life.") {
                    Toggle("Tab Freezing", isOn: $store.preferences.tabFreezingEnabled)
                        .labelsHidden()
                        .tint(Palette.accent)
                }

                if store.preferences.tabFreezingEnabled {
                    Divider()

                    settingsRow("Freeze Inactivity Timeout", "Unload web view memory when a tab has been inactive for this duration.") {
                        Picker("Freeze Timeout", selection: $store.preferences.tabFreezeMinutes) {
                            Text("5 minutes").tag(5)
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("60 minutes").tag(60)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }

                    Divider()

                    settingsRow("Hibernate Background Tabs", "Instantly release memory for all portals not currently visible.") {
                        HStack(spacing: 8) {
                            if hibernatedFeedback {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Memory Released!")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green)
                            }

                            Button {
                                PortalSessionRegistry.shared.hibernateAllInactive(activeAccountIDs: Set(store.currentActiveAccountIDs))
                                hibernatedFeedback = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    hibernatedFeedback = false
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "leaf.fill")
                                    Text("Free RAM Now")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            settingsCard("Resource Optimization Metrics", symbol: "chart.bar.fill", color: .green) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sleeping Tabs")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                        Text("\(store.sleepingSessionCount())")
                            .font(.system(size: 20, weight: .bold))
                        Text("Hibernate background processes")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Estimated RAM Saved")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                        let mb = store.sleepingSessionCount() * 140 + (store.sleepingSessionCount() > 0 ? 60 : 0)
                        Text("\(mb) MB")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.green)
                        Text("WebKit process suspension")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))
                }
            }
        }
    }

    private var aboutPage: some View {
        VStack(spacing: 20) {
            // App Branding Banner
            VStack(spacing: 10) {
                AppLogo(size: 64, cornerRadius: 14)
                    .shadow(color: .black.opacity(0.14), radius: 8, y: 4)

                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Text("PINGGO")
                            .font(.system(size: 20, weight: .bold))
                        Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Palette.card, in: Capsule())
                    }

                    Text("All your social workspaces in one native macOS application")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)

            settingsCard("Power Keyboard Shortcuts", symbol: "command", color: .purple) {
                VStack(spacing: 8) {
                    shortcutCheatRow("Command Palette", "Global search & quick switcher", "⌘K")
                    Divider()
                    shortcutCheatRow("Toggle Split View", "Side-by-side workspace comparison", "⌘\\")
                    Divider()
                    shortcutCheatRow("Lock PINGGO", "Immediate biometric / password lock", "⌘L")
                    Divider()
                    shortcutCheatRow("Open Settings", "Preferences and configuration", "⌘,")
                    Divider()
                    shortcutCheatRow("Overview Screen", "Home dashboard & activity stream", "⌘1")
                    Divider()
                    shortcutCheatRow("Private Browser", "Tabbed web browser with adblocker", "⌘2")
                }
            }

            settingsCard("Support & Legal", symbol: "shield.lefthalf.filled", color: .cyan) {
                settingsRow("User Guide & Portal Help", "Learn how multi-account sessions and portals work.") {
                    Button("Open Guide") { detail = "Help" }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Divider()

                settingsRow("Privacy & Data Isolation", "Learn how WebKit cookies, credentials, and AI queries are isolated.") {
                    Button("View Privacy Policy") { detail = "Privacy" }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private func shortcutCheatRow(_ name: String, _ desc: String, _ key: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.card, lineWidth: 1))
        }
    }

    private func settingsCard<Content: View>(_ title: String, symbol: String, color: Color,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
                Text(title)
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            VStack(alignment: .leading, spacing: 14, content: content)
                .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.card, lineWidth: 1))
    }

    private func settingsRow<Control: View>(_ title: String, _ subtitle: String,
                                             @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                rowLabel(title, subtitle)
                Spacer(minLength: 8)
                control()
            }
            VStack(alignment: .leading, spacing: 8) {
                rowLabel(title, subtitle)
                control()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rowLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Palette.muted)
        }
    }

    private func accentColor(_ name: String) -> Color {
        switch name {
        case "blue": .blue
        case "cyan": .cyan
        case "orange": .orange
        case "green": .green
        case "pink": .pink
        default: Color(red: 0.42, green: 0.48, blue: 0.98)
        }
    }

    private func detailSheet(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(name).font(.system(size: 23, weight: .bold))
            if name == "Privacy" {
                Text("Your platform sessions are stored by WebKit on this Mac. Chat previews and website alerts shown on Home stay in memory and clear when PINGGO quits. Your local profile, chats, and posts are saved in Application Support. PINGGO does not read passwords.")
            } else {
                Text("Choose a social app in the sidebar. Use the account menu beside its name to add, switch, or rename accounts. Each added account has its own website login. Home shows chat previews when the websites expose them. Use the sidebar plus button to add a platform.")
            }
            Spacer()
            Button("Done") { detail = nil }.buttonStyle(.borderedProminent).tint(Palette.accent)
        }
        .padding(25)
        .frame(width: 430, height: 240)
    }
}

private struct DetailSheet: Identifiable {
    let id: String
}

struct CustomPinSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    var isChangingExisting: Bool = false

    @State private var currentPinInput = ""
    @State private var newPinInput = ""
    @State private var confirmPinInput = ""
    @State private var hintInput = ""
    @State private var showPinText = false
    @State private var saveToApplePasswords = true
    @State private var errorMessage: String? = nil
    @FocusState private var focusedField: SetupField?

    enum SetupField {
        case current, new, confirm, hint
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: "key.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isChangingExisting ? "Change PINGGO PIN / Password" : "Set PINGGO PIN / Password")
                        .font(.system(size: 16, weight: .bold))
                    Text("Use a numeric PIN (e.g. 4-8 digits) or alphanumeric password.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.muted)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(spacing: 14) {
                // If changing, require current PIN
                if isChangingExisting && store.hasCustomPin {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Current PIN / Password")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Palette.muted)
                            Spacer()
                            if KeychainHelper.getPassword() != nil {
                                Button {
                                    if let saved = KeychainHelper.getPassword() {
                                        currentPinInput = saved
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "key.fill")
                                            .font(.system(size: 9))
                                        Text("AutoFill from Apple Passwords")
                                    }
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        pinInputField(placeholder: "Enter current PIN", text: $currentPinInput, isNew: false)
                            .focused($focusedField, equals: .current)
                    }
                }

                // New PIN
                VStack(alignment: .leading, spacing: 5) {
                    Text("New PIN / Password (min 4 characters)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.muted)

                    pinInputField(placeholder: "Enter new PIN or password", text: $newPinInput, isNew: true)
                        .focused($focusedField, equals: .new)
                }

                // Confirm PIN
                VStack(alignment: .leading, spacing: 5) {
                    Text("Confirm New PIN / Password")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.muted)

                    pinInputField(placeholder: "Re-enter new PIN or password", text: $confirmPinInput, isNew: true)
                        .focused($focusedField, equals: .confirm)
                }

                // Password Hint
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Password Reminder Hint (Optional)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.muted)
                        Spacer()
                    }

                    TextField("e.g. Favorite street or birthday", text: $hintInput)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .hint)
                }

                // Save to Apple Passwords Toggle
                Toggle(isOn: $saveToApplePasswords) {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(Palette.accent)
                            .font(.system(size: 11))
                        Text("Save to Apple Passwords / iCloud Keychain")
                            .font(.system(size: 11.5))
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.top, 2)

                // Show/hide toggle
                HStack {
                    Button {
                        showPinText.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showPinText ? "eye.slash" : "eye")
                            Text(showPinText ? "Hide characters" : "Show characters")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save PIN / Password") {
                    savePin()
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            if isChangingExisting {
                hintInput = store.preferences.customPinHint
                focusedField = .current
            } else {
                focusedField = .new
            }
        }
    }

    @ViewBuilder
    private func pinInputField(placeholder: String, text: Binding<String>, isNew: Bool = false) -> some View {
        HStack {
            if showPinText {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(isNew ? .newPassword : .password)
            } else {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(isNew ? .newPassword : .password)
            }
        }
    }

    private func savePin() {
        errorMessage = nil

        if isChangingExisting && store.hasCustomPin {
            if !store.verifyCustomPin(currentPinInput) {
                errorMessage = "The current PIN or password you entered is incorrect."
                focusedField = .current
                return
            }
        }

        let trimmed = newPinInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 4 {
            errorMessage = "PIN or password must be at least 4 characters long."
            focusedField = .new
            return
        }

        if newPinInput != confirmPinInput {
            errorMessage = "The confirmed PIN or password does not match."
            focusedField = .confirm
            return
        }

        store.setCustomPin(
            newPinInput,
            hint: hintInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : hintInput.trimmingCharacters(in: .whitespacesAndNewlines),
            saveToKeychain: saveToApplePasswords
        )
        store.preferences.lockMethod = "customPin"
        store.showToast(saveToApplePasswords ? "Saved to Apple Passwords & strict lock active" : "Strict custom password active")
        dismiss()
    }
}

struct SocialLoginItem: Identifiable {
    var id: String { provider }
    let provider: String
}

struct SocialLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let providerName: String

    @State private var customName: String = ""
    @State private var customEmail: String = ""
    @State private var selectedTier: String = "PINGGO Pro (Annual)"
    @State private var isSigningIn: Bool = false

    private var providerBrandColor: Color {
        switch providerName {
        case "Apple": return .primary
        case "Google": return Color(red: 0.92, green: 0.26, blue: 0.21)
        case "Microsoft": return Color(red: 0.0, green: 0.63, blue: 0.94)
        default: return Palette.accent
        }
    }

    private var providerSymbol: String {
        switch providerName {
        case "Apple": return "apple.logo"
        case "Google": return "g.circle.fill"
        case "Microsoft": return "square.grid.2x2.fill"
        default: return "person.crop.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(providerBrandColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: providerSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(providerBrandColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in with \(providerName)")
                        .font(.system(size: 16, weight: .bold))
                    Text("Connect your account to store subscriptions & sync workspaces.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.muted)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // 1-Click Quick Demo Presets
            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK 1-CLICK DEMO ACCOUNTS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .tracking(1)

                ForEach(presetsForProvider(), id: \.email) { preset in
                    Button {
                        completeSignIn(name: preset.name, email: preset.email, tier: preset.tier)
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Palette.accent.opacity(0.15))
                                    .frame(width: 28, height: 28)
                                Text(String(preset.name.prefix(1)))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.accent)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(preset.email)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.muted)
                            }

                            Spacer()

                            Text(preset.tier)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.accent.opacity(0.1), in: Capsule())

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                        }
                        .padding(10)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Custom Account Option
            VStack(alignment: .leading, spacing: 10) {
                Text("OR SIGN IN WITH CUSTOM CREDENTIALS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .tracking(1)

                VStack(spacing: 8) {
                    TextField("Full Name (e.g. Nikita Jangid)", text: $customName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Email Address (e.g. nikita@\(providerName.lowercased()).com)", text: $customEmail)
                        .textFieldStyle(.roundedBorder)

                    Picker("Cloud Subscription", selection: $selectedTier) {
                        Text("PINGGO Pro (Annual)").tag("PINGGO Pro (Annual)")
                        Text("PINGGO Lifetime Cloud").tag("PINGGO Lifetime Cloud")
                        Text("Free Tier").tag("Free Tier")
                    }
                    .pickerStyle(.segmented)
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    let name = customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nikita" : customName
                    let email = customEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "nikita@\(providerName.lowercased()).com" : customEmail
                    completeSignIn(name: name, email: email, tier: selectedTier)
                } label: {
                    if isSigningIn {
                        ProgressView().controlSize(.small)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: providerSymbol)
                            Text("Sign In with \(providerName)")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .disabled(isSigningIn)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            customName = store.userProfile.displayName
            customEmail = "nikita@\(providerName.lowercased()).com"
        }
    }

    private struct DemoPreset {
        let name: String
        let email: String
        let tier: String
    }

    private func presetsForProvider() -> [DemoPreset] {
        switch providerName {
        case "Google":
            return [
                DemoPreset(name: "Alex Chen", email: "alex.chen@gmail.com", tier: "PINGGO Pro"),
                DemoPreset(name: "Elena Rostova", email: "elena.work@googlemail.com", tier: "PINGGO Lifetime")
            ]
        case "Apple":
            return [
                DemoPreset(name: "Sarah Connor", email: "sarah.appleid@icloud.com", tier: "PINGGO Pro"),
                DemoPreset(name: "David Miller", email: "david.m@me.com", tier: "PINGGO Pro Family")
            ]
        case "Microsoft":
            return [
                DemoPreset(name: "Jordan Taylor", email: "jordan.taylor@outlook.com", tier: "PINGGO Pro"),
                DemoPreset(name: "Morgan Reed", email: "m.reed@live.com", tier: "PINGGO Enterprise")
            ]
        default:
            return [
                DemoPreset(name: "Nikita", email: "nikita@pinggo.internal", tier: "PINGGO Pro")
            ]
        }
    }

    private func completeSignIn(name: String, email: String, tier: String) {
        isSigningIn = true
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            await MainActor.run {
                store.signInWith(provider: providerName, name: name, email: email, tier: tier)
                isSigningIn = false
                dismiss()
            }
        }
    }
}

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var nameInput: String = ""
    @State private var emailInput: String = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Edit Profile Details")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }
                    .buttonStyle(.plain)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Display Name").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.muted)
                TextField("Display Name", text: $nameInput).textFieldStyle(.roundedBorder)

                Text("Email Address").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Palette.muted)
                TextField("Email Address", text: $emailInput).textFieldStyle(.roundedBorder)
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    store.updateProfileDetails(name: nameInput, email: emailInput)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            nameInput = store.userProfile.displayName
            emailInput = store.userProfile.email
        }
    }
}
