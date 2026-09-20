import SwiftUI
import AppKit

enum HeaderNavTab: String, CaseIterable, Identifiable {
    case platform = "Platform"
    case overview = "Overview"
    case inbox = "Inbox"
    case browser = "Browser"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .platform: return "square.stack.3d.up.fill"
        case .overview: return "square.grid.2x2.fill"
        case .inbox: return "bubble.left.and.bubble.right.fill"
        case .browser: return "globe.americas.fill"
        }
    }
}

struct GlobalHeaderView: View {
    @EnvironmentObject private var store: AppStore
    let windowWidth: CGFloat
    @State private var showingSecurityPopover = false

    private var usesCompactHeaderControls: Bool { windowWidth < 1100 }

    private var activeTab: HeaderNavTab {
        switch store.destination {
        case .browser:
            return .browser
        case .inbox:
            return .inbox
        case .home:
            return .overview
        case .platform, .channel, .conversation:
            return .platform
        case .profile, .settings:
            return .overview
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Brand Area: 220–260 px (Pinggo logo + name)
            brandArea
                .frame(width: usesCompactHeaderControls ? 44 : 220, alignment: .leading)

            if windowWidth > 1200 {
                // Centered Navigation Pill layout
                Spacer()
                rightControls
            } else if windowWidth >= 768 {
                // Navigation pill inline
                primaryNavigationPill
                Spacer()
                rightControls
            } else {
                // Compact mobile header (< 768px): navigation moves to bottom bar
                Spacer()
                rightControls
            }
        }
        .overlay {
            if windowWidth > 1200 {
                primaryNavigationPill
            }
        }
        .padding(.leading, 76) // Space for macOS window controls (close, minimize, zoom)
        .padding(.trailing, 22)
        .frame(height: 64)
        .background(Palette.panel)
    }

