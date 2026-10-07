import SwiftUI

struct UnifiedNotificationCenterView: View {
    @EnvironmentObject private var store: AppStore
    @State private var filter: NotificationFilter = .all
    @State private var newVIPInput: String = ""
    @State private var showingVIPManager: Bool = false

    enum NotificationFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case vip = "VIP"
        case unread = "Unread"
        var id: String { rawValue }
    }

    private struct UnifiedNotificationItem: Identifiable {
        let id: String
        let accountID: UUID
        let platform: SocialPlatform
        let sender: String
        let text: String
        let time: String?
        let isUnread: Bool
        let isVIP: Bool
    }

    private var notifications: [UnifiedNotificationItem] {
        var items: [UnifiedNotificationItem] = []
        let vips = Set(store.preferences.vipContacts.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })

        for account in store.platformAccounts {
            guard let platform = store.platform(account.platformID),
                  let activity = store.platformActivity[account.id] else { continue }

            // 1. Notification previews
            for (idx, notif) in activity.allNotificationPreviews.enumerated() {
                let sender = notif.title.isEmpty ? platform.name : notif.title
                let isVIP = vips.contains(sender.lowercased())
                items.append(UnifiedNotificationItem(
                    id: "\(account.id)-raw-\(idx)",
                    accountID: account.id,
                    platform: platform,
                    sender: sender,
                    text: notif.text,
                    time: notif.time,
                    isUnread: true,
                    isVIP: isVIP
                ))
            }

            // 2. Unread message previews
            for msg in activity.messages where msg.unread {
                let isVIP = vips.contains(msg.sender.lowercased())
                items.append(UnifiedNotificationItem(
                    id: "\(account.id)-msg-\(msg.id)",
                    accountID: account.id,
                    platform: platform,
                    sender: msg.sender,
                    text: msg.text,
                    time: msg.time,
                    isUnread: true,
                    isVIP: isVIP
                ))
            }
        }

        switch filter {
        case .all:
            return items
        case .vip:
            return items.filter { $0.isVIP }
        case .unread:
            return items.filter { $0.isUnread }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.accent)

                Text("Notifications")
                    .font(.system(size: 14, weight: .semibold))

                if store.totalUnreadCount > 0 {
                    Text("\(store.totalUnreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                }

                Spacer()

                // Focus Mode Quick Toggle
                Button {
                    store.preferences.focusModeEnabled.toggle()
                    store.showToast(store.preferences.focusModeEnabled ? "Focus Mode ON: Distractions muted" : "Focus Mode OFF")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: store.preferences.focusModeEnabled ? "moon.stars.fill" : "moon.stars")
                            .font(.system(size: 11))
                        Text(store.preferences.focusModeEnabled ? "Focus ON" : "Focus")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(store.preferences.focusModeEnabled ? Palette.accent.opacity(0.18) : Palette.hover, in: Capsule())
                    .foregroundStyle(store.preferences.focusModeEnabled ? Palette.accent : Palette.muted)
                }
                .buttonStyle(.plain)
                .help("Toggle Focus Mode (mutes non-work social apps)")

                // VIP Manager Button
                Button {
                    showingVIPManager.toggle()
                } label: {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
                .help("Manage VIP Contacts")
            }
            .padding(14)
            .background(Palette.panel)

            Divider()

            // Filter Tabs
            HStack(spacing: 6) {
                ForEach(NotificationFilter.allCases) { f in
                    let isSelected = (filter == f)
                    Button {
                        filter = f
                    } label: {
                        Text(f.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isSelected ? Palette.accent : Palette.hover, in: Capsule())
                            .foregroundStyle(isSelected ? .white : Palette.muted)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Palette.sidebar)

            Divider()

            // Notification List or Empty State
            if notifications.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: filter == .vip ? "star.slash" : "bell.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 24)

                    Text(filter == .vip ? "No VIP notifications" : "All caught up!")
                        .font(.system(size: 13, weight: .semibold))

                    Text(filter == .vip ? "Add key contacts as VIPs to prioritize their messages." : "You have no unread alerts across connected platforms.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(notifications) { item in
                            notificationRow(item)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 380)
            }

            if showingVIPManager {
                Divider()
                vipManagerDrawer
            }
        }
        .frame(width: 380)
        .background(Palette.panel)
    }

    private func notificationRow(_ item: UnifiedNotificationItem) -> some View {
        Button {
            store.destination = .platform(item.platform.id)
            store.selectAccount(item.accountID)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                PlatformLogo(platform: item.platform, size: 24)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.sender)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        if item.isVIP {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                Text("VIP")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.yellow, in: Capsule())
                        }

                        Spacer()

                        if let time = item.time {
                            Text(time)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.muted)
                        }
                    }

                    Text(item.text)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Button {
                    toggleVIP(name: item.sender)
                } label: {
                    Image(systemName: item.isVIP ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(item.isVIP ? .yellow : Palette.muted)
                }
                .buttonStyle(.plain)
                .help(item.isVIP ? "Remove from VIPs" : "Mark as VIP")
            }
            .padding(10)
            .background(item.isVIP ? Color.yellow.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var vipManagerDrawer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VIP Contacts (Bypass Focus Mode)")
                .font(.system(size: 11.5, weight: .semibold))

            HStack(spacing: 6) {
                TextField("Add name or handle (e.g. John, Boss)...", text: $newVIPInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(6)
                    .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
                    .onSubmit { addVIP() }

                Button("Add") {
                    addVIP()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.yellow)
            }

            if !store.preferences.vipContacts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.preferences.vipContacts, id: \.self) { vip in
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow)
                                Text(vip).font(.system(size: 10.5, weight: .medium))
                                Button {
                                    toggleVIP(name: vip)
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Palette.hover, in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Palette.sidebar)
    }

    private func addVIP() {
        let clean = newVIPInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !store.preferences.vipContacts.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            store.preferences.vipContacts.append(clean)
        }
        newVIPInput = ""
    }

    private func toggleVIP(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = store.preferences.vipContacts.firstIndex(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            store.preferences.vipContacts.remove(at: idx)
        } else {
            store.preferences.vipContacts.append(clean)
        }
    }
}
