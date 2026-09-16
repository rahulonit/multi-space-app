import SwiftUI

private enum SettingsPage: String, CaseIterable {
    case general = "General", security = "Security", launch = "Performance"
    case interaction = "Interaction", subscription = "Subscription", about = "About"

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .security: "lock.shield.fill"
        case .launch: "bolt.fill"
        case .interaction: "cursorarrow.click.2"
        case .subscription: "crown.fill"
        case .about: "info.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .general: .cyan
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
    @State private var page: SettingsPage = .general
    @State private var detail: String?
    @State private var hibernatedFeedback = false

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
                        case .general: generalPage
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
        .sheet(item: Binding(
            get: { detail.map(DetailSheet.init) },
            set: { detail = $0?.id }
        )) { item in
            detailSheet(item.id)
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { store.destination = .home } label: {
                Label("Back to Multispace", systemImage: "chevron.left")
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
                settingsRow("Open To", "Default view when Multispace opens.") {
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
                settingsRow("Touch ID & Password Lock", "Require biometric or system password authentication to open Multispace.") {
                    Toggle("App Lock", isOn: $store.preferences.appLockEnabled)
                        .labelsHidden()
                        .tint(Palette.accent)
                }
                if store.preferences.appLockEnabled {
                    Divider()
                    settingsRow("Auto-Lock", "Automatically lock after inactivity or when the display sleeps.") {
                        Picker("Auto-Lock", selection: $store.preferences.autoLockMinutes) {
                            Text("Immediately").tag(0)
                            Text("After 5 minutes").tag(5)
                            Text("After 15 minutes").tag(15)
                            Text("After 30 minutes").tag(30)
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    Divider()
                    settingsRow("Lock Immediately", "Lock Multispace now. You can also press ⌘L anywhere.") {
                        Button("Lock Now") {
                            store.lockApp()
                        }
                        .buttonStyle(.bordered)
                    }
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
                settingsRow("Websites Check", "Check your connected accounts when Multispace opens.") {
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
                settingsRow("Purchase Status", "Multispace is currently a local prototype.") {
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
                Text("Multispace")
                    .font(.system(size: 22, weight: .bold))
                Text("All your social apps, in one native macOS workspace")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)

            settingsCard("App Info", symbol: "info.circle.fill", color: .blue) {
                settingsRow("Version", "Multispace") {
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
                Text("Your platform sessions are stored by WebKit on this Mac. Chat previews and website alerts shown on Home stay in memory and clear when Multispace quits. Your local profile, chats, and posts are saved in Application Support. Multispace does not read passwords.")
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
