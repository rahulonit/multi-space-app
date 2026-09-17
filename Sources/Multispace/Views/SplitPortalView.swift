import SwiftUI

struct SplitPortalView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            // Left Pane (Primary)
            paneView(for: store.destination, isSplitPane: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Split Divider
            Rectangle()
                .fill(.primary.opacity(0.15))
                .frame(width: 1)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            Spacer()

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
        case .inbox: InboxView()
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
        case .platform(let id):
            return store.platform(id)?.name ?? "Platform"
        case .settings: return "Settings"
        default: return "App"
        }
    }
}
