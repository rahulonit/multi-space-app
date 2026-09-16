import SwiftUI

struct SplitPortalView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            // Left Pane (Primary)
            paneView(for: store.destination)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Split Divider
            Rectangle()
                .fill(.primary.opacity(0.15))
                .frame(width: 1)

            // Right Pane (Secondary)
            VStack(spacing: 0) {
                secondaryHeader
                if let secondary = store.splitDestination {
                    paneView(for: secondary)
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
        HStack(spacing: 10) {
            Image(systemName: "rectangle.split.2x1")
                .foregroundStyle(Palette.accent)
                .font(.system(size: 13, weight: .semibold))

            Menu {
                ForEach(store.socialPlatforms) { platform in
                    Button(platform.name) {
                        store.splitDestination = .platform(platform.id)
                    }
                }
                Divider()
                Button("Feed") { store.splitDestination = .feed }
                Button("Inbox") { store.splitDestination = .inbox }
            } label: {
                HStack(spacing: 4) {
                    Text(title(for: store.splitDestination))
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.muted)
                }
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Button {
                store.closeSplitView()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .background(Palette.panel, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close split pane")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Palette.sidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func paneView(for destination: AppDestination?) -> some View {
        switch destination {
        case .home: HomeView()
        case .feed: FeedView()
        case .inbox: InboxView()
        case .platform(let id): PlatformPortalView(platformID: id)
        case .settings, .profile, .channel, .conversation: SettingsView()
        case nil:
            EmptyState(symbol: "rectangle.split.2x1", title: "Select an app", subtitle: "Choose an app to display in this pane.")
        }
    }

    private func title(for destination: AppDestination?) -> String {
        guard let destination else { return "Choose pane app" }
        switch destination {
        case .home: return "Home"
        case .feed: return "Feed"
        case .inbox: return "Inbox"
        case .platform(let id):
            return store.platform(id)?.name ?? "Platform"
        case .settings: return "Settings"
        default: return "App"
        }
    }
}
