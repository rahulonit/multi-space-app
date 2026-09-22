import SwiftUI
import WebKit

enum SettingsPage: String, CaseIterable {
    case profile = "Profile", general = "General", ai = "AI Assistant", security = "Security", launch = "Performance"
    case interaction = "Interaction", subscription = "Subscription", about = "About"

    var symbol: String {
        switch self {
        case .profile: "person.crop.circle.fill"
        case .general: "gearshape.fill"
        case .ai: "sparkles"
        case .security: "lock.shield.fill"
        case .launch: "bolt.fill"
        case .interaction: "cursorarrow.click.2"
        case .subscription: "crown.fill"
        case .about: "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .profile: .indigo
        case .general: .cyan
        case .ai: .purple
        case .security: .purple
        case .launch: .orange
        case .interaction: .blue
        case .subscription: .yellow
        case .about: .blue
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    var initialPage: SettingsPage? = nil
    @State private var page: SettingsPage = .profile
    @State private var detail: String?
    @State private var hibernatedFeedback = false
    @State private var showingPinSetupSheet = false
    @State private var pinSetupIsChanging = false
    @State private var selectedSocialLoginProvider: String? = nil
    @State private var activeAILoginProvider: String? = nil
    @State private var showingEditProfileSheet = false
    @State private var showGeminiApiKey = false
    @State private var showOpenAiApiKey = false
    @State private var testingAiConnection = false
    @State private var aiTestResult: (success: Bool, message: String)? = nil
    @State private var keychainDiagnosticResult: String? = nil

    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 750
            HStack(spacing: 0) {
                if !narrow { settingsSidebar }
                ScrollView {
                    VStack(alignment: .leading, spacing: 25) {
                        if narrow {
                            HStack {
                                Button { store.destination = .home } label: {
                                    Label("Back", systemImage: "chevron.left")
                                }
                                Spacer()
                                Picker("Settings", selection: $page) {
                                    ForEach(SettingsPage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 190)
                            }
                        }
                        Text(page.rawValue)
                            .font(.system(size: 27, weight: .bold))
                            .padding(.bottom, 28)
                        switch page {
                        case .profile: profilePage
                        case .general: generalPage
                        case .ai: aiSettingsPage
                        case .security: securityPage
                        case .launch: launchPage
                        case .interaction: interactionPage
                        case .subscription: subscriptionPage
                        case .about: aboutPage
                        }
                    }
                    .padding(narrow ? 22 : 30)
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
                page = .profile
            } else if store.destination == .settings {
                page = .general
            }
        }
        .onChange(of: store.destination) { _, newDestination in
            if newDestination == .profile {
                page = .profile
            } else if newDestination == .settings && page == .profile {
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
        .sheet(item: Binding(
            get: { activeAILoginProvider.map { AILoginProviderItem(id: $0) } },
            set: { activeAILoginProvider = $0?.id }
        )) { item in
            AILoginWebSheet(provider: item.id)
        }
        .sheet(isPresented: $showingEditProfileSheet) {
            EditProfileSheet()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { store.destination = .home } label: {
                Label("Back to PINGGO", systemImage: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 13)
            Text("Settings")
                .font(.system(size: 19, weight: .bold))
                .padding(.horizontal, 13)
                .padding(.top, 12)
                .padding(.bottom, 18)
            ForEach(SettingsPage.allCases, id: \.self) { item in
                Button { page = item } label: {
                    HStack(spacing: 11) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(item.color.gradient, in: RoundedRectangle(cornerRadius: 9))
                        Text(item.rawValue).font(.system(size: 15, weight: page == item ? .semibold : .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 11)
                    .frame(height: 48)
                    .background(page == item ? Palette.accent.opacity(0.52) : .clear,
                                in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { store.destination = .profile } label: {
                Label("Edit profile", systemImage: "person.crop.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            .padding(13)
        }
        .padding(12)
        .frame(width: 210)
        .background(Palette.sidebar)
    }

    private var profilePage: some View {
        VStack(spacing: 24) {
            if !store.userProfile.isSignedIn {
                guestProfileBanner
                socialLoginSection
                localUserCard
                syncBenefitsCard
            } else {
                authenticatedUserCard
                cloudSubscriptionCard
                cloudBackupCard
            }
        }
    }

    private var guestProfileBanner: some View {
        settingsCard("Cloud Account & Sync", symbol: "cloud.fill", color: .indigo) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Store Subscription & Sync Workspaces Across Devices")
                    .font(.system(size: 15, weight: .bold))
                Text("Sign in with Google, Apple, or Microsoft to back up your social workspaces, sync your PINGGO Pro subscription, and restore custom URLs and platforms on any Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(2)
            }
        }
    }

    private var socialLoginSection: some View {
        settingsCard("Sign In Options", symbol: "person.badge.key.fill", color: .blue) {
            VStack(spacing: 12) {
                socialLoginRow(
                    provider: "Apple",
                    icon: "apple.logo",
                    iconColor: .primary,
                    title: "Continue with Apple",
                    desc: "Fast Touch ID & iCloud Keychain sync",
                    badge: " Apple ID"
                )

                Divider()

                socialLoginRow(
                    provider: "Google",
                    icon: "g.circle.fill",
                    iconColor: Color(red: 0.92, green: 0.26, blue: 0.21),
                    title: "Continue with Google",
                    desc: "Sync via Google Cloud & Workspace",
                    badge: "Google Cloud"
                )

                Divider()

                socialLoginRow(
                    provider: "Microsoft",
                    icon: "square.grid.2x2.fill",
                    iconColor: Color(red: 0.0, green: 0.63, blue: 0.94),
                    title: "Continue with Microsoft",
                    desc: "Sync via Microsoft Account & Entra ID",
                    badge: "Microsoft 365"
                )
            }
        }
    }

    private func socialLoginRow(provider: String, icon: String, iconColor: Color, title: String, desc: String, badge: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(badge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Palette.panel, in: Capsule())
                }
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }

            Spacer()

            Button("Sign In") {
                selectedSocialLoginProvider = provider
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Palette.accent)
        }
    }

    private var localUserCard: some View {
        settingsCard("Local Profile (Offline)", symbol: "laptopcomputer", color: .gray) {
            HStack(spacing: 14) {
                Avatar(member: store.me, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.me.name)
                        .font(.system(size: 14, weight: .bold))
                    Text("@\(store.me.handle) · \(store.me.status)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                    Text("Currently saved only on this Mac. Sign in above to sync to cloud.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Button("Edit Name") {
                    showingEditProfileSheet = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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

    private var authenticatedUserCard: some View {
        settingsCard("Connected Account", symbol: "person.crop.circle.fill.badge.checkmark", color: .green) {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Palette.accent.opacity(0.2))
                            .frame(width: 52, height: 52)
                        Text(String(store.userProfile.displayName.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Palette.accent)

                        ZStack {
                            Circle()
                                .fill(Palette.panel)
                                .frame(width: 20, height: 20)
                            Image(systemName: providerSymbol(store.userProfile.provider ?? ""))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(providerColor(store.userProfile.provider ?? ""))
                        }
                        .offset(x: 2, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(store.userProfile.displayName)
                                .font(.system(size: 15, weight: .bold))
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill")
                                Text("Synced")
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                        }

                        Text(store.userProfile.email)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)

                        Text("Signed in with \(store.userProfile.provider ?? "Cloud Account")")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Button("Edit Details") {
                            showingEditProfileSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Sign Out", role: .destructive) {
                            store.signOutProfile()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
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

    private var cloudSubscriptionCard: some View {
        settingsCard("Cloud Subscription & License", symbol: "crown.fill", color: .yellow) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(store.userProfile.subscriptionTier)
                                .font(.system(size: 14, weight: .bold))
                            Text("ACTIVE")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        }
                        Text("Linked to \(store.userProfile.email)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Renews Oct 24, 2027")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("Ref: #PG-\(abs(store.userProfile.email.hashValue % 90000) + 10000)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(10)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))

                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 12))
                    Text("Cloud License verified via \(store.userProfile.provider ?? "Provider") In-App Billing.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Button("Manage Plan") {
                        page = .subscription
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var cloudBackupCard: some View {
        settingsCard("User Data & Cloud Sync", symbol: "arrow.triangle.2.circlepath.circle.fill", color: .cyan) {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cloud Storage Quota")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(store.userProfile.cloudStorageUsage)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                    ProgressView(value: 0.03)
                        .tint(Palette.accent)
                }

                Divider()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Synced Items")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("• \(store.socialPlatforms.count) Social Platforms & URLs")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                        Text("• \(store.platformAccounts.count) Active Accounts & Sessions")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                        Text("• App Preferences & App Lock")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Last Backup")
                            .font(.system(size: 11.5, weight: .semibold))
                        if let backup = store.userProfile.lastCloudBackup {
                            Text(backup.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(.green)
                        } else {
                            Text("Never")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
                .padding(10)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))

                Divider()

                HStack {
                    Toggle("Auto-Sync Changes", isOn: $store.userProfile.autoCloudSync)
                        .font(.system(size: 11.5))
                        .tint(Palette.accent)

                    Spacer()

                    Button {
                        let json = store.exportUserDataJSON()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                        store.showToast("Exported user data JSON copied to clipboard!")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Data")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        store.triggerCloudSync()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync Now")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Palette.accent)
                }
            }
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
                        Text("Log into your Google Gemini or ChatGPT account directly—no developer API keys or billing setup required.")
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

                settingsRow("Stealth Mode Default", "When opening unread chats in Inbox, inspect messages and AI analysis without loading the interactive portal (no read receipts sent).") {
                    Toggle("Stealth Mode", isOn: $store.preferences.stealthModeDefault)
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

            // Connected Accounts Card
            settingsCard("Connected AI Accounts", symbol: "person.badge.shield.checkmark.fill", color: .indigo) {
                // Google Gemini Card
                aiAccountRow(
                    title: "Google Gemini",
                    subtitle: "gemini.google.com · Google Account",
                    icon: "sparkles",
                    color: Color(red: 0.26, green: 0.52, blue: 0.96),
                    isLoggedIn: store.preferences.isGeminiLoggedIn,
                    provider: "gemini"
                )

                Divider()

                // OpenAI ChatGPT Card
                aiAccountRow(
                    title: "OpenAI ChatGPT",
                    subtitle: "chatgpt.com · OpenAI Account",
                    icon: "bubble.left.and.bubble.right.fill",
                    color: Color(red: 0.06, green: 0.65, blue: 0.53),
                    isLoggedIn: store.preferences.isChatGptLoggedIn,
                    provider: "chatgpt"
                )
            }

            // Direct API Keys & Models
            settingsCard("API Keys & Direct Integration", symbol: "key.horizontal.fill", color: .blue) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Optional Direct API Access")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Provide your personal API keys for direct REST API communication. If left empty, PINGGO uses the local Apple ML Smart Engine or your logged-in web partition.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }

                Divider()

                // Google Gemini Key
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                        Text("Google Gemini API Key")
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Picker("Model", selection: $store.preferences.aiModelTier) {
                            Text("gemini-1.5-flash").tag("gemini-1.5-flash")
                            Text("gemini-1.5-pro").tag("gemini-1.5-pro")
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    HStack(spacing: 8) {
                        Group {
                            if showGeminiApiKey {
                                TextField("AIzaSy...", text: $store.preferences.geminiApiKey)
                            } else {
                                SecureField("AIzaSy...", text: $store.preferences.geminiApiKey)
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

                        Button("Test Key") {
                            testingAiConnection = true
                            aiTestResult = nil
                            Task {
                                let res = await AIService.shared.testAPIConnection(
                                    provider: "gemini",
                                    apiKey: store.preferences.geminiApiKey,
                                    model: store.preferences.aiModelTier
                                )
                                testingAiConnection = false
                                aiTestResult = res
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.preferences.geminiApiKey.isEmpty || testingAiConnection)
                    }
                }

                Divider()

                // OpenAI ChatGPT Key
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(Color(red: 0.06, green: 0.65, blue: 0.53))
                        Text("OpenAI ChatGPT API Key")
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Picker("Model", selection: $store.preferences.aiModelTier) {
                            Text("gpt-4o-mini").tag("gpt-4o-mini")
                            Text("gpt-4o").tag("gpt-4o")
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    HStack(spacing: 8) {
                        Group {
                            if showOpenAiApiKey {
                                TextField("sk-proj-...", text: $store.preferences.openAiApiKey)
                            } else {
                                SecureField("sk-proj-...", text: $store.preferences.openAiApiKey)
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

                        Button("Test Key") {
                            testingAiConnection = true
                            aiTestResult = nil
                            Task {
                                let res = await AIService.shared.testAPIConnection(
                                    provider: "chatgpt",
                                    apiKey: store.preferences.openAiApiKey,
                                    model: store.preferences.aiModelTier
                                )
                                testingAiConnection = false
                                aiTestResult = res
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.preferences.openAiApiKey.isEmpty || testingAiConnection)
                    }
                }

                Divider()

                // Ollama Local LLM (Offline / Privacy-First)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "cpu.fill")
                            .foregroundStyle(.purple)
                        Text("Ollama Local LLM (Offline / Privacy-First)")
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        TextField("llama3.2", text: $store.preferences.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 140)
                    }

                    HStack(spacing: 8) {
                        TextField("http://localhost:11434", text: $store.preferences.ollamaEndpoint)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button("Test Local Server") {
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
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(testingAiConnection)
                    }
                }

                if let res = aiTestResult {
                    HStack(spacing: 8) {
                        Image(systemName: res.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(res.success ? .green : .red)
                        Text(res.message)
                            .font(.system(size: 11.5))
                            .foregroundStyle(res.success ? .green : .red)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((res.success ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func aiAccountRow(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isLoggedIn: Bool,
        provider: String
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    if isLoggedIn {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("Connected")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                    } else {
                        Text("Not Logged In")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Palette.card.opacity(0.6), in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }

            Spacer()

            if isLoggedIn {
                Button("Re-login") {
                    activeAILoginProvider = provider
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Sign Out") {
                    Task {
                        await AIService.shared.signOut(provider: provider, store: store)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    activeAILoginProvider = provider
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Log In")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .controlSize(.small)
            }
        }
    }

    private var generalPage: some View {
        VStack(spacing: 24) {
            settingsCard("Language Settings", symbol: "character.book.closed.fill", color: .indigo) {
                settingsRow("Language", "English is the available interface language in this build.") {
                    Picker("Language", selection: $store.preferences.language) {
                        Text("Follow System").tag("Follow System")
                        Text("English").tag("English")
                    }
                    .labelsHidden().frame(width: 190)
                }
            }
            settingsCard("Appearance", symbol: "paintpalette.fill", color: .cyan) {
                settingsRow("Appearance", "Choose the interface appearance.") {
                    Picker("Appearance", selection: $store.preferences.appearance) {
                        Text("Follow System").tag("Follow System")
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 340)
                }
                Divider()
                settingsRow("Accent Color", "Used for buttons and selection.") {
                    HStack(spacing: 9) {
                        ForEach(["blue", "cyan", "indigo", "orange", "green", "pink"], id: \.self) { color in
                            Button { store.preferences.accent = color } label: {
                                Circle().fill(accentColor(color))
                                    .frame(width: 25, height: 25)
                                    .padding(4)
                                    .overlay(Circle().stroke(.primary.opacity(store.preferences.accent == color ? 0.9 : 0), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(color.capitalized) accent")
                        }
                    }
                }
                Divider()
                settingsRow("Compact Mode", "Use a tighter layout.") {
                    Toggle("Compact Mode", isOn: $store.preferences.compactMode).labelsHidden().tint(Palette.accent)
                }
            }
            settingsCard("Startup", symbol: "house.fill", color: .blue) {
                settingsRow("Open To", "Default view when PINGGO opens.") {
                    Picker("Open To", selection: $store.preferences.openTo) {
                        Text("Home").tag("Home")
                        Text("Last Platform").tag("Last Platform")
                    }
                    .labelsHidden().frame(width: 190)
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

    private var launchPage: some View {
        VStack(spacing: 24) {
            settingsCard("Memory Saver & Tab Freezing", symbol: "bolt.fill", color: .orange) {
                settingsRow("Smart Tab Freezing", "Hibernate inactive web views to dramatically reduce RAM and battery usage.") {
                    Toggle("Tab Freezing", isOn: $store.preferences.tabFreezingEnabled)
                        .labelsHidden()
                        .tint(Palette.accent)
                }
                if store.preferences.tabFreezingEnabled {
                    Divider()
                    settingsRow("Freeze Inactive Tabs", "Unload web portals when not used for a period of time.") {
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
                    settingsRow("Hibernate Background Tabs", "Free RAM immediately for all tabs not currently active.") {
                        HStack(spacing: 8) {
                            if hibernatedFeedback {
                                Text("Hibernated!")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.green)
                            }
                            Button("Hibernate Inactive Tabs") {
                                PortalSessionRegistry.shared.hibernateAllInactive(activeAccountIDs: Set(store.currentActiveAccountIDs))
                                hibernatedFeedback = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    hibernatedFeedback = false
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            settingsCard("Startup & Background", symbol: "play.fill", color: .cyan) {
                settingsRow("Websites Check", "Check your connected accounts when PINGGO opens.") {
                    Toggle("Websites", isOn: $store.preferences.launchWebsites).labelsHidden().tint(Palette.accent)
                }
                Divider()
                settingsRow("Check Delay", "Wait before checking websites on startup.") {
                    Picker("Delay", selection: $store.preferences.launchDelay) {
                        Text("No Delay").tag(0)
                        Text("5 Seconds").tag(5)
                        Text("15 Seconds").tag(15)
                    }
                    .labelsHidden().frame(width: 160)
                }
            }
        }
    }

    private var interactionPage: some View {
        VStack(spacing: 24) {
            settingsCard("Dashboard", symbol: "cursorarrow.click.2", color: .blue) {
                settingsRow("Website Alerts", "Show alerts exposed by social websites on Home.") {
                    Toggle("Website Alerts", isOn: $store.preferences.showWebsiteAlerts).labelsHidden().tint(Palette.accent)
                }
            }
            Text("Message previews depend on what each signed-in website makes available.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subscriptionPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Purchase Info").font(.system(size: 22, weight: .bold))
            settingsCard("Subscription", symbol: "crown.fill", color: .yellow) {
                settingsRow("Purchase Status", "PINGGO is currently a local prototype.") {
                    Text("No subscription")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .padding(9)
                        .background(Palette.card, in: Capsule())
                }
                Divider()
                Text("Purchases are not available in this build.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var aboutPage: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                AppLogo(size: 72, cornerRadius: 16)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
                Text("PINGGO")
                    .font(.system(size: 22, weight: .bold))
                Text("All your social apps, in one native macOS workspace")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

            settingsCard("App Info", symbol: "info.circle.fill", color: .blue) {
                settingsRow("Version", "PINGGO") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                        .foregroundStyle(Palette.muted)
                }
            }
            settingsCard("Support", symbol: "questionmark.circle.fill", color: .cyan) {
                settingsRow("Help", "How to use social portals and the dashboard.") {
                    Button("Open") { detail = "Help" }
                }
                Divider()
                settingsRow("Privacy", "Learn how local data is handled.") {
                    Button("Open") { detail = "Privacy" }
                }
            }
        }
    }

    private func settingsCard<Content: View>(_ title: String, symbol: String, color: Color,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                Text(title).font(.system(size: 21, weight: .bold))
            }
            .padding(20)
            Divider()
            VStack(alignment: .leading, spacing: 17, content: content)
                .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(0.08)))
    }

    private func settingsRow<Control: View>(_ title: String, _ subtitle: String,
                                             @ViewBuilder control: () -> Control) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                rowLabel(title, subtitle)
                Spacer(minLength: 8)
                control()
            }
            VStack(alignment: .leading, spacing: 12) {
                rowLabel(title, subtitle)
                control()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rowLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
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
                Text("Choose a social app in the sidebar. Use the account menu beside its name to add, switch, or rename accounts. Each added account has its own website login. Home and Inbox show chat previews when the websites expose them; Feeds opens the selected social feed. Use the sidebar plus button to add a platform.")
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


