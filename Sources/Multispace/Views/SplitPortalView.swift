import SwiftUI
import AppKit

private enum SplitLayoutMode: String, CaseIterable, Identifiable {
    case columns
    case rows

    var id: String { rawValue }
    var title: String { self == .columns ? "Side by side" : "Top and bottom" }
    var icon: String { self == .columns ? "rectangle.split.2x1" : "rectangle.split.1x2" }
}

private enum SplitPane: String {
    case primary
    case secondary

    var label: String { self == .primary ? "Primary" : "Secondary" }
}

@MainActor
struct SplitPortalView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("split.layout") private var savedLayout = SplitLayoutMode.columns.rawValue
    @AppStorage("split.ratio") private var splitRatio = 0.5

    @State private var activePane: SplitPane = .primary
    @State private var soloPane: SplitPane?
    @State private var isDraggingDivider = false
    @State private var dragStartRatio = 0.5
    @State private var showingBridge = false
    @State private var bridgePrompt = "Compare both panes and summarize the important differences, decisions, and next actions."
    @State private var bridgeResult = ""
    @State private var isBridgeRunning = false

    private var layout: SplitLayoutMode {
        SplitLayoutMode(rawValue: savedLayout) ?? .columns
    }

    var body: some View {
        VStack(spacing: 0) {
            splitToolbar
            Rectangle().fill(Palette.border).frame(height: 1)

            GeometryReader { geometry in
                if let soloPane {
                    paneContainer(soloPane, destination: destination(for: soloPane), isSplitPane: soloPane == .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if layout == .columns {
                    columnWorkspace(in: geometry.size)
                } else {
                    rowWorkspace(in: geometry.size)
                }
            }
        }
        .background(Palette.background)
        .sheet(isPresented: $showingBridge) { crossPaneBridgeSheet }
        .background { splitKeyboardShortcuts }
    }

    private func columnWorkspace(in size: CGSize) -> some View {
        let available = max(1, size.width - 6)
        let leftWidth = available * CGFloat(splitRatio)
        return HStack(spacing: 0) {
            paneContainer(.primary, destination: store.destination, isSplitPane: false)
                .frame(width: leftWidth, height: size.height)

            splitDivider(axis: .horizontal, availableLength: available)

            paneContainer(.secondary, destination: store.splitDestination, isSplitPane: true)
                .frame(width: available - leftWidth, height: size.height)
        }
    }

    private func rowWorkspace(in size: CGSize) -> some View {
        let available = max(1, size.height - 6)
        let topHeight = available * CGFloat(splitRatio)
        return VStack(spacing: 0) {
            paneContainer(.primary, destination: store.destination, isSplitPane: false)
                .frame(width: size.width, height: topHeight)

            splitDivider(axis: .vertical, availableLength: available)

            paneContainer(.secondary, destination: store.splitDestination, isSplitPane: true)
                .frame(width: size.width, height: available - topHeight)
        }
    }

    private var splitToolbar: some View {
        HStack(spacing: 8) {
            Label("Split workspace", systemImage: layout.icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.muted)

            Menu {
                ForEach(SplitLayoutMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            savedLayout = mode.rawValue
                            splitRatio = 0.5
                        }
                    } label: {
                        Label(mode.title, systemImage: mode.icon)
                    }
                }
            } label: {
                compactControl(layout.title, icon: "chevron.down")
            }
            .menuStyle(.borderlessButton)

            ratioControls
            Spacer()

            Button {
                bridgeResult = ""
                showingBridge = true
            } label: {
                Label("AI Bridge", systemImage: "sparkles")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .foregroundStyle(Palette.accent)
                    .background(Palette.navActiveBg, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Analyze context from both active panes")

            toolbarIcon("arrow.left.arrow.right", help: "Swap panes · ⌘⌥X", action: swapPanes)
            toolbarIcon("xmark", help: "Close split workspace") { store.closeSplitView() }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(Palette.panel)
    }

    private var ratioControls: some View {
        HStack(spacing: 1) {
            ratioButton("1:2", value: 0.33)
            ratioButton("1:1", value: 0.50)
            ratioButton("2:1", value: 0.67)
        }
        .padding(2)
        .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
    }

    private func ratioButton(_ title: String, value: Double) -> some View {
        let selected = abs(splitRatio - value) < 0.04
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { splitRatio = value }
        } label: {
            Text(title)
                .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Palette.accent : Palette.muted)
                .frame(width: 30, height: 22)
                .background(selected ? Palette.navActiveBg : Color.clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func paneContainer(_ pane: SplitPane, destination: AppDestination?, isSplitPane: Bool) -> some View {
        VStack(spacing: 0) {
            paneHeader(pane, destination: destination)
            Rectangle().fill(Palette.border).frame(height: 1)
            paneView(for: destination, isSplitPane: isSplitPane)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background)
        .overlay(
            Rectangle()
                .stroke(activePane == pane ? Palette.accent.opacity(0.65) : Color.clear, lineWidth: 1.5)
        )
        .simultaneousGesture(TapGesture().onEnded { activePane = pane })
    }

    private func paneHeader(_ pane: SplitPane, destination: AppDestination?) -> some View {
        HStack(spacing: 7) {
            Text(pane.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(activePane == pane ? Palette.accent : Palette.muted)
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(activePane == pane ? Palette.navActiveBg : Palette.sidebar, in: RoundedRectangle(cornerRadius: 5))

            Menu {
                ForEach(store.socialPlatforms) { platform in
                    Button(platform.name) { setDestination(.platform(platform.id), for: pane) }
                }
                Divider()
                Button("Browser") { setDestination(.browser, for: pane) }
                Button("Overview") { setDestination(.home, for: pane) }
            } label: {
                HStack(spacing: 4) {
                    Text(title(for: destination))
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
            }
            .menuStyle(.borderlessButton)

            if case .platform(let platformID) = destination,
               let account = account(for: pane, platformID: platformID) {
                Menu {
                    ForEach(store.accounts(for: platformID)) { candidate in
                        Button {
                            selectAccount(candidate.id, platformID: platformID, pane: pane)
                        } label: {
                            if candidate.id == account.id {
                                Label(candidate.name, systemImage: "checkmark")
                            } else {
                                Text(candidate.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                        Text(account.name).lineLimit(1)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 7)
                    .frame(height: 23)
                    .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
            }

            Spacer(minLength: 4)

            if case .platform(let platformID) = destination,
               let account = account(for: pane, platformID: platformID) {
                let muted = store.isSessionMuted(accountID: account.id)
                paneIcon(muted ? "speaker.slash.fill" : "speaker.wave.2", active: muted, help: muted ? "Unmute this pane" : "Mute this pane") {
                    store.toggleSessionMute(accountID: account.id)
                }
            }

            paneIcon(soloPane == pane ? "rectangle.compress.vertical" : "arrow.up.left.and.arrow.down.right", active: soloPane == pane, help: soloPane == pane ? "Restore split" : "Focus this pane") {
                toggleSolo(pane)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(Palette.panel)
        .contentShape(Rectangle())
        .onTapGesture { activePane = pane }
        .onTapGesture(count: 2) { toggleSolo(pane) }
    }

    private func splitDivider(axis: Axis, availableLength: CGFloat) -> some View {
        let horizontalDrag = axis == .horizontal
        return ZStack {
            Rectangle().fill(isDraggingDivider ? Palette.accent.opacity(0.22) : Palette.border)
            RoundedRectangle(cornerRadius: 1)
                .fill(isDraggingDivider ? Palette.accent : Palette.muted.opacity(0.45))
                .frame(width: horizontalDrag ? 2 : 26, height: horizontalDrag ? 26 : 2)
        }
        .frame(width: horizontalDrag ? 6 : nil, height: horizontalDrag ? nil : 6)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                (horizontalDrag ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.18)) { splitRatio = 0.5 }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if !isDraggingDivider {
                        dragStartRatio = splitRatio
                        isDraggingDivider = true
                    }
                    let delta = horizontalDrag ? value.translation.width : value.translation.height
                    let minimumLength: CGFloat = horizontalDrag ? 260 : 170
                    let minimumRatio = min(0.42, max(0.18, minimumLength / max(availableLength, 1)))
                    splitRatio = max(
                        Double(minimumRatio),
                        min(Double(1 - minimumRatio), dragStartRatio + Double(delta / max(availableLength, 1)))
                    )
                }
                .onEnded { _ in isDraggingDivider = false }
        )
    }

    private var splitKeyboardShortcuts: some View {
        Group {
            Button("Swap panes", action: swapPanes)
                .keyboardShortcut("x", modifiers: [.command, .option])
            Button("Focus primary") { activePane = .primary }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Focus secondary") { activePane = .secondary }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Toggle focused pane") { toggleSolo(activePane) }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Restore split") { soloPane = nil }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var crossPaneBridgeSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Cross-pane AI Bridge", systemImage: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Compare recent indexed context from both active panes.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Done") { showingBridge = false }
                    .buttonStyle(.bordered)
            }

            TextEditor(text: $bridgePrompt)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 76)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))

            HStack {
                Text("Only indexed message previews are sent to the selected AI provider.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Button(action: runCrossPaneBridge) {
                    if isBridgeRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Analyze both panes", systemImage: "arrow.triangle.branch")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .disabled(isBridgeRunning || bridgePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !bridgeResult.isEmpty {
                ScrollView {
                    Text(markdownText(bridgeResult))
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))

                HStack {
                    Spacer()
                    Button("Copy result") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bridgeResult, forType: .string)
                        store.showToast("Cross-pane result copied")
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                EmptyState(
                    symbol: "arrow.left.arrow.right",
                    title: "Bridge two work streams",
                    subtitle: "Ask for a comparison, consolidated summary, or client-ready status draft."
                )
            }
        }
        .padding(20)
        .frame(width: 620, height: 500)
        .background(Palette.background)
    }

    private func runCrossPaneBridge() {
        let messages = scopedMessages(for: .primary) + scopedMessages(for: .secondary)
        guard !messages.isEmpty else {
            bridgeResult = "No indexed conversation messages are available in either pane yet."
            return
        }

        let cleanPrompt = bridgePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        isBridgeRunning = true
        Task { @MainActor in
            let analysis = ChatIntelligenceService.shared.analyze(conversationID: "split-workspace", messages: messages)
            let response = await ChatIntelligenceService.shared.answer(
                question: cleanPrompt,
                analysis: analysis,
                messages: messages,
                members: nil,
                preferences: store.preferences,
                conversationTitle: "Split workspace"
            )
            bridgeResult = response.text
            isBridgeRunning = false
        }
    }

    private func scopedMessages(for pane: SplitPane) -> [PlatformMessagePreview] {
        guard case .platform(let platformID) = destination(for: pane),
              let account = account(for: pane, platformID: platformID),
              let snapshot = store.platformActivity[account.id] else { return [] }

        return snapshot.messages.suffix(35).map { message in
            PlatformMessagePreview(
                id: "\(pane.rawValue)-\(message.id)",
                sender: "\(pane.label) · \(message.sender)",
                text: message.text,
                time: message.time,
                linkURL: message.linkURL,
                isUnread: message.isUnread
            )
        }
    }

    private func destination(for pane: SplitPane) -> AppDestination? {
        pane == .primary ? store.destination : store.splitDestination
    }

    private func setDestination(_ destination: AppDestination, for pane: SplitPane) {
        activePane = pane
        if pane == .primary {
            store.destination = destination
        } else {
            store.splitDestination = destination
            if case .platform(let platformID) = destination,
               case .platform(let primaryID) = store.destination,
               primaryID == platformID {
                store.ensureDifferentSplitAccount(for: platformID)
            }
        }
    }

    private func account(for pane: SplitPane, platformID: String) -> PlatformAccount? {
        pane == .primary ? store.selectedAccount(for: platformID) : store.splitAccount(for: platformID)
    }

    private func selectAccount(_ accountID: UUID, platformID: String, pane: SplitPane) {
        activePane = pane
        if pane == .primary {
            store.selectAccount(accountID, navigate: false)
        } else {
            store.selectSplitAccount(accountID)
        }
    }

    private func toggleSolo(_ pane: SplitPane) {
        activePane = pane
        withAnimation(.easeInOut(duration: 0.18)) {
            soloPane = soloPane == pane ? nil : pane
        }
    }

    private func swapPanes() {
        let primary = store.destination
        guard let secondary = store.splitDestination else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            store.destination = secondary
            store.splitDestination = primary
            activePane = activePane == .primary ? .secondary : .primary
        }
    }

    @ViewBuilder
    private func paneView(for destination: AppDestination?, isSplitPane: Bool) -> some View {
        switch destination {
        case .home: HomeView()
        case .browser: BrowserView()
        case .platform(let id):
            if isSplitPane {
                PlatformPortalView(
                    platformID: id,
                    explicitAccountID: store.splitAccount(for: id)?.id,
                    onSelectAccount: { store.selectSplitAccount($0) }
                )
                .id("split-\(id)-\(store.splitAccount(for: id)?.id.uuidString ?? "")")
            } else {
                PlatformPortalView(
                    platformID: id,
                    explicitAccountID: store.selectedAccount(for: id)?.id,
                    onSelectAccount: { store.selectAccount($0, navigate: false) }
                )
                .id("primary-\(id)-\(store.selectedAccount(for: id)?.id.uuidString ?? "")")
            }
        case .settings, .profile, .channel, .conversation: SettingsView()
        case nil:
            EmptyState(
                symbol: "rectangle.split.2x1",
                title: "Choose a pane app",
                subtitle: "Select a platform, browser, or overview from the pane header."
            )
        }
    }

    private func title(for destination: AppDestination?) -> String {
        guard let destination else { return "Choose app" }
        switch destination {
        case .home: return "Overview"
        case .browser: return "Browser"
        case .platform(let id): return store.platform(id)?.name ?? "Platform"
        case .settings: return "Settings"
        case .profile: return "Profile"
        default: return "Workspace"
        }
    }

    private func compactControl(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: icon).font(.system(size: 8, weight: .semibold))
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Palette.muted)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border))
    }

    private func toolbarIcon(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 26, height: 26)
                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func paneIcon(_ icon: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(active ? Palette.accent : Palette.muted)
                .frame(width: 24, height: 24)
                .background(active ? Palette.navActiveBg : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func markdownText(_ value: String) -> AttributedString {
        (try? AttributedString(markdown: value)) ?? AttributedString(value)
    }
}