    // MARK: - Brand Area (220–260 px)
    private var brandArea: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                store.destination = .home
            }
        } label: {
            HStack(spacing: 10) {
                AppLogo(size: 32)
                Text("Pinggo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .opacity(usesCompactHeaderControls ? 0 : 1)
                    .frame(width: usesCompactHeaderControls ? 0 : nil)
            }
        }
        .buttonStyle(.plain)
        .help("Go to Overview")
    }

    // MARK: - Primary Navigation (Segmented Pill)
    private var primaryNavigationPill: some View {
        HStack(spacing: 4) {
            ForEach(HeaderNavTab.allCases) { tab in
                let isActive = (activeTab == tab)
                Button {
                    selectTab(tab)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        if tab == .inbox && store.totalUnreadCount > 0 {
                            Text("\(store.totalUnreadCount)")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(isActive ? Palette.navActiveText : .white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(isActive ? Color.black.opacity(0.18) : Color.red, in: Capsule())
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(isActive ? Palette.navActiveBg : Color.clear, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(isActive ? Palette.navActiveText : Palette.navInactiveText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(height: 40)
        .background(Palette.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Palette.border, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private func selectTab(_ tab: HeaderNavTab) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            switch tab {
            case .platform:
                if store.isSplitView {
                    // Already in multi-task split view
                } else if case .platform = store.destination {
                    // Already inside platform
                } else {
                    let lastID = UserDefaults.standard.string(forKey: "lastPlatformID")
                    let targetID = lastID ?? store.socialPlatforms.first?.id ?? "whatsapp"
                    store.destination = .platform(targetID)
                }
            case .overview:
                store.destination = .home
            case .inbox:
                store.destination = .inbox
            case .browser:
                store.destination = .browser
            }
        }
    }

    // MARK: - Right Controls
    private var rightControls: some View {
        HStack(spacing: 10) {
            // Security Status (80–100 px)
            if !usesCompactHeaderControls {
                securityPill
            }

            // Search (220–280 px on desktop, icon on compact)
            if windowWidth > 1200 {
                searchBar
                    .frame(width: 240)
            } else {
                searchIconButton
            }

            // Notifications (40 px)
            notificationsButton

            // Profile Avatar (40–44 px)
            profileButton
        }
    }

    // MARK: - Security Status (80–100 px)
    private var securityPill: some View {
        Button {
            showingSecurityPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.green)
                Text("SECURE")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Color.green)
            }
            .padding(.horizontal, 10)
            .frame(width: 90, height: 32)
            .background(Color.green.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.green.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Security & Privacy Shield")
        .popover(isPresented: $showingSecurityPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Security Shield Active")
                            .font(.system(size: 13, weight: .bold))
                        Text("All sessions protected and isolated")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    securityFeatureRow(icon: "lock.fill", title: "End-to-End Encryption", subtitle: "Platform credentials encrypted in Apple Keychain")
                    securityFeatureRow(icon: "eye.slash.fill", title: "Stealth Mode Available", subtitle: "Read messages without triggering read receipts or blue checkmarks")
                    securityFeatureRow(icon: store.preferences.appLockEnabled ? "touchid" : "lock.open", title: "App Lock Protection", subtitle: store.preferences.appLockEnabled ? "Biometric & Master PIN active" : "Disabled (Enable in Settings)")
                    securityFeatureRow(icon: "memorychip", title: "Isolated Sandboxes", subtitle: "Per-platform web partitions and storage isolation")
                }
            }
            .padding(16)
            .frame(width: 320)
        }
    }

    private func securityFeatureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Search Bar (220–280 px)
    private var searchBar: some View {
        Button {
            store.showingCommandPalette = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Text("Search messages…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text("⌘K")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Palette.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Search messages, spaces, and commands (⌘K)")
    }

    // MARK: - Search Icon Button (40 px)
    private var searchIconButton: some View {
        Button {
            store.showingCommandPalette = true
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(Palette.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Search (⌘K)")
    }

    // MARK: - Notifications Button (40 px)
    private var notificationsButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                store.destination = .inbox
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(width: 40, height: 40)
                    .background(Palette.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Palette.border, lineWidth: 1)
                    )

                if store.totalUnreadCount > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Notifications & Inbox (\(store.totalUnreadCount) unread)")
    }

    // MARK: - Profile Avatar Button (40–44 px)
    private var profileButton: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                store.destination = .profile
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Palette.accent, Palette.accent.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)

                Text(profileInitial)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .help("User Profile & Settings")
    }

    private var profileInitial: String {
        let name = store.userProfile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = name.first {
            return String(first).uppercased()
        }
        return "P"
    }
}

// MARK: - Mobile Bottom Nav View (< 768px)
struct MobileBottomNavView: View {
    @EnvironmentObject private var store: AppStore

    private var activeTab: HeaderNavTab {
        switch store.destination {
        case .browser: return .browser
        case .inbox: return .inbox
        case .home: return .overview
        default: return .platform
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(HeaderNavTab.allCases) { tab in
                let isActive = (activeTab == tab)
                Button {
                    selectTab(tab)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if tab == .inbox && store.totalUnreadCount > 0 {
                            Text("\(store.totalUnreadCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(isActive ? Palette.navActiveText : .white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(isActive ? Color.black.opacity(0.18) : Color.red, in: Capsule())
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(isActive ? Palette.navActiveBg : Color.clear, in: RoundedRectangle(cornerRadius: 18))
                    .foregroundStyle(isActive ? Palette.navActiveText : Palette.navInactiveText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Palette.panel)
    }

    private func selectTab(_ tab: HeaderNavTab) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            switch tab {
            case .platform:
                let lastID = UserDefaults.standard.string(forKey: "lastPlatformID")
                let targetID = lastID ?? store.socialPlatforms.first?.id ?? "whatsapp"
                store.destination = .platform(targetID)
            case .overview:
                store.destination = .home
            case .inbox:
                store.destination = .inbox
            case .browser:
                store.destination = .browser
            }
        }
    }
}
