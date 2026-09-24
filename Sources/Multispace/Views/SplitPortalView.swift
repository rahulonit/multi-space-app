import SwiftUI

struct SplitPortalView: View {
    @EnvironmentObject private var store: AppStore
    @State private var splitRatio: CGFloat = 0.5
    @State private var isDraggingDivider: Bool = false

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let leftWidth = max(240, min(totalWidth - 240, totalWidth * splitRatio))
            let rightWidth = max(240, totalWidth - leftWidth - 6)

            HStack(spacing: 0) {
                // Left Pane (Primary)
                paneView(for: store.destination, isSplitPane: false)
                    .frame(width: leftWidth, height: geo.size.height)

                // Draggable Split Divider (6px wide with visual grab bar)
                ZStack {
                    Rectangle()
                        .fill(isDraggingDivider ? Palette.accent.opacity(0.5) : Palette.border.opacity(0.8))
                        .frame(width: 6)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isDraggingDivider ? Palette.accent : Palette.muted.opacity(0.5))
                        .frame(width: 2.5, height: 26)
                }
                .frame(width: 6)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isDraggingDivider = true
                            let newRatio = value.location.x / totalWidth
                            splitRatio = max(0.20, min(0.80, newRatio))
                        }
                        .onEnded { _ in
                            isDraggingDivider = false
                        }
                )

                // Right Pane (Secondary)
                VStack(spacing: 0) {
                    secondaryHeader
                    if let secondary = store.splitDestination {
                        paneView(for: secondary, isSplitPane: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyState(
                            symbol: "rectangle.split.2x1",
                            title: "Select an app",
                            subtitle: "Choose an app to display in the secondary pane."
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: rightWidth, height: geo.size.height)
            }
        }
    }

    private var secondaryHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .foregroundStyle(Palette.accent)
                .font(.system(size: 13, weight: .semibold))

            // Platform Switcher
            Menu {
                ForEach(store.socialPlatforms) { platform in
                    Button(platform.name) {
                        store.splitDestination = .platform(platform.id)
                        if case .platform(let primaryID) = store.destination, primaryID == platform.id {
                            store.ensureDifferentSplitAccount(for: platform.id)
                        }
                    }
                }
                Divider()
                Button("Inbox") { store.splitDestination = .inbox }
                Button("Browser") { store.splitDestination = .browser }
            } label: {
                HStack(spacing: 4) {
                    Text(title(for: store.splitDestination))
                        .font(.system(size: 12, weight: .bold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.muted)
                }
            }
            .menuStyle(.borderlessButton)

            // Account Switcher for Split Pane
            if case .platform(let platformID) = store.splitDestination,
               let currentSplitAcc = store.splitAccount(for: platformID) {
                Text("•")
                    .foregroundStyle(Palette.muted.opacity(0.5))

                Menu {
                    ForEach(store.accounts(for: platformID)) { acc in
                        Button {
                            store.selectSplitAccount(acc.id)
                        } label: {
                            if acc.id == currentSplitAcc.id {
                                Label(acc.name, systemImage: "checkmark")
                            } else {
                                Text(acc.name)
                            }
                        }
                    }
                    Divider()
                    Button("Add account…", systemImage: "plus") {
                        if let newAcc = store.addAccount(to: platformID, name: "", selectAsPrimary: false) {
                            store.selectSplitAccount(newAcc.id)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 11))
                        Text(currentSplitAcc.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Palette.card, in: Capsule())
                }
                .menuStyle(.borderlessButton)

                // If same platform as primary pane, display a prominent badge
                if case .platform(let primaryID) = store.destination, primaryID == platformID {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 6, height: 6)
                        Text("2nd Account")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Palette.accent.opacity(0.12), in: Capsule())
                }
            }

            // Quick ratio presets
            HStack(spacing: 4) {
                Button("1:2") { withAnimation(.easeInOut(duration: 0.2)) { splitRatio = 0.33 } }
                    .font(.system(size: 9.5, weight: abs(splitRatio - 0.33) < 0.05 ? .bold : .regular))
                    .foregroundStyle(abs(splitRatio - 0.33) < 0.05 ? Palette.accent : Palette.muted)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(abs(splitRatio - 0.33) < 0.05 ? Palette.accent.opacity(0.12) : Palette.hover, in: RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)

                Button("1:1") { withAnimation(.easeInOut(duration: 0.2)) { splitRatio = 0.50 } }
                    .font(.system(size: 9.5, weight: abs(splitRatio - 0.50) < 0.05 ? .bold : .regular))
                    .foregroundStyle(abs(splitRatio - 0.50) < 0.05 ? Palette.accent : Palette.muted)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(abs(splitRatio - 0.50) < 0.05 ? Palette.accent.opacity(0.12) : Palette.hover, in: RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)

                Button("2:1") { withAnimation(.easeInOut(duration: 0.2)) { splitRatio = 0.67 } }
                    .font(.system(size: 9.5, weight: abs(splitRatio - 0.67) < 0.05 ? .bold : .regular))
                    .foregroundStyle(abs(splitRatio - 0.67) < 0.05 ? Palette.accent : Palette.muted)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(abs(splitRatio - 0.67) < 0.05 ? Palette.accent.opacity(0.12) : Palette.hover, in: RoundedRectangle(cornerRadius: 4))
                    .buttonStyle(.plain)
            }

            Spacer()

            Button {
                let primary = store.destination
                if let sec = store.splitDestination {
                    store.destination = sec
                    store.splitDestination = primary
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 22, height: 22)
                    .background(Palette.panel, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Swap primary and secondary panes")

            Button {
                store.closeSplitView()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 22, height: 22)
                    .background(Palette.panel, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close split pane")
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Palette.sidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func paneView(for destination: AppDestination?, isSplitPane: Bool) -> some View {
        switch destination {
        case .home: HomeView()
        case .inbox: IntelligenceInboxView()
        case .browser: BrowserView()
        case .platform(let id):
            if isSplitPane {
                PlatformPortalView(
                    platformID: id,
                    explicitAccountID: store.splitAccount(for: id)?.id,
                    onSelectAccount: { accountID in
                        store.selectSplitAccount(accountID)
                    }
                )
                .id("split-\(id)-\(store.splitAccount(for: id)?.id.uuidString ?? "")")
            } else {
                PlatformPortalView(
                    platformID: id,
                    explicitAccountID: store.selectedAccount(for: id)?.id,
                    onSelectAccount: { accountID in
                        store.selectAccount(accountID, navigate: false)
                    }
                )
                .id("primary-\(id)-\(store.selectedAccount(for: id)?.id.uuidString ?? "")")
            }
        case .settings, .profile, .channel, .conversation: SettingsView()
        case nil:
            EmptyState(symbol: "rectangle.split.2x1", title: "Select an app", subtitle: "Choose an app to display in this pane.")
        }
    }

    private func title(for destination: AppDestination?) -> String {
        guard let destination else { return "Choose pane app" }
        switch destination {
        case .home: return "Home"
        case .inbox: return "Inbox"
        case .browser: return "Browser"
        case .platform(let id):
            return store.platform(id)?.name ?? "Platform"
        case .settings: return "Settings"
        default: return "App"
        }
    }
}
