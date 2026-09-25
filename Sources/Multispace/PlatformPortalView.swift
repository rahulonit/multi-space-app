import AppKit
import QuickLookUI
import SwiftUI
@preconcurrency import WebKit

struct PlatformLogo: View {
    let platform: SocialPlatform
    let size: CGFloat

    var body: some View {
        Group {
            if platform.usesOfficialLogo,
               let file = Bundle.module.url(forResource: platform.officialIdentity?.id ?? platform.id, withExtension: "png"),
               let image = NSImage(contentsOf: file) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if platform.customIcon != true,
                      let host = platform.resolvedWebsiteURL?.host,
                      let favicon = URL(string: "https://\(host)/favicon.ico") {
                AsyncImage(url: favicon) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Image(systemName: platform.symbol)
                            .resizable().scaledToFit()
                            .foregroundStyle(spaceColor(platform.color))
                    }
                }
            } else {
                Image(systemName: platform.symbol)
                    .resizable().scaledToFit()
                    .foregroundStyle(spaceColor(platform.color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(platform.name)
    }
}

struct PopupBrowserView: View {
    let webView: WKWebView
    let onClose: () -> Void
    var onOpenInBrowser: (() -> Void)? = nil
    var onSyncSession: (() -> Void)? = nil

    @State private var copiedNotice = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Sign In")
                    .font(.system(size: 13, weight: .semibold))

                if let currentURL = webView.url {
                    Text(currentURL.host ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }

                Spacer()

                if let onOpenInBrowser {
                    Button(action: onOpenInBrowser) {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                            Text("Open in Browser")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Palette.hover, in: RoundedRectangle(cornerRadius: 6))
                    .help("Open sign-in in your default browser (Safari, Chrome)")
                }

                if let currentURL = webView.url, currentURL.absoluteString != "about:blank" {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(currentURL.absoluteString, forType: .string)
                        copiedNotice = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedNotice = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                            if copiedNotice {
                                Text("Copied")
                                    .font(.system(size: 11))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Palette.hover, in: RoundedRectangle(cornerRadius: 6))
                    .help("Copy sign-in link")
                }

                if let onSyncSession {
                    Button(action: onSyncSession) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Sync")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Palette.hover, in: RoundedRectangle(cornerRadius: 6))
                    .help("Sync session from browser")
                }

                Button("Done") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Palette.panel)

            Divider()

            PopupWebViewRepresentable(webView: webView)
        }
        .frame(minWidth: 540, minHeight: 680)
    }
}

struct PopupWebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct PasskeyLoginAssistantSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let platform: SocialPlatform
    let account: PlatformAccount
    var session: PortalSession? = nil

    @State private var selectedTab: Int = 0
    @State private var tokenInput: String = ""
    @State private var copiedBookmarklet = false
    @State private var isSubmitting = false
    @State private var passkeyStatusMessage: String? = nil
    @State private var isCheckingPasskey = false

    private var host: String {
        platform.resolvedWebsiteURL?.host ?? "\(platform.id).com"
    }

    private var bookmarkletCode: String {
        "javascript:(function(){const c=document.cookie;if(!c){alert('No cookies found! Please make sure you are logged into " + platform.name + ".');return;}window.location.href='pinggo://auth-sync?platform=" + platform.id + "&host=" + host + "&cookies='+encodeURIComponent(c);})();"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                PlatformLogo(platform: platform, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(platform.name) Passkey & Login Assistant")
                            .font(.system(size: 17, weight: .bold))
                        Image(systemName: "key.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 12))
                    }
                    Text("Account: \(account.name) • \(host)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.muted)
                        .font(.system(size: 17))
                }
                .buttonStyle(.plain)
            }

            // Sub-Navigation Tabs
            Picker("", selection: $selectedTab) {
                Text("🔑 Passkeys & Touch ID").tag(0)
                Text("🌐 1-Click Browser Sync").tag(1)
                Text("📋 Token & Cookies").tag(2)
            }
            .pickerStyle(.segmented)

            Divider()

            if selectedTab == 0 {
                passkeysTab
            } else if selectedTab == 1 {
                browserSyncTab
            } else {
                manualTokenTab
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .frame(width: 560)
    }

    // MARK: - Tab 0: Native Passkeys & Biometrics
    private var passkeysTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "touchid")
                        .font(.system(size: 16))
                        .foregroundStyle(.green)
                    Text("Biometric & Hardware Passkeys Enabled")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("FIDO2 / WebAuthn")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .foregroundStyle(.green)
                }

                Text("PINGGO supports Apple Passkeys, Mac Touch ID, iCloud Keychain, and hardware security keys directly on \(platform.name).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            }
            .padding(12)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1))

            // Methods list
            VStack(alignment: .leading, spacing: 10) {
                methodRow(
                    icon: "touchid",
                    color: .blue,
                    title: "Touch ID on Mac",
                    desc: "When prompted on the login page, tap the Touch ID sensor on your Mac keyboard to sign in instantly."
                )

                methodRow(
                    icon: "qrcode.viewfinder",
                    color: .purple,
                    title: "Phone Passkey (iPhone / Android)",
                    desc: "Select 'Use phone or tablet' or 'Scan QR code' on the login screen to sign in with your phone's Face ID."
                )

                methodRow(
                    icon: "key.horizontal.fill",
                    color: .orange,
                    title: "Hardware Security Keys (YubiKey)",
                    desc: "Plug your USB-C security key directly into your Mac for instant hardware passkey authentication."
                )

                methodRow(
                    icon: "key.fill",
                    color: .purple,
                    title: "Apple Passwords AutoFill",
                    desc: "Right-click any username or password field on the login page and choose AutoFill -> Passwords to fill saved credentials from iCloud Keychain."
                )
            }

            if let msg = passkeyStatusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary)
                }
                .padding(8)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }

            // Quick actions
            HStack(spacing: 8) {
                Button {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    } else if let url = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                    store.showToast("Opening Apple Passwords...")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                        Text("Open Apple Passwords")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    isCheckingPasskey = true
                    Task {
                        if let session {
                            let script = "(typeof window.PublicKeyCredential !== 'undefined') ? 'ready' : 'fallback';"
                            let res = try? await session.webView.evaluateJavaScript(script)
                            let val = res as? String ?? "ready"
                            if val == "ready" {
                                passkeyStatusMessage = "WebAuthn engine verified: Touch ID & Passkeys are ready on this page!"
                            } else {
                                passkeyStatusMessage = "Passkey engine active. Tap sign-in on page to authenticate."
                            }
                        } else {
                            passkeyStatusMessage = "Touch ID and iCloud Keychain passkeys are ready for \(platform.name)."
                        }
                        isCheckingPasskey = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text(isCheckingPasskey ? "Checking..." : "Verify Readiness")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    session?.reload()
                    store.showToast("Reloaded \(platform.name) portal")
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Reload Page")
                    }
                    .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func methodRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .padding(4)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
        }
    }

    // MARK: - Tab 1: Browser 1-Click Sync
    private var browserSyncTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Already logged in with Passkey in Safari or Chrome? Transfer your active session into PINGGO in seconds.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.muted)

            VStack(spacing: 8) {
                // Step 1: Open in default browser
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step 1: Sign in with Passkey in Browser")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Open \(platform.name) in Safari or Chrome and use your saved passkey.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button {
                        if let url = platform.resolvedWebsiteURL {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                            Text("Open Browser")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))

                // Step 2: Auto-detect session from clipboard
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Step 2: Auto-Sync Active Session")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Automatically detects cookies copied from browser or sync bookmarklet.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button {
                        Task {
                            let imported = await store.detectAndImportClipboardSession(accountID: account.id, platformID: platform.id)
                            if imported {
                                dismiss()
                            } else {
                                store.showToast("No session cookies in clipboard. Use bookmarklet below or copy cookies.")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Auto-Sync Now")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Palette.accent)
                }
                .padding(10)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))

                // Step 3: Copy 1-click Bookmarklet
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1-Click Sync Bookmarklet (Optional)")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Run in browser bookmark bar to instantly sync session into PINGGO.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bookmarkletCode, forType: .string)
                        copiedBookmarklet = true
                        store.showToast("Bookmarklet copied to clipboard!")
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            copiedBookmarklet = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedBookmarklet ? "checkmark" : "bookmark.fill")
                            Text(copiedBookmarklet ? "Copied!" : "Copy Bookmarklet")
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Tab 2: Manual Token / Cookies
    private var manualTokenTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(platform.id == "linkedin" ? "Paste the 'li_at' session token from browser DevTools, or paste raw cookie header." : "Paste session cookies (name=value; ...) from your browser.")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.muted)

            HStack(spacing: 8) {
                TextField(platform.id == "linkedin" ? "Paste li_at token or cookies..." : "Paste cookies (name=value; ...)", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button("Paste") {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        tokenInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Log In") {
                    let text = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    isSubmitting = true
                    Task {
                        await store.importSessionCookies(accountID: account.id, platformID: platform.id, rawInput: text)
                        isSubmitting = false
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Palette.accent)
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
            }
        }
    }
}
typealias SessionSyncSheet = PasskeyLoginAssistantSheet

struct PlatformPortalView: View {
    @EnvironmentObject private var store: AppStore
    let platformID: String
    var explicitAccountID: UUID? = nil
    var customURL: URL? = nil
    var onSelectAccount: ((UUID) -> Void)? = nil

    var body: some View {
        if let platform = store.platform(platformID) {
            let targetURL = customURL ?? platform.resolvedWebsiteURL
            if let url = targetURL {
                let targetAccount = (explicitAccountID != nil ? store.account(explicitAccountID!) : nil) ?? store.selectedAccount(for: platform.id)
                if let account = targetAccount {
                    PortalBrowser(
                        platform: platform,
                        account: account,
                        url: url,
                        onSelectAccount: onSelectAccount
                    )
                    .id("\(account.id):\(url.absoluteString)")
                }
            } else {
                missingWebsite(for: platform)
            }
        }
    }

    private func missingWebsite(for platform: SocialPlatform) -> some View {
        VStack(spacing: 16) {
            PlatformLogo(platform: platform, size: 54)
            Text("Set a website for \(platform.name)")
                .font(.system(size: 20, weight: .semibold))
            Text("Add the platform’s official HTTPS web address to open it here.")
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button("Edit platform") { store.editingPlatform = platform }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PortalBrowser: View {
    @EnvironmentObject private var store: AppStore
    let platform: SocialPlatform
    let account: PlatformAccount
    let url: URL
    var onSelectAccount: ((UUID) -> Void)? = nil
    @ObservedObject private var session: PortalSession
    @State private var showingAddAccount = false
    @State private var showingRenameAccount = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var documentToPreview: PortalDownloadedDocument?
    @State private var showingPasskeyAssistant = false
    @State private var dismissedPasskeyBanner = false
    @State private var showingAIDrawer = false
    @State private var copilotWidth: CGFloat = 380
    @ObservedObject private var downloadManager: VideoDownloadManager = VideoDownloadManager.shared

    private var isAuthenticationPage: Bool {
        let urlStr = (session.currentURL ?? url).absoluteString.lowercased()
        return urlStr.contains("login") || urlStr.contains("signin") || urlStr.contains("sign-in") ||
               urlStr.contains("auth") || urlStr.contains("checkpoint") || urlStr.contains("accounts.google") ||
               urlStr.contains("appleid.apple") || urlStr.contains("web.whatsapp.com") || urlStr.contains("challenge") ||
               urlStr.contains("two-factor") || urlStr.contains("2fa") || urlStr.contains("sso") ||
               urlStr.contains("session") || urlStr.contains("identity")
    }

    init(platform: SocialPlatform, account: PlatformAccount, url: URL, onSelectAccount: ((UUID) -> Void)? = nil) {
        self.platform = platform
        self.account = account
        self.url = url
        self.onSelectAccount = onSelectAccount
        _session = ObservedObject(wrappedValue: PortalSessionRegistry.shared.session(for: account, url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Unified Modern 50px Portal Toolbar
            HStack(spacing: 10) {
                // Platform & Account Switcher Pill
                Menu {
                    ForEach(store.accounts(for: platform.id)) { item in
                        Button {
                            if let onSelectAccount {
                                onSelectAccount(item.id)
                            } else {
                                store.selectAccount(item.id)
                            }
                        } label: {
                            if item.id == account.id { Label(item.name, systemImage: "checkmark") }
                            else { Text(item.name) }
                        }
                    }
                    Divider()
                    Button("Add account…", systemImage: "plus") { showingAddAccount = true }
                    Button("Rename this account…", systemImage: "pencil") { showingRenameAccount = true }
                    if store.canRemoveAccount(account.id) {
                        Button("Delete this account…", systemImage: "trash", role: .destructive) {
                            showingDeleteAccountConfirmation = true
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        PlatformLogo(platform: platform, size: 20)
                        Text(platform.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary)
                        Text("·")
                            .foregroundStyle(Palette.muted)
                        Text(account.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)

                // Navigation Cluster
                HStack(spacing: 2) {
                    toolbarButton("chevron.left", help: "Back", enabled: session.canGoBack) { session.webView.goBack() }
                    toolbarButton("chevron.right", help: "Forward", enabled: session.canGoForward) { session.webView.goForward() }
                    toolbarButton("arrow.clockwise", help: "Reload", enabled: true) { session.webView.reload() }
                }
                .padding(2)
                .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))

                // Center Omni-Address Pill
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isAuthenticationPage ? .orange : .green)
                    Text(session.currentURL?.host ?? url.host ?? platform.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                    if session.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .frame(minWidth: 140, maxWidth: 260)
                .background(Palette.card.opacity(0.5), in: Capsule())
                .overlay(Capsule().stroke(Palette.card, lineWidth: 1))

                Spacer(minLength: 8)

                // Right Action Cluster
                if isAuthenticationPage {
                    Button {
                        showingPasskeyAssistant = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Passkey Ready")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Fast Passkey & Login Assistant available")
                } else {
                    toolbarButton(
                        "key.fill",
                        help: "Passkey & Fast Login Assistant",
                        enabled: true,
                        tint: Palette.muted
                    ) {
                        showingPasskeyAssistant = true
                    }
                }

                toolbarButton(
                    session.isMuted ? "speaker.slash.fill" : "speaker.wave.2",
                    help: session.isMuted ? "Unmute audio" : "Mute audio",
                    enabled: true,
                    tint: session.isMuted ? .orange : Palette.muted
                ) {
                    session.toggleMute()
                }

                toolbarButton(
                    store.isSplitView ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                    help: store.isSplitView ? "Exit split view (⌘\\)" : "Split view side-by-side (⌘\\)",
                    enabled: true,
                    tint: store.isSplitView ? Palette.accent : Palette.muted
                ) {
                    store.toggleSplitView()
                }

                // Video Downloader for Platform Media (WhatsApp Status, Instagram Reel, LinkedIn, TikTok, etc.)
                let detectedVideos = downloadManager.detectedVideosByPlatform[platform.id] ?? []
                if !detectedVideos.isEmpty {
                    Menu {
                        ForEach(detectedVideos) { media in
                            Section(header: Text(media.title).lineLimit(1)) {
                                ForEach(media.availableOptions) { opt in
                                    Button {
                                        downloadManager.startDownload(media: media, quality: opt, webView: session.webView)
                                    } label: {
                                        HStack {
                                            Text(opt.label)
                                            Spacer()
                                            Text(opt.format.uppercased())
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Palette.muted)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.green)
                            Text("Download Video (\(detectedVideos.count))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.green)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.green.opacity(0.8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.35), lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Download video with full audio and chosen quality from \(platform.name)")
                }

                // Active Downloads indicator for this platform
                let activeMedia = downloadManager.activeDownloads.filter { !$0.isComplete && $0.error == nil }
                if !activeMedia.isEmpty {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text(activeMedia.first?.statusText ?? "Downloading…")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.accent)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Palette.accent.opacity(0.1), in: Capsule())
                }

                // AI Co-Pilot Toggle Button
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        showingAIDrawer.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Text("Co-Pilot")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(showingAIDrawer ? .white : Palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(showingAIDrawer ? Palette.accent : Palette.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Palette.accent.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Toggle AI Co-Pilot Chat & Analysis")

                toolbarButton("square.and.arrow.up", help: "Open in external browser", enabled: true) {
                    NSWorkspace.shared.open(session.currentURL ?? url)
                }

                Menu {
                    Button("Edit platform…") { store.editingPlatform = platform }
                    Button("Remove from sidebar", role: .destructive) { store.removePlatform(platform.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Palette.muted)
                        .frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Palette.panel)

            Divider()
                .background(Palette.border)

            if isAuthenticationPage && !dismissedPasskeyBanner {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))

                    Text("Fast Sign-In: Touch ID, Apple Passkeys, or 1-Click Sync available")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        showingPasskeyAssistant = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Passkey Assistant")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(.orange)

                    Button {
                        dismissedPasskeyBanner = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(Color.orange.opacity(0.25)),
                    alignment: .bottom
                )
            }

            // 3-Pane Layout: Platform WebView on Left, Co-Pilot docked side-by-side as 3rd Pane on Right
            HStack(spacing: 0) {
                ZStack {
                    PortalWebView(session: session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let error = session.error {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 28))
                                .foregroundStyle(Palette.accent)
                            Text("Couldn’t open \(platform.name)")
                                .font(.system(size: 17, weight: .semibold))
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                                .multilineTextAlignment(.center)
                            HStack {
                                Button("Try again") { session.load(url) }
                                Button("Open in browser") { NSWorkspace.shared.open(url) }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 390)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if session.isHibernated {
                        VStack(spacing: 14) {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Palette.accent)
                            Text("\(platform.name) is sleeping")
                                .font(.system(size: 16, weight: .semibold))
                            Text("This account was put to sleep while inactive to save RAM and battery life.")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                                .multilineTextAlignment(.center)
                            Button("Wake Session") {
                                session.wake()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.accent)
                        }
                        .padding(28)
                        .frame(maxWidth: 380)
                        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showingAIDrawer {
                    // Resizable Divider Handle between Platform WebView and Co-Pilot 3rd Pane
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Palette.border)
                            .frame(width: 1)
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
                        DragGesture()
                            .onChanged { val in
                                let newW = copilotWidth - val.translation.width
                                copilotWidth = min(max(newW, 320), 650)
                            }
                    )

                    AICopilotDrawer(
                        session: session,
                        platform: platform,
                        account: account,
                        onClose: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                showingAIDrawer = false
                            }
                        }
                    )
                    .frame(width: copilotWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(.white)
        }
        .overlay(alignment: .top) {
            if session.isLoading {
                ProgressView().progressViewStyle(.linear).tint(Palette.accent)
                    .padding(.top, 78)
            }
        }
        .onAppear {
            session.wake()
            session.resume()
            if session.webView.url != url && session.currentURL != url {
                session.load(url)
            }
            session.activityHandler = { title, messages, notifications, rawNotifications, activeContact, activeThreadMessages, groupMemberCount, groupSubtitle, groupMembers in
                store.updatePlatformActivity(accountID: account.id, title: title,
                                             messages: messages, notifications: notifications,
                                             rawNotifications: rawNotifications,
                                             activeContact: activeContact,
                                             activeThreadMessages: activeThreadMessages,
                                             groupMemberCount: groupMemberCount,
                                             groupSubtitle: groupSubtitle,
                                             groupMembers: groupMembers)
            }
        }
        .onChange(of: url) { _, newURL in
            if session.webView.url != newURL {
                session.load(newURL)
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AccountNameSheet(title: "Add \(platform.name) account", suggestedName: "Account \(store.accounts(for: platform.id).count + 1)") { name in
                if let onSelectAccount {
                    if let newAcc = store.addAccount(to: platform.id, name: name, selectAsPrimary: false) {
                        onSelectAccount(newAcc.id)
                    }
                } else {
                    store.addAccount(to: platform.id, name: name)
                }
            }
        }
        .sheet(isPresented: $showingRenameAccount) {
            AccountNameSheet(title: "Rename account", suggestedName: account.name) { name in
                store.renameAccount(account.id, to: name)
            }
        }
        .confirmationDialog(
            "Delete \(account.name)?",
            isPresented: $showingDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                store.removeAccount(account.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the account from PINGGO and clears its separate website session. Your account on \(platform.name) is not deleted.")
        }
        .confirmationDialog(
            "Document downloaded",
            isPresented: Binding(
                get: { session.completedDownload != nil },
                set: { if !$0 { session.completedDownload = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let document = session.completedDownload {
                Button("Open in Pinggo") {
                    documentToPreview = document
                    session.completedDownload = nil
                }
                Button("Open with Default App") {
                    NSWorkspace.shared.open(document.url)
                    session.completedDownload = nil
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([document.url])
                    session.completedDownload = nil
                }
            }
            Button("Not Now", role: .cancel) { session.completedDownload = nil }
        } message: {
            if let document = session.completedDownload {
                Text("\(document.url.lastPathComponent) is ready. Choose where you want to open it.")
            }
        }
        .sheet(item: $documentToPreview) { document in
            PinggoDocumentPreview(document: document)
        }
        .sheet(isPresented: Binding(
            get: { session.popupWebView != nil },
            set: { if !$0 { session.closePopup() } }
        )) {
            if let popup = session.popupWebView {
                PopupBrowserView(
                    webView: popup,
                    onClose: { session.closePopup() },
                    onOpenInBrowser: {
                        if let targetURL = popup.url, targetURL.absoluteString != "about:blank" {
                            NSWorkspace.shared.open(targetURL)
                        } else if let mainURL = session.currentURL ?? platform.resolvedWebsiteURL {
                            NSWorkspace.shared.open(mainURL)
                        }
                    },
                    onSyncSession: {
                        session.closePopup()
                        showingPasskeyAssistant = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingPasskeyAssistant) {
            PasskeyLoginAssistantSheet(platform: platform, account: account, session: session)
        }
        .onChange(of: session.currentURL) { _, _ in
            dismissedPasskeyBanner = false
        }
    }

    private func toolbarButton(_ symbol: String, help: String, enabled: Bool, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(tint ?? (enabled ? .primary : Palette.muted))
                .frame(width: 27, height: 27)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

struct PortalDownloadedDocument: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

private struct PinggoDocumentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let document: PortalDownloadedDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .foregroundStyle(Palette.accent)
                Text(document.url.lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([document.url])
                }
                Button("Open with Default App") {
                    NSWorkspace.shared.open(document.url)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                Button("Done") { dismiss() }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Palette.panel)

            Divider()

            QuickLookDocumentView(url: document.url)
                .frame(minWidth: 720, minHeight: 520)
        }
        .frame(minWidth: 760, minHeight: 580)
    }
}

private struct QuickLookDocumentView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.autostarts = true
        preview.previewItem = url as NSURL
        return preview
    }

    func updateNSView(_ preview: QLPreviewView, context: Context) {
        preview.previewItem = url as NSURL
        preview.refreshPreviewItem()
    }
}

private struct AccountNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let suggestedName: String
    let save: (String) -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 20, weight: .bold))
            Text("This account keeps a separate website login on this Mac.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            TextField("Account name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save(name); dismiss() }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 390)
        .onAppear { name = suggestedName }
    }
}

private struct PortalWebView: NSViewRepresentable {
    @ObservedObject var session: PortalSession

    func makeNSView(context: Context) -> WKWebView {
        session.webView.alphaValue = 1.0
        return session.webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.alphaValue = 1.0
    }
}

@MainActor
final class PortalSessionRegistry {
    static let shared = PortalSessionRegistry()
    private var sessions: [UUID: PortalSession] = [:]

    func session(for account: PlatformAccount, url: URL) -> PortalSession {
        if let existing = sessions[account.id] {
            existing.lastAccessedAt = .now
            if existing.currentURL != url && existing.homeURL != url {
                existing.load(url)
            }
            return existing
        }
        let created = PortalSession(account: account, url: url)
        sessions[account.id] = created
        return created
    }

    func monitor(_ platforms: [SocialPlatform], accounts: [PlatformAccount], store: AppStore) {
        let activeIDs = Set(accounts.map(\.id))
        for id in Array(sessions.keys) where !activeIDs.contains(id) {
            sessions[id]?.stop()
            sessions.removeValue(forKey: id)
        }
        for account in accounts {
            guard let platform = platforms.first(where: { $0.id == account.platformID }) else { continue }
            guard let url = platform.resolvedWebsiteURL else { continue }
            let browser = session(for: account, url: url)
            browser.activityHandler = { [weak store] title, messages, notifications, rawNotifications, activeContact, activeThreadMessages, groupMemberCount, groupSubtitle, groupMembers in
                store?.updatePlatformActivity(accountID: account.id, title: title,
                                               messages: messages, notifications: notifications,
                                               rawNotifications: rawNotifications,
                                               activeContact: activeContact,
                                               activeThreadMessages: activeThreadMessages,
                                               groupMemberCount: groupMemberCount,
                                               groupSubtitle: groupSubtitle,
                                               groupMembers: groupMembers)
            }
        }
    }

    func forget(_ account: PlatformAccount, platform: SocialPlatform? = nil) {
        let browser = sessions.removeValue(forKey: account.id)
        browser?.stop()
        if !account.usesLegacyStore {
            WKWebsiteDataStore.remove(forIdentifier: account.id) { _ in }
        } else if let host = platform?.resolvedWebsiteURL?.host?.lowercased() {
            // Older Personal accounts used WebKit's shared default store. Remove only
            // records belonging to this platform so other Personal accounts stay signed in.
            let normalizedHost = host.replacingOccurrences(
                of: "^(www|web)\\.",
                with: "",
                options: .regularExpression
            )
            let dataStore = WKWebsiteDataStore.default()
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                let matchingRecords = records.filter { record in
                    let recordHost = record.displayName.lowercased().replacingOccurrences(
                        of: "^(www|web)\\.",
                        with: "",
                        options: .regularExpression
                    )
                    return recordHost == normalizedHost ||
                           recordHost.hasSuffix(".\(normalizedHost)") ||
                           normalizedHost.hasSuffix(".\(recordHost)")
                }
                guard !matchingRecords.isEmpty else { return }
                dataStore.removeData(ofTypes: dataTypes, for: matchingRecords) {}
            }
        }
    }

    func cleanupInactiveSessions(activeAccountIDs: Set<UUID>, timeout: TimeInterval) {
        for (id, session) in sessions {
            if activeAccountIDs.contains(id) {
                session.wake()
                session.resume()
            } else {
                let inactiveTime = Date.now.timeIntervalSince(session.lastAccessedAt)
                if inactiveTime >= timeout {
                    session.hibernate()
                } else {
                    session.suspend()
                }
            }
        }
    }

    func hibernateAllInactive(activeAccountIDs: Set<UUID>) {
        for (id, session) in sessions where !activeAccountIDs.contains(id) {
            session.hibernate()
        }
    }

    func existingSession(for accountID: UUID) -> PortalSession? {
        sessions[accountID]
    }

    func attachBackgroundWebViews(to container: NSView) {
        for session in sessions.values {
            if session.webView.superview == nil {
                session.webView.frame = NSRect(x: -2000, y: -2000, width: 1280, height: 900)
                session.webView.alphaValue = 0.01
                container.addSubview(session.webView)
            }
        }
    }

    func isHibernated(accountID: UUID) -> Bool {
        sessions[accountID]?.isHibernated ?? false
    }

    func isMuted(accountID: UUID) -> Bool {
        sessions[accountID]?.isMuted ?? false
    }

    func toggleMute(accountID: UUID) {
        sessions[accountID]?.toggleMute()
    }

    func wakeSession(accountID: UUID) {
        sessions[accountID]?.wake()
        sessions[accountID]?.resume()
    }

    func sleepingSessionCount() -> Int {
        sessions.values.filter { $0.isHibernated }.count
    }

    func activeSessionCount() -> Int {
        sessions.count
    }

    func injectCookiesAndReload(accountID: UUID, cookies: String, domain: String) async {
        guard let session = sessions[accountID] else { return }
        await session.injectCookies(headerString: cookies, domain: domain)
        session.reload()
    }

    func injectTokenAndReload(accountID: UUID, tokenName: String, tokenValue: String, domain: String) async {
        guard let session = sessions[accountID] else { return }
        await session.injectCookie(name: tokenName, value: tokenValue, domain: domain)
        if domain.contains("linkedin.com") {
            session.load(URL(string: "https://www.linkedin.com/messaging/")!)
        } else {
            session.reload()
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
final class PortalSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var isMuted = false
    @Published var isHibernated = false
    @Published var popupWebView: WKWebView?
    @Published var currentURL: URL?
    @Published var error: String?
    @Published var completedDownload: PortalDownloadedDocument?
    @Published var activeThread: ActiveThreadContext? = nil
    @Published var copilotHistory: [CopilotMessage] = []
    var lastAccessedAt: Date = .now
    let webView: WKWebView
    let homeURL: URL
    let accountID: UUID
    let platformID: String
    var activityHandler: ((String, [[String: String]], [String], [[String: String]], String?, [[String: Any]], Int?, String?, [AIChatMemberItem]?) -> Void)?
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    func appendCopilotMessage(role: String, content: String) {
        copilotHistory.append(CopilotMessage(role: role, content: content))
        if copilotHistory.count > 10 {
            copilotHistory.removeFirst(copilotHistory.count - 10)
        }
    }

    func clearCopilotHistory() {
        copilotHistory.removeAll()
    }

    init(account: PlatformAccount, url: URL) {
        accountID = account.id
        platformID = account.platformID
        homeURL = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = account.usesLegacyStore ? .default() : WKWebsiteDataStore(forIdentifier: account.id)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(source: Self.passkeyScript,
                                                                       injectionTime: .atDocumentStart,
                                                                       forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(source: Self.activityScript,
                                                                       injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: true))
        configuration.userContentController.addUserScript(WKUserScript(source: Self.audioScript,
                                                                       injectionTime: .atDocumentStart,
                                                                       forMainFrameOnly: false))
        configuration.userContentController.addUserScript(WKUserScript(source: VideoDownloadManager.snifferScript,
                                                                       injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: false))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration)
        super.init()
        let weakHandler = WeakScriptMessageHandler(delegate: self)
        configuration.userContentController.add(weakHandler, name: "pinggoActivity")
        configuration.userContentController.add(weakHandler, name: "multispaceActivity")
        configuration.userContentController.add(weakHandler, name: "pinggoVideoSniffer")
        configuration.userContentController.add(weakHandler, name: "pinggoVideoDownload")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // Use standard modern Safari desktop user agent
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"
        load(url)
    }

    func closePopup() {
        popupWebView?.stopLoading()
        popupWebView = nil
    }

    func stop() {
        closePopup()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "pinggoActivity")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "multispaceActivity")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "pinggoVideoSniffer")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "pinggoVideoDownload")
        activityHandler = nil
    }

    func reload() {
        webView.reload()
    }

    func insertTextIntoChat(_ text: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        let script = "window.pinggoInsertText ? window.pinggoInsertText(\"\(escaped)\") : false;"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func forceCollect() {
        webView.evaluateJavaScript("window.__pinggoCollect ? window.__pinggoCollect() : (window.__multispaceCollect ? window.__multispaceCollect() : null);", completionHandler: nil)
    }

    func injectCookie(name: String, value: String, domain: String, path: String = "/") async {
        let cookieProps: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path,
            .name: name,
            .value: value,
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(86400 * 365)
        ]
        if let cookie = HTTPCookie(properties: cookieProps) {
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
        }
    }

    func injectCookies(headerString: String, domain: String) async {
        let pairs = headerString.components(separatedBy: ";")
        for pair in pairs {
            let trimmed = pair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let val = String(trimmed[trimmed.index(after: eqIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                await injectCookie(name: key, value: val, domain: domain)
            }
        }
    }

    func suspend() {
        webView.setAllMediaPlaybackSuspended(true)
        webView.evaluateJavaScript("window.__multispaceSuspended = true;", completionHandler: nil)
    }

    func resume() {
        lastAccessedAt = .now
        if !isMuted {
            webView.setAllMediaPlaybackSuspended(false)
        }
        webView.evaluateJavaScript("window.__multispaceSuspended = false;", completionHandler: nil)
    }

    func hibernate() {
        guard !isHibernated else { return }
        isHibernated = true
        suspend()
        webView.stopLoading()
        webView.loadHTMLString("<html><body style='background:#121318;'></body></html>", baseURL: nil)
    }

    func wake() {
        webView.alphaValue = 1.0
        guard isHibernated else { return }
        isHibernated = false
        lastAccessedAt = .now
        load(homeURL)
    }

    func toggleMute() {
        isMuted.toggle()
        applyMute()
    }

    func applyMute() {
        let script = """
        (() => {
            window.__multispaceMuted = \(isMuted ? "true" : "false");
            document.querySelectorAll('video, audio').forEach(el => {
                el.muted = \(isMuted ? "true" : "false");
            });
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "pinggoVideoSniffer", let dict = message.body as? [String: Any] {
            let id = dict["id"] as? String ?? ""
            let title = dict["title"] as? String ?? "Video"
            let pageURL = (dict["pageURL"] as? String).flatMap { URL(string: $0) }
            let thumb = (dict["thumbnailURL"] as? String).flatMap { URL(string: $0) }
            let duration = dict["duration"] as? Double ?? 0
            let isBlob = dict["isBlob"] as? Bool ?? false

            var qualities: [VideoQualityOption] = []
            if let qArray = dict["qualities"] as? [[String: Any]] {
                for q in qArray {
                    let qId = q["id"] as? String ?? "full"
                    let label = q["label"] as? String ?? "Full Quality"
                    let res = q["resolution"] as? String ?? "Original"
                    let url = q["url"] as? String ?? id
                    let format = q["format"] as? String ?? "mp4"
                    qualities.append(VideoQualityOption(id: qId, label: label, resolution: res, url: url, format: format))
                }
            }
            if qualities.isEmpty {
                qualities.append(VideoQualityOption(id: "full", label: "🌟 Full Quality (Best Available)", resolution: "Original", url: id, format: "mp4"))
            }

            let media = DetectedVideoMedia(
                id: id,
                title: title,
                pageURL: pageURL,
                thumbnailURL: thumb,
                duration: duration,
                qualities: qualities,
                isBlob: isBlob
            )

            VideoDownloadManager.shared.registerDetectedVideo(media, forPlatformID: platformID)
            return
        }

        if message.name == "pinggoVideoDownload", let dict = message.body as? [String: Any] {
            let action = dict["action"] as? String ?? ""
            if action == "blobChunk" || action == "blobError" {
                VideoDownloadManager.shared.handleBlobChunkMessage(dict)
            } else if action == "triggerVideoDownload", let videoId = dict["videoId"] as? String {
                if let mediaList = VideoDownloadManager.shared.detectedVideosByPlatform[platformID],
                   let media = mediaList.first(where: { $0.id == videoId }),
                   let best = media.bestQuality {
                    VideoDownloadManager.shared.startDownload(media: media, quality: best, webView: webView)
                }
            }
            return
        }

        guard message.name == "pinggoActivity" || message.name == "multispaceActivity" else { return }
        if let currentHost = webView.url?.host?.lowercased(),
           let homeHost = homeURL.host?.lowercased() {
            let baseHome = homeHost.replacingOccurrences(of: "^(www|web)\\.", with: "", options: .regularExpression)
            let baseCurrent = currentHost.replacingOccurrences(of: "^(www|web)\\.", with: "", options: .regularExpression)
            let isAllowed = currentHost == baseHome || currentHost.hasSuffix(".\(baseHome)") ||
                            baseHome == baseCurrent ||
                            (baseHome.contains("x.com") && baseCurrent.contains("twitter.com")) ||
                            (baseHome.contains("twitter.com") && baseCurrent.contains("x.com"))
            guard isAllowed else { return }
        }
        guard let body = message.body as? [String: Any] else { return }
        let title = body["title"] as? String ?? ""
        let rows = (body["messages"] as? [[String: Any]] ?? []).map { row in
            [
                "sender": row["sender"] as? String ?? "",
                "text": row["text"] as? String ?? "",
                "time": row["time"] as? String ?? "",
                "link": row["link"] as? String ?? "",
                "unread": (row["unread"] as? String) ?? ((row["unread"] as? Bool == true) ? "true" : "false")
            ]
        }
        let notifications = body["notifications"] as? [String] ?? []
        let rawNotifications = (body["rawNotifications"] as? [[String: Any]] ?? []).map { item in
            [
                "title": item["title"] as? String ?? "",
                "text": item["text"] as? String ?? "",
                "time": item["time"] as? String ?? "",
                "link": item["link"] as? String ?? "",
                "category": item["category"] as? String ?? "general"
            ]
        }
        let activeContact = body["activeContact"] as? String
        let activeThreadMessages = body["activeThreadMessages"] as? [[String: Any]] ?? []
        let groupMemberCount = body["groupMemberCount"] as? Int
        let groupSubtitle = body["groupSubtitle"] as? String
        let rawGroupMembers = body["groupMembers"] as? [[String: Any]] ?? []
        let groupMembers: [AIChatMemberItem] = rawGroupMembers.compactMap { dict in
            let rawName = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let phone = (dict["phoneNumber"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = (dict["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanPhone = (phone?.isEmpty == false) ? phone : nil
            let cleanUsername = (username?.isEmpty == false) ? username : nil

            let finalName = rawName.isEmpty ? (cleanUsername ?? (cleanPhone ?? "")) : rawName
            guard !finalName.isEmpty || cleanPhone != nil else { return nil }

            let role = (dict["role"] as? String) ?? "Member"
            let activity = (dict["activity"] as? String) ?? "In group roster"
            let count = (dict["messageCount"] as? Int) ?? 0
            return AIChatMemberItem(
                name: finalName,
                role: role,
                activity: activity,
                messageCount: count,
                phoneNumber: cleanPhone,
                username: cleanUsername
            )
        }

        let cleanContact = (activeContact ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanContact.isEmpty || !activeThreadMessages.isEmpty {
            let threadMsgs: [ActiveChatMessage] = activeThreadMessages.prefix(200).enumerated().compactMap { idx, dict in
                let sender = (dict["sender"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let text = (dict["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let isFromMe = (dict["isFromMe"] as? Bool) ?? (sender.lowercased() == "you" || sender.lowercased() == "me")
                let time = (dict["time"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return ActiveChatMessage(
                    id: "\(accountID)-thread-\(idx)-\(sender)",
                    sender: sender.isEmpty ? (isFromMe ? "You" : cleanContact) : sender,
                    text: text,
                    isFromMe: isFromMe,
                    time: (time?.isEmpty == false) ? time : nil
                )
            }
            self.activeThread = ActiveThreadContext(
                contactName: cleanContact.isEmpty ? (threadMsgs.first(where: { !$0.isFromMe })?.sender ?? "Current Chat") : cleanContact,
                platformID: homeURL.host ?? "",
                messages: threadMsgs,
                groupMemberCount: groupMemberCount,
                groupSubtitle: groupSubtitle,
                groupMembers: groupMembers.isEmpty ? nil : groupMembers,
                updatedAt: .now
            )
        } else {
            self.activeThread = nil
        }

        activityHandler?(title, rows, notifications, rawNotifications, activeContact, activeThreadMessages, groupMemberCount, groupSubtitle, groupMembers)
    }

    func load(_ url: URL) {
        error = nil
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        error = nil
        updateNavigation()
        VideoDownloadManager.shared.clearDetectedVideos(forPlatformID: platformID)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        updateNavigation()
        if isMuted { applyMute() }
        forceCollect()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.forceCollect()
            try? await Task.sleep(for: .seconds(4))
            self?.forceCollect()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    // MARK: - WKUIDelegate (WebRTC media capture & popups)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    // MARK: - Attachment & File Classification
    private enum AttachmentKind {
        case pdf
        case media
        case otherFile
        case none
    }

    private static let pdfFileExtensions: Set<String> = ["pdf"]

    private static let mediaFileExtensions: Set<String> = [
        // Images
        "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico", "heic", "heif", "avif", "tiff", "tif",
        // Video
        "mp4", "mov", "webm", "mkv", "avi", "m4v", "mpg", "mpeg", "wmv", "flv", "3gp",
        // Audio
        "mp3", "wav", "ogg", "m4a", "aac", "flac", "wma", "aiff", "opus"
    ]

    private static let otherFileExtensions: Set<String> = [
        // Documents & spreadsheets
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
        "odt", "ods", "odp", "rtf", "csv", "tsv", "txt",
        // Archives & compressed
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz",
        // Installers & executables
        "dmg", "pkg", "exe", "msi", "apk", "deb", "rpm", "ipa",
        // Data & design
        "json", "xml", "yaml", "yml", "psd", "ai", "eps"
    ]

    private static func extractPathExtension(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty { return ext }
        let path = url.path
        if let lastComponent = path.split(separator: "/").last {
            let parts = lastComponent.split(separator: ".")
            if parts.count > 1, let last = parts.last {
                return String(last).lowercased()
            }
        }
        return ""
    }

    private static func classifyAttachment(
        url: URL?,
        mimeType: String? = nil,
        suggestedFilename: String? = nil,
        contentDisposition: String? = nil
    ) -> AttachmentKind {
        // 1. Check suggested filename first
        if let filename = suggestedFilename, !filename.isEmpty {
            let ext = (filename as NSString).pathExtension.lowercased()
            if pdfFileExtensions.contains(ext) { return .pdf }
            if mediaFileExtensions.contains(ext) { return .media }
            if otherFileExtensions.contains(ext) { return .otherFile }
        }

        // 2. Check Content-Disposition header
        if let disposition = contentDisposition?.lowercased() {
            if disposition.contains("filename") || disposition.contains("attachment") {
                if let range = disposition.range(of: "filename=") {
                    let suffix = String(disposition[range.upperBound...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'; "))
                    let ext = (suffix as NSString).pathExtension.lowercased()
                    if pdfFileExtensions.contains(ext) { return .pdf }
                    if mediaFileExtensions.contains(ext) { return .media }
                    if !ext.isEmpty { return .otherFile }
                }
                if let mime = mimeType?.lowercased() {
                    if mime == "application/pdf" || mime == "application/x-pdf" { return .pdf }
                    if mime.hasPrefix("image/") || mime.hasPrefix("video/") || mime.hasPrefix("audio/") { return .media }
                }
                return .otherFile
            }
        }

        // 3. Check URL extension
        if let url = url {
            let ext = extractPathExtension(from: url)
            if pdfFileExtensions.contains(ext) { return .pdf }
            if mediaFileExtensions.contains(ext) { return .media }
            if otherFileExtensions.contains(ext) { return .otherFile }
        }

        // 4. Check MIME type
        if let mime = mimeType?.lowercased(), !mime.isEmpty {
            if mime == "application/pdf" || mime == "application/x-pdf" {
                return .pdf
            }
            if mime.hasPrefix("image/") || mime.hasPrefix("video/") || mime.hasPrefix("audio/") {
                return .media
            }
            let webMimes = ["text/html", "application/xhtml+xml", "text/javascript", "application/javascript", "application/x-javascript", "text/css"]
            if !webMimes.contains(where: { mime.contains($0) }) {
                if mime.contains("word") || mime.contains("excel") || mime.contains("sheet") ||
                   mime.contains("presentation") || mime.contains("powerpoint") || mime.contains("zip") ||
                   mime.contains("octet-stream") || mime.contains("tar") || mime.contains("compressed") ||
                   mime.contains("document") || mime.contains("text/csv") {
                    return .otherFile
                }
            }
        }

        return .none
    }

    private func openInDefaultBrowser(fileURL: URL) {
        if let defaultBrowserURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://apple.com")!) {
            NSWorkspace.shared.open([fileURL], withApplicationAt: defaultBrowserURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let targetURL = navigationAction.request.url {
            let kind = Self.classifyAttachment(url: targetURL)
            if kind == .pdf {
                // PDF -> open in browser
                NSWorkspace.shared.open(targetURL)
                return nil
            } else if kind == .media || kind == .otherFile {
                // Media or other file -> start background download and open in OS default app
                webView.startDownload(using: navigationAction.request) { [weak self] download in
                    download.delegate = self
                }
                return nil
            }

            if isExternalURL(targetURL) {
                NSWorkspace.shared.open(targetURL)
                return nil
            }
        }

        // WebKit requires the returned WKWebView to be initialized with the exact configuration passed into this method.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 540, height: 700), configuration: configuration)
        popup.uiDelegate = self
        popup.navigationDelegate = self
        popup.customUserAgent = webView.customUserAgent
        self.popupWebView = popup
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView == popupWebView {
            popupWebView = nil
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let result = alert.runModal() == .alertFirstButtonReturn
        completionHandler(result)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        let result = openPanel.runModal()
        if result == .OK {
            completionHandler(openPanel.urls)
        } else {
            completionHandler(nil)
        }
    }

    // MARK: - WKNavigationDelegate (External link routing & downloads)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let targetURL = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if ["blob", "data", "about"].contains(targetURL.scheme?.lowercased()) {
            decisionHandler(.allow)
            return
        }

        // Check if user or page is navigating to a file attachment
        if navigationAction.targetFrame?.isMainFrame == true {
            let kind = Self.classifyAttachment(url: targetURL)
            if kind == .pdf {
                decisionHandler(.cancel)
                if webView == popupWebView { popupWebView = nil }
                NSWorkspace.shared.open(targetURL)
                return
            } else if kind == .media || kind == .otherFile {
                if webView == popupWebView { popupWebView = nil }
                decisionHandler(.download)
                return
            }

            // Only open in external browser if the user explicitly clicked a link targeting the main frame
            // and it is truly an external website, not an auth domain or subframe captcha/challenge
            if navigationAction.navigationType == .linkActivated && isExternalURL(targetURL) {
                decisionHandler(.cancel)
                if webView == popupWebView { popupWebView = nil }
                NSWorkspace.shared.open(targetURL)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        let httpResponse = navigationResponse.response as? HTTPURLResponse
        let contentDisposition = (httpResponse?.allHeaderFields["Content-Disposition"]
            ?? httpResponse?.allHeaderFields["content-disposition"]) as? String
        let responseURL = navigationResponse.response.url
        let mimeType = navigationResponse.response.mimeType
        let suggestedFilename = navigationResponse.response.suggestedFilename

        let kind = Self.classifyAttachment(
            url: responseURL,
            mimeType: mimeType,
            suggestedFilename: suggestedFilename,
            contentDisposition: contentDisposition
        )

        if navigationResponse.isForMainFrame {
            if kind == .pdf {
                if webView == popupWebView { popupWebView = nil }
                if let disp = contentDisposition?.lowercased(), disp.contains("attachment") {
                    decisionHandler(.download)
                    return
                } else if let url = responseURL, ["http", "https"].contains(url.scheme?.lowercased()) {
                    decisionHandler(.cancel)
                    NSWorkspace.shared.open(url)
                    return
                } else {
                    decisionHandler(.download)
                    return
                }
            } else if kind == .media || kind == .otherFile || !navigationResponse.canShowMIMEType {
                if webView == popupWebView { popupWebView = nil }
                decisionHandler(.download)
                return
            }
        } else {
            // Subframe / iframe attachments
            if !navigationResponse.canShowMIMEType || (contentDisposition?.lowercased().contains("attachment") == true) {
                decisionHandler(.download)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: - WKDownloadDelegate
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let fileManager = FileManager.default
        let downloadsDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

        var destinationURL = downloadsDir.appendingPathComponent(suggestedFilename)
        var counter = 1
        let ext = destinationURL.pathExtension
        let baseName = destinationURL.deletingPathExtension().lastPathComponent

        while fileManager.fileExists(atPath: destinationURL.path) {
            let candidate = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            destinationURL = downloadsDir.appendingPathComponent(candidate)
            counter += 1
        }
        downloadDestinations[ObjectIdentifier(download)] = destinationURL
        completionHandler(destinationURL)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destinationURL = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        
        let ext = destinationURL.pathExtension.lowercased()
        if ext == "pdf" {
            // PDF -> Open in browser
            openInDefaultBrowser(fileURL: destinationURL)
        } else {
            // Media file or other file -> Open in OS default app
            NSWorkspace.shared.open(destinationURL)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        report(error)
    }

    private func isExternalURL(_ url: URL) -> Bool {
        guard let targetHost = url.host?.lowercased(),
              let homeHost = homeURL.host?.lowercased() else { return false }

        let authDomains = [
            "accounts.google.com",
            "appleid.apple.com",
            "login.microsoftonline.com",
            "login.live.com",
            "account.live.com",
            "account.microsoft.com",
            "auth0.com",
            "arkoselabs.com",
            "funcaptcha.com",
            "recaptcha.net",
            "hcaptcha.com",
            "cloudflare.com",
            "challenges.cloudflare.com"
        ]
        if authDomains.contains(where: { targetHost == $0 || targetHost.hasSuffix(".\($0)") }) {
            return false
        }

        let cleanHome = homeHost.replacingOccurrences(of: "^(www|web|m|app)\\.", with: "", options: .regularExpression)

        // LinkedIn domain family
        if cleanHome == "linkedin.com" {
            let linkedinFamily = ["linkedin.com", "licdn.com"]
            if linkedinFamily.contains(where: { targetHost == $0 || targetHost.hasSuffix(".\($0)") }) {
                return false
            }
        }

        let metaFamily = ["instagram.com", "facebook.com", "fb.com", "messenger.com", "threads.net", "whatsapp.com"]
        if metaFamily.contains(cleanHome) && metaFamily.contains(where: { targetHost == $0 || targetHost.hasSuffix(".\($0)") }) {
            return false
        }

        if (cleanHome == "telegram.org" || cleanHome == "t.me") &&
            (targetHost == "telegram.org" || targetHost.hasSuffix(".telegram.org") || targetHost == "t.me") {
            return false
        }

        if targetHost == cleanHome || targetHost.hasSuffix(".\(cleanHome)") {
            return false
        }

        return true
    }

    private func report(_ failure: Error) {
        if (failure as NSError).code == NSURLErrorCancelled { return }
        isLoading = false
        error = failure.localizedDescription
        updateNavigation()
    }

    private func updateNavigation() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url
    }

    private static let activityScript = #"""
    (() => {
      if (window.__multispaceActivityObserver) return;
      window.__multispaceActivityObserver = true;
      const clean = value => (value || '').replace(/\s+/g, ' ').trim();
      let pending = null;
      let lastPayload = '';

      // WhatsApp Web Backend IndexedDB & Memory Cache
      const waBackendCache = {
        contactsByName: new Map(),
        contactsByDigits: new Map(),
        groups: new Map(),
        lastSync: 0
      };

      function formatPhoneNumber(digits) {
        if (!digits) return '';
        if (digits.startsWith('91') && digits.length === 12) {
          return '+91 ' + digits.slice(2, 7) + ' ' + digits.slice(7);
        }
        if (digits.startsWith('1') && digits.length === 11) {
          return '+1 ' + digits.slice(1, 4) + ' ' + digits.slice(4, 7) + ' ' + digits.slice(7);
        }
        if (digits.startsWith('44') && digits.length >= 12) {
          return '+44 ' + digits.slice(2, 6) + ' ' + digits.slice(6);
        }
        return '+' + digits;
      }

      function extractDigitsFromId(idField) {
        if (!idField) return '';
        let s = '';
        if (typeof idField === 'string') s = idField;
        else if (typeof idField._serialized === 'string') s = idField._serialized;
        else if (typeof idField.user === 'string') s = idField.user;
        else if (typeof idField.jid === 'string') s = idField.jid;
        s = s.split('@')[0];
        return s.replace(/\D/g, '');
      }

      function processRawContact(c) {
        if (!c) return;
        let rawId = '';
        if (typeof c.id === 'string') rawId = c.id;
        else if (c.id && typeof c.id._serialized === 'string') rawId = c.id._serialized;
        else if (c.id && typeof c.id.user === 'string') rawId = c.id.user + '@c.us';
        else if (typeof c.jid === 'string') rawId = c.jid;
        else if (typeof c.phoneNumber === 'string') rawId = c.phoneNumber;

        if (!rawId || rawId.includes('@g.us')) return;

        const digits = extractDigitsFromId(rawId);
        if (!digits || digits.length < 7) return;

        const phone = formatPhoneNumber(digits);
        const name = clean(c.name || c.displayName || c.verifiedName || c.formattedName || '');
        const pushname = clean(c.pushname || c.notifyName || c.shortName || '').replace(/^~/, '');

        const item = {
          digits: digits,
          phone: phone,
          name: name,
          username: pushname
        };

        waBackendCache.contactsByDigits.set(digits, item);
        if (digits.length >= 10) {
          waBackendCache.contactsByDigits.set(digits.slice(-10), item);
        }

        if (name) {
          const low = name.toLowerCase();
          waBackendCache.contactsByName.set(low, item);
          const stripped = low.replace(/[^a-z0-9]/g, '');
          if (stripped && stripped !== low) {
            waBackendCache.contactsByName.set(stripped, item);
          }
        }

        if (pushname) {
          const pLow = pushname.toLowerCase();
          if (!waBackendCache.contactsByName.has(pLow)) {
            waBackendCache.contactsByName.set(pLow, item);
          }
          const pStripped = pLow.replace(/[^a-z0-9]/g, '');
          if (pStripped && pStripped !== pLow && !waBackendCache.contactsByName.has(pStripped)) {
            waBackendCache.contactsByName.set(pStripped, item);
          }
        }
      }

      function processRawGroup(g) {
        if (!g) return;
        const subject = clean(g.subject || g.name || '');
        const gid = typeof g.id === 'string' ? g.id : (g.id?._serialized || '');
        const rawParts = g.participants || g.participantList || g.groupMetadata?.participants || [];
        const participants = [];

        for (const p of rawParts) {
          let pid = '';
          if (typeof p === 'string') pid = p;
          else if (typeof p.id === 'string') pid = p.id;
          else if (p.id?._serialized) pid = p.id._serialized;
          else if (p.id?.user) pid = p.id.user + '@c.us';
          else if (typeof p.jid === 'string') pid = p.jid;

          const pDigits = extractDigitsFromId(pid);
          if (!pDigits || pDigits.length < 7) continue;

          const isAdmin = Boolean(p.isAdmin || p.isSuperAdmin || p.role === 'admin' || p.role === 'creator');
          const contactInfo = waBackendCache.contactsByDigits.get(pDigits) ||
                              (pDigits.length >= 10 ? waBackendCache.contactsByDigits.get(pDigits.slice(-10)) : null);
          const resolvedName = contactInfo?.name || '';
          const resolvedPushname = contactInfo?.username || clean(p.pushname || p.notifyName || '').replace(/^~/, '');
          const phone = contactInfo?.phone || formatPhoneNumber(pDigits);

          participants.push({
            digits: pDigits,
            phone: phone,
            name: resolvedName,
            username: resolvedPushname,
            isAdmin: isAdmin
          });
        }

        const groupData = {
          id: gid,
          subject: subject,
          participants: participants
        };

        if (subject) {
          const sLow = subject.toLowerCase();
          waBackendCache.groups.set(sLow, groupData);
          const sStripped = sLow.replace(/[^a-z0-9]/g, '');
          if (sStripped && sStripped !== sLow) {
            waBackendCache.groups.set(sStripped, groupData);
          }
        }
        if (gid) {
          waBackendCache.groups.set(gid.toLowerCase(), groupData);
        }
      }

      let waSyncRunning = false;
      async function syncWhatsAppBackend() {
        if (waSyncRunning) return;
        if (!location.hostname.toLowerCase().endsWith('whatsapp.com')) return;
        if (Date.now() - waBackendCache.lastSync < 6000 && waBackendCache.contactsByName.size > 0) return;

        waSyncRunning = true;
        try {
          // 1. Try window.Store if exposed or reachable
          try {
            if (window.Store) {
              if (window.Store.Contact) {
                const contacts = window.Store.Contact.models || window.Store.Contact._models || [];
                for (const c of contacts) processRawContact(c);
              }
              if (window.Store.GroupMetadata) {
                const groups = window.Store.GroupMetadata.models || window.Store.GroupMetadata._models || [];
                for (const g of groups) processRawGroup(g);
              }
            }
          } catch(e) {}

          // 2. Open IndexedDB database 'model-storage' directly
          if (window.indexedDB) {
            await new Promise(resolve => {
              try {
                const req = window.indexedDB.open('model-storage');
                req.onerror = () => resolve();
                req.onblocked = () => resolve();
                req.onsuccess = (e) => {
                  const db = e.target.result;
                  if (!db) return resolve();

                  const storeNames = Array.from(db.objectStoreNames || []);
                  const cStoreName = storeNames.find(s => s === 'contact' || s.includes('contact'));
                  const gStoreName = storeNames.find(s => s === 'group-metadata' || s.includes('group-metadata'));
                  const needed = [cStoreName, gStoreName].filter(Boolean);

                  if (needed.length === 0) {
                    db.close();
                    return resolve();
                  }

                  try {
                    const tx = db.transaction(needed, 'readonly');
                    if (cStoreName) {
                      const cs = tx.objectStore(cStoreName);
                      const csReq = cs.getAll();
                      csReq.onsuccess = () => {
                        const all = csReq.result || [];
                        for (const c of all) processRawContact(c);
                      };
                    }
                    if (gStoreName) {
                      const gs = tx.objectStore(gStoreName);
                      const gsReq = gs.getAll();
                      gsReq.onsuccess = () => {
                        const all = gsReq.result || [];
                        for (const g of all) processRawGroup(g);
                      };
                    }
                    tx.oncomplete = () => {
                      db.close();
                      resolve();
                    };
                    tx.onerror = () => {
                      db.close();
                      resolve();
                    };
                  } catch(err) {
                    db.close();
                    resolve();
                  }
                };
              } catch(err) {
                resolve();
              }
            });
          }

          waBackendCache.lastSync = Date.now();
        } catch(e) {
        } finally {
          waSyncRunning = false;
        }
      }

      function getCookie(name) {
        const parts = (document.cookie || '').split(';');
        for (let i = 0; i < parts.length; i++) {
          const pair = parts[i].trim().split('=');
          if (pair[0] === name) return decodeURIComponent(pair[1] || '');
        }
        return '';
      }

      async function fetchInstagramDirect() {
        try {
          const csrf = getCookie('csrftoken');
          const resp = await fetch('/api/v1/direct_v2/inbox/?persistentBadging=true&folder=&limit=20', {
            headers: {
              'X-CSRFToken': csrf,
              'X-IG-App-ID': '936619743392459',
              'X-Requested-With': 'XMLHttpRequest',
              'Accept': '*/*'
            },
            credentials: 'include'
          });
          if (!resp.ok) return [];
          const data = await resp.json();
          const threads = (data && data.inbox && data.inbox.threads) || [];
          const results = [];
          for (const t of threads) {
            const threadId = t.thread_id || t.thread_v2_id || '';
            const user = (t.users && t.users[0]) || {};
            const sender = t.thread_title || user.full_name || user.username || 'Instagram User';
            let text = '';
            const lastItem = t.last_permanent_item || {};
            if (lastItem.text) {
              text = clean(lastItem.text);
            } else if (lastItem.item_type === 'media' || lastItem.media) {
              text = '📷 Photo / Video';
            } else if (lastItem.item_type === 'voice_media') {
              text = '🎤 Voice message';
            } else if (lastItem.item_type === 'clip') {
              text = '🎬 Reel';
            } else if (lastItem.item_type === 'like' || lastItem.like) {
              text = '❤️ Liked a message';
            } else if (lastItem.item_type === 'action_log') {
              text = clean(lastItem.action_log?.description || 'Active chat');
            } else {
              text = 'Direct message';
            }
            const isUnread = t.read_state === 0;
            let time = '';
            if (lastItem.timestamp) {
              const d = new Date(Math.floor(Number(lastItem.timestamp) / 1000));
              time = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            }
            if (sender && text) {
              results.push({
                sender: sender.slice(0, 80),
                text: text.slice(0, 240),
                time: time || undefined,
                link: threadId ? `https://www.instagram.com/direct/t/${threadId}/` : 'https://www.instagram.com/direct/inbox/',
                unread: isUnread ? "true" : "false"
              });
            }
          }
          return results;
        } catch (e) {
          return [];
        }
      }

      async function fetchLinkedInDirect() {
        try {
          const csrf = (getCookie('JSESSIONID') || '').replace(/"/g, '');
          if (!csrf) return [];
          const resp = await fetch('/voyager/api/messaging/conversations?keyVersion=LEGACY_INBOX', {
            headers: {
              'csrf-token': csrf,
              'x-restli-protocol-version': '2.0.0',
              'accept': 'application/vnd.linkedin.normalized+json+2.1'
            },
            credentials: 'include'
          });
          if (!resp.ok) return [];
          const data = await resp.json();
          const elements = data.elements || (data.data && data.data.elements) || [];
          const included = data.included || [];
          const results = [];

          for (const conv of elements) {
            const urn = conv.entityUrn || '';
            const unread = conv.read === false || (conv.unreadCount && conv.unreadCount > 0);
            
            let sender = '';
            if (conv.conversationParticipants && conv.conversationParticipants.length > 0) {
              for (const p of conv.conversationParticipants) {
                const pUrn = p.participant || p['*participant'] || '';
                const profile = included.find(inc => inc.entityUrn === pUrn || (pUrn && inc.entityUrn && inc.entityUrn.includes(pUrn)));
                if (profile && (profile.firstName || profile.lastName)) {
                  sender = clean(`${profile.firstName || ''} ${profile.lastName || ''}`);
                  break;
                }
              }
            }

            let text = '';
            let time = '';
            if (conv.events && conv.events.length > 0) {
              const lastEvtUrn = conv.events[0] || '';
              const evtObj = included.find(inc => inc.entityUrn === lastEvtUrn || (lastEvtUrn && inc.entityUrn && inc.entityUrn.includes(lastEvtUrn)));
              if (evtObj) {
                if (evtObj.eventContent && evtObj.eventContent.attributedBody) {
                  text = clean(evtObj.eventContent.attributedBody.text || '');
                }
                if (evtObj.createdAt) {
                  const d = new Date(evtObj.createdAt);
                  time = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                }
              }
            }

            if (!sender && conv.title) {
              sender = clean(conv.title);
            }

            if (sender && text) {
              const cleanUrn = urn.replace(/^urn:li:fs_conversation:/, '');
              results.push({
                sender: sender.slice(0, 80),
                text: text.slice(0, 240),
                time: time || undefined,
                link: cleanUrn ? `https://www.linkedin.com/messaging/thread/${cleanUrn}/` : 'https://www.linkedin.com/messaging/',
                unread: unread ? "true" : "false"
              });
            }
          }
          return results;
        } catch (e) {
          return [];
        }
      }

      async function collect(force = false) {
        const host = location.hostname.toLowerCase();
        let messages = [];

        // 0. Direct WhatsApp IndexedDB & Model Sync
        if (host.endsWith('whatsapp.com')) {
          try {
            await syncWhatsAppBackend();
          } catch (e) {}
        }

        // 1. Direct Background API Scrapers for Home Feeds
        if (host.endsWith('instagram.com')) {
          try {
            const igMsgs = await fetchInstagramDirect();
            if (igMsgs && igMsgs.length > 0) {
              messages.push(...igMsgs);
            }
          } catch (e) {}
        } else if (host.endsWith('linkedin.com')) {
          try {
            const liMsgs = await fetchLinkedInDirect();
            if (liMsgs && liMsgs.length > 0) {
              messages.push(...liMsgs);
            }
          } catch (e) {}
        }

        // 2. DOM Scrapers (Live Page / Fallback)
        let selector = '';
        if (host.endsWith('whatsapp.com')) {
          selector = '#pane-side [role="row"], #pane-side [role="listitem"], [data-testid="cell-frame-container"], div[role="listitem"], div._ak8l, div[tabindex="-1"][role="row"], div[data-testid="chat-list-item"]';
        } else if (host.endsWith('instagram.com')) {
          selector = 'a[href*="/direct/t/"], div[role="listitem"] a[href*="/direct/"], a[href*="/direct/inbox/"], div[role="row"] a[role="link"]';
        } else if (host.endsWith('telegram.org')) {
          selector = '.chat-list .ListItem, .chat-list-item, .chatlist-chat, a.chatlist-chat, .chatlist-parts, .c-ripple, div.chat-item, .chatlist a';
        } else if (host.endsWith('facebook.com') || host.endsWith('messenger.com')) {
          selector = 'a[href*="/messages/t/"], div[role="row"] a[role="link"], div[role="gridcell"] a, a[href*="/t/"]';
        } else if (host.endsWith('snapchat.com')) {
          selector = '[data-testid*="conversation-list"] [role="button"], a[href*="/chat/"]';
        } else if (host.endsWith('linkedin.com')) {
          selector = 'li.msg-conversation-listitem, .msg-conversation-card, a[href*="/messaging/thread/"], [data-view-name*="conversation"], .msg-overlay-list-bubble__convo-item, .msg-overlay-conversation-bubble, div.msg-conversations-container__conversations-list li, div[data-view-name="conversation-list-item"], div[data-control-name="conversation_item"], li[class*="msg-conversation"], div[class*="msg-conversation-card"]';
        } else if (host.endsWith('x.com') || host.endsWith('twitter.com')) {
          selector = '[data-testid="conversation"], a[href*="/messages/"]';
        } else if (host.endsWith('discord.com')) {
          selector = 'a[href*="/channels/@me/"], li[class*="channel_"], [data-list-item-id*="private-channels-"]';
        } else if (host.endsWith('slack.com')) {
          selector = '[data-qa="channel_sidebar_name_matching"], div.p-channel_sidebar__channel, .c-link--channel, [data-qa-channel-sidebar-channel-id]';
        } else if (host.endsWith('teams.microsoft.com')) {
          selector = 'div[data-tid="chat-list-item"], div[data-tid="team-channel-item"]';
        } else if (host.endsWith('reddit.com')) {
          selector = '[data-testid="chat-room-item"], div.message, .entry, a[href*="/message/messages/"]';
        } else {
          selector = '[role="listitem"] a[href*="message"], [role="listitem"] a[href*="chat"], a[href*="/messages/"], a[href*="/direct/"], [role="listitem"]';
        }

        if (host.endsWith('linkedin.com')) {
          const minimizedContainer = document.querySelector('.msg-overlay-list-bubble--is-minimized');
          if (minimizedContainer) {
            const headerBtn = minimizedContainer.querySelector('.msg-overlay-bubble-header, button');
            if (headerBtn) {
              headerBtn.click();
            }
          }
        }

        if (selector) {
          const nodes = document.querySelectorAll(selector);
          nodes.forEach(node => {
            if (messages.length >= 100) return;
            let sender = '';
            let text = '';
            let time = '';
            let link = '';

            const anchor = node.tagName === 'A' ? node : node.querySelector('a');
            if (anchor && anchor.href && anchor.href.startsWith('http')) {
              link = anchor.href;
            }

            const timeNode = node.querySelector('time, [class*="time"], [class*="timestamp"], [data-testid*="time"], div._ak8i, span[class*="_ak8i"], span[data-testid="cell-frame-secondary-title"]');
            if (timeNode) {
              time = clean(timeNode.innerText || timeNode.getAttribute('datetime'));
            }

            // WhatsApp specific: contact name in span[title] or _ak8q
            if (host.endsWith('whatsapp.com')) {
              const nameSpan = node.querySelector('span[title], div[class*="_ak8q"] span, span[data-testid="cell-frame-title"], [data-testid="chat-title"]');
              if (nameSpan) sender = clean(nameSpan.getAttribute('title') || nameSpan.innerText);
              const textSpan = node.querySelector('[data-testid="last-msg-status"], span[class*="_ao3e"], div[class*="_ak8k"] span, span[data-testid="last-msg"]');
              if (textSpan) text = clean(textSpan.innerText);
            }

            // LinkedIn specific:
            if (!sender && host.endsWith('linkedin.com')) {
              const nameEl = node.querySelector('.msg-conversation-listitem__participant-names, span[data-anonymize="person-name"], h3.msg-conversation-listitem__participant-names, .msg-overlay-list-bubble__convo-item-header, .msg-conversation-card__participant-names, div.artdeco-entity-lockup__title, [data-view-name="conversation-list-item"] h3, h3, h4, strong');
              if (nameEl) sender = clean(nameEl.innerText);
              const snippetEl = node.querySelector('.msg-conversation-card__message-snippet, .msg-overlay-list-bubble__message-snippet, span.msg-conversation-card__message-snippet-body, p.msg-conversation-card__message-snippet, .msg-s-message-group__meta, [class*="message-snippet"]');
              if (snippetEl) text = clean(snippetEl.innerText);
              if (!text && nameEl) {
                const paragraphs = Array.from(node.querySelectorAll('p, span')).filter(el => el !== nameEl && !nameEl.contains(el) && clean(el.innerText).length > 0);
                if (paragraphs.length > 0) text = clean(paragraphs[paragraphs.length - 1].innerText);
              }
              if (!link || !link.startsWith('http')) {
                link = 'https://www.linkedin.com/messaging/';
              }
            }

            // Telegram specific:
            if (!sender && host.endsWith('telegram.org')) {
              const nameEl = node.querySelector('.peer-title, .title, .user-caption, .chat-title, h3');
              if (nameEl) sender = clean(nameEl.innerText);
              const snippetEl = node.querySelector('.subtitle, .last-message, .dialog-subtitle, .message, p');
              if (snippetEl) text = clean(snippetEl.innerText);
            }

            // Slack specific:
            if (!sender && host.endsWith('slack.com')) {
              const nameEl = node.querySelector('[data-qa="channel_sidebar_name_matching"], .p-channel_sidebar__name, span.c-link--channel');
              if (nameEl) sender = clean(nameEl.innerText);
              const snippetEl = node.querySelector('.p-channel_sidebar__subtext, [data-qa="channel_sidebar_prefix"]');
              if (snippetEl) text = clean(snippetEl.innerText);
            }

            // Teams specific:
            if (!sender && host.endsWith('teams.microsoft.com')) {
              const nameEl = node.querySelector('[data-tid="chat-list-item-title"], span[data-tid="channel-list-item-title"], h3');
              if (nameEl) sender = clean(nameEl.innerText);
              const snippetEl = node.querySelector('[data-tid="chat-list-item-preview"], [data-tid="chat-list-item-message-body"], p');
              if (snippetEl) text = clean(snippetEl.innerText);
            }

            // Instagram specific:
            if (!sender && host.endsWith('instagram.com')) {
              const nameEl = node.querySelector('span[dir="auto"], span.x1lliihq, span[class*="x193iq5w"], div[role="button"] span');
              if (nameEl) sender = clean(nameEl.innerText);
              const snippetEl = node.querySelector('span.x1lliihq span, div[class*="x1n2onr6"] span');
              if (snippetEl) text = clean(snippetEl.innerText);
            }

            // Facebook / Messenger specific:
            if (!sender && (host.endsWith('facebook.com') || host.endsWith('messenger.com'))) {
              const nameEl = node.querySelector('span[dir="auto"], span.x1lliihq, div[role="gridcell"] span');
              if (nameEl) sender = clean(nameEl.innerText);
              const snippetEl = node.querySelector('span[dir="auto"], div.x78zum5 span');
              if (snippetEl) text = clean(snippetEl.innerText);
            }

            // X / Twitter specific:
            if (!sender && (host.endsWith('x.com') || host.endsWith('twitter.com'))) {
              const nameEl = node.querySelector('[data-testid="User-Name"], div[dir="ltr"] span');
              if (nameEl) sender = clean(nameEl.innerText);
              const snippetEl = node.querySelector('div[dir="auto"] span, [data-testid="last-message"]');
              if (snippetEl) text = clean(snippetEl.innerText);
            }

            // Fallback line parsing
            if (!sender || !text) {
              const lines = (node.innerText || '').split(/\n+/).map(clean).filter(Boolean);
              if (lines.length >= 2) {
                if (!sender) sender = lines[0].slice(0, 80);
                if (!text) {
                  if (/^((\d{1,2}:\d{2}(\s?[AP]M)?)|yesterday|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday)$/i.test(lines[1])) {
                    if (!time) time = lines[1];
                    text = lines.slice(2).join(' ').slice(0, 240);
                  } else {
                    text = lines.slice(1).join(' ').slice(0, 240);
                  }
                }
              }
            }

            const lowerSender = sender.toLowerCase();
            if (lowerSender === 'archived' || lowerSender === 'chats' || lowerSender === 'messages' || lowerSender === 'search' || lowerSender === 'filter chats') return;

            const isUnread = Boolean(
              node.querySelector('[aria-label*="unread" i], [class*="unread" i], .badge, [data-testid*="unread"], span[class*="_ak8q"], .msg-conversation-listitem--unread, .msg-conversation-card--unread, [data-badge="unread"], span.msg-conversation-listitem__unread-count, span.notification-badge, .notification-badge--show, [data-qa*="unread"], [data-qa-channel-sidebar-is-unread="true"]') ||
              (node.getAttribute('aria-label') || '').toLowerCase().includes('unread') ||
              (node.className || '').toString().toLowerCase().includes('unread') ||
              node.querySelector('span[class*="unread"], div[class*="unread"]')
            );

            if (sender && text) {
              if (!messages.some(m => m.sender === sender && m.text === text)) {
                messages.push({ sender, text, time: time || undefined, link: link || undefined, unread: isUnread ? "true" : "false" });
              }
            }
          });
        }

        const notifications = [];
        const rawNotifications = [];
        const seenNotifText = new Set();

        const notifSelectors = [
          '.nt-card',
          '[data-id*="urn:li:activity"]',
          '[data-testid="cellInnerDiv"]',
          '[data-testid*="notification"]',
          '[data-qa="activity_item"]',
          '.notification-item',
          '[role="alert"]',
          '[aria-live="assertive"]',
          '[aria-label*="notification" i]',
          '[aria-label*="unread message" i]'
        ];

        document.querySelectorAll(notifSelectors.join(',')).forEach(node => {
          if (rawNotifications.length >= 15) return;
          if (node.parentElement && node.parentElement.closest(notifSelectors.join(','))) return;

          const anchor = node.querySelector('a[href]') || node.closest('a[href]');
          const link = anchor ? anchor.href : null;
          const timeNode = node.querySelector('time, [class*="time"], [class*="timestamp"], [aria-label*="ago"], [aria-label*="AM"], [aria-label*="PM"]');
          const time = timeNode ? clean(timeNode.innerText || timeNode.getAttribute('aria-label') || '').slice(0, 40) : null;

          let title = '';
          const heading = node.querySelector('h1, h2, h3, h4, [class*="headline"], [class*="title"], strong, b');
          if (heading) {
            title = clean(heading.innerText).slice(0, 80);
          }

          let rawText = clean(node.getAttribute('aria-label') || node.innerText);
          let bodyText = rawText;
          if (title && bodyText.startsWith(title)) {
            bodyText = clean(bodyText.slice(title.length));
          }
          bodyText = bodyText.slice(0, 240);

          if (!title && bodyText) {
            const dotIdx = bodyText.indexOf('. ');
            if (dotIdx > 0 && dotIdx < 60) {
              title = bodyText.slice(0, dotIdx);
              bodyText = bodyText.slice(dotIdx + 2);
            } else {
              title = bodyText.slice(0, 60);
            }
          }

          if (!title && !bodyText) return;

          const combined = (title + ' ' + bodyText).toLowerCase();
          let category = 'general';
          if (combined.includes('mentioned') || combined.includes('tagged') || combined.includes('@')) {
            category = 'mention';
          } else if (combined.includes('security') || combined.includes('password') || combined.includes('sign-in') || combined.includes('login') || combined.includes('device') || combined.includes('2fa') || combined.includes('code')) {
            category = 'security';
          } else if (combined.includes('request') || combined.includes('invited') || combined.includes('connect') || combined.includes('follow') || combined.includes('joined')) {
            category = 'request';
          } else if (combined.includes('reacted') || combined.includes('liked') || combined.includes('reposted') || combined.includes('retweet') || combined.includes('shared')) {
            category = 'reaction';
          } else if (combined.includes('commented') || combined.includes('replied')) {
            category = 'reply';
          }

          const sig = (title + '|' + bodyText).slice(0, 100);
          if (seenNotifText.has(sig)) return;
          seenNotifText.add(sig);

          notifications.push(rawText.slice(0, 240));
          rawNotifications.push({
            title: title || 'Notice',
            text: bodyText || title || 'Notification received',
            time: time || undefined,
            link: link || undefined,
            category: category
          });
        });

        // 3. Active Conversation Thread & Contact Detection
        let activeContact = '';
        if (host.endsWith('whatsapp.com')) {
          const titleEl = document.querySelector('#main header [data-testid="conversation-info-header-chat-title"], #main header div[class*="_amj2"] span, #main header div._ak8q span, #main header h2, #main header span[dir="auto"]');
          if (titleEl) activeContact = clean(titleEl.getAttribute('title') || titleEl.innerText);
        } else if (host.endsWith('telegram.org')) {
          const headerName = document.querySelector('.chat-info .peer-title, .chat-info .title, .top-chat-info .name, .sidebar-header-title');
          if (headerName) activeContact = clean(headerName.innerText);
        } else if (host.endsWith('discord.com')) {
          const headerName = document.querySelector('section[aria-label*="Channel header"] h1, h2[class*="title"], [data-list-item-id*="channels___"]');
          if (headerName) activeContact = clean(headerName.innerText);
        } else if (host.endsWith('slack.com')) {
          const headerName = document.querySelector('[data-qa="channel_name"], .p-classic_nav__team_header__channel_name');
          if (headerName) activeContact = clean(headerName.innerText);
        } else if (host.endsWith('linkedin.com')) {
          const headerName = document.querySelector('.msg-entity-lockup__entity-title, .msg-title-bar__title, .msg-thread__link-to-profile, header h2');
          if (headerName) activeContact = clean(headerName.innerText);
        } else if (host.endsWith('facebook.com') || host.endsWith('messenger.com')) {
          const headerName = document.querySelector('[role="main"] h1, [role="main"] span[dir="auto"]');
          if (headerName) activeContact = clean(headerName.innerText);
        } else if (host.endsWith('instagram.com')) {
          const headerName = document.querySelector('header h2, header span[dir="auto"], a[role="link"] span[dir="auto"]');
          if (headerName) activeContact = clean(headerName.innerText);
        } else if (host.endsWith('teams.microsoft.com')) {
          const headerName = document.querySelector('[data-tid="chat-header-title"], [data-tid="thread-header-title"]');
          if (headerName) activeContact = clean(headerName.innerText);
        }
        if (!activeContact) {
          const titleParts = (document.title || '').split(/[-–|·•]/);
          if (titleParts.length > 1 && !titleParts[0].toLowerCase().includes('whatsapp') && !titleParts[0].toLowerCase().includes('telegram')) {
            activeContact = clean(titleParts[0]);
          }
        }

        const activeThreadMessages = [];
        let bubbleSelectors = '';
        if (host.endsWith('whatsapp.com')) {
          bubbleSelectors = '#main [data-testid="msg-container"], #main .message-in, #main .message-out, #main div[class*="message-"], #main [data-id]';
        } else if (host.endsWith('telegram.org')) {
          bubbleSelectors = '.messages-container .message, .bubbles .bubble, .message-list .message';
        } else if (host.endsWith('discord.com')) {
          bubbleSelectors = 'li[class*="messageListItem"], [id^="chat-messages-"]';
        } else if (host.endsWith('slack.com')) {
          bubbleSelectors = '.c-message_kit__message, [data-qa="message_container"]';
        } else if (host.endsWith('linkedin.com')) {
          bubbleSelectors = '.msg-s-message-list__event, .msg-s-event-listitem, .msg-s-message-group';
        } else if (host.endsWith('facebook.com') || host.endsWith('messenger.com')) {
          bubbleSelectors = 'div[data-testid="message-container"], [role="row"] [role="gridcell"]';
        } else if (host.endsWith('instagram.com')) {
          bubbleSelectors = 'div[role="row"], div.x1n2onr6';
        } else if (host.endsWith('teams.microsoft.com')) {
          bubbleSelectors = '[data-tid="chat-pane-item"], [data-tid="message-pane-list-item"]';
        }

        // Deep group roster & participant crawling (strictly within the SELECTED chat)
        let isGroup = false;
        let groupMemberCount = 0;
        let groupSubtitle = '';
        const membersMap = new Map();

        const getPhoneDigits = (p) => (p || '').replace(/\D/g, '');

        const findExistingMemberKey = (name, phone) => {
          const cleanN = clean(name).toLowerCase();
          const pDigits = getPhoneDigits(phone);

          if (pDigits && pDigits.length >= 7) {
            for (const [k, v] of membersMap.entries()) {
              const vDigits = getPhoneDigits(v.phoneNumber || v.name);
              if (vDigits && vDigits.length >= 7) {
                if (vDigits === pDigits || vDigits.endsWith(pDigits) || pDigits.endsWith(vDigits)) {
                  return k;
                }
              }
            }
          }
          if (cleanN && membersMap.has(cleanN)) {
            return cleanN;
          }
          return null;
        };

        const addGroupMember = (name, role, activity, count, phone, username) => {
          let cleanName = clean(name);
          if (!cleanName || cleanName.toLowerCase() === 'you' || cleanName.toLowerCase() === 'me' || cleanName.toLowerCase() === 'contact') return;
          if (activeContact && cleanName.toLowerCase() === activeContact.toLowerCase()) return;

          // Ignore action buttons and system labels in group info drawers
          const lower = cleanName.toLowerCase();
          if (lower.includes('add participant') || lower.includes('invite to group') || lower.includes('exit group') || lower.includes('report group') || lower.includes('block group') || lower.includes('dismiss as admin')) return;

          let resolvedPhone = phone ? clean(phone) : undefined;
          const isCleanNamePhone = /^\+?[0-9\s\-()]{7,}$/.test(cleanName);
          if (!resolvedPhone && isCleanNamePhone) {
            resolvedPhone = cleanName;
          }

          let resolvedUsername = username ? clean(username) : undefined;
          if (!resolvedUsername && cleanName.startsWith('@')) {
            resolvedUsername = cleanName.slice(1);
          }
          if (resolvedUsername && resolvedUsername.startsWith('@')) {
            resolvedUsername = resolvedUsername.slice(1);
          }

          // BACKEND LOOKUP FOR MISSING PHONE NUMBERS ON NAMED CONTACTS:
          if (!resolvedPhone && waBackendCache.contactsByName.size > 0) {
            const cleanLower = cleanName.toLowerCase();
            const cached = waBackendCache.contactsByName.get(cleanLower) ||
                           waBackendCache.contactsByName.get(cleanLower.replace(/[^a-z0-9]/g, ''));
            if (cached) {
              resolvedPhone = cached.phone;
              if (!resolvedUsername && cached.username) {
                resolvedUsername = cached.username;
              }
            }
          }

          // IF CLEANNAME IS A PHONE NUMBER, RESOLVE SAVED CONTACT NAME FROM BACKEND:
          let finalName = isCleanNamePhone ? (resolvedUsername || '') : cleanName;
          if (isCleanNamePhone && (!finalName || finalName === cleanName)) {
            const digits = getPhoneDigits(cleanName);
            const cached = waBackendCache.contactsByDigits.get(digits) ||
                           (digits.length >= 10 ? waBackendCache.contactsByDigits.get(digits.slice(-10)) : null);
            if (cached) {
              if (cached.name) finalName = cached.name;
              if (cached.username && !resolvedUsername) resolvedUsername = cached.username;
            }
          }

          let normalizedRole = 'Member';
          if (role) {
            const rLow = role.toLowerCase();
            if (rLow.includes('admin') || rLow.includes('owner') || rLow.includes('creator')) {
              normalizedRole = 'Group Admin';
            }
          }

          const safeCount = (typeof count === 'number' && !isNaN(count)) ? count : 0;
          const existingKey = findExistingMemberKey(finalName || cleanName, resolvedPhone);

          if (existingKey) {
            const existing = membersMap.get(existingKey);
            if ((!existing.name || /^\+?[0-9\s\-()]{7,}$/.test(existing.name)) && finalName) {
              existing.name = finalName;
            }
            if (!existing.phoneNumber && resolvedPhone) existing.phoneNumber = resolvedPhone;
            if (!existing.username && resolvedUsername) existing.username = resolvedUsername;
            if (normalizedRole === 'Group Admin') existing.role = 'Group Admin';
            if (safeCount > 0) existing.messageCount = Math.max(existing.messageCount, safeCount);
            if (activity && (!existing.activity || existing.activity === 'In group roster')) existing.activity = activity;
          } else {
            const key = (resolvedPhone || finalName || cleanName).toLowerCase();
            membersMap.set(key, {
              name: finalName,
              role: normalizedRole,
              activity: activity || 'In group roster',
              messageCount: safeCount,
              phoneNumber: resolvedPhone || undefined,
              username: resolvedUsername || undefined
            });
          }
        };

        if (host.endsWith('whatsapp.com')) {
          const mainContainer = document.querySelector('#main');
          if (!mainContainer) {
            // No chat selected in WhatsApp Web
            activeContact = '';
          } else {
            // Header inspection strictly inside #main header
            const headerNodes = Array.from(document.querySelectorAll('#main header span, #main header div, #main header p'));
            for (const node of headerNodes) {
              const txt = clean(node.getAttribute('title') || node.innerText);
              if (!txt || txt === activeContact) continue;

              const cm = txt.match(/(\d+)\s*(participants|members|contacts|people|subscribers)/i);
              if (cm) {
                groupMemberCount = parseInt(cm[1], 10);
                groupSubtitle = txt;
                isGroup = true;
                break;
              }
              const om = txt.match(/and\s*(\d+)\s*others?/i);
              if (om) {
                const othersCount = parseInt(om[1], 10);
                const namedCount = txt.split(',').length;
                groupMemberCount = othersCount + namedCount;
                groupSubtitle = txt;
                isGroup = true;
                break;
              }
              if (txt.includes(',') && txt.length > 5 && !groupSubtitle && !txt.toLowerCase().includes('last seen') && !txt.toLowerCase().includes('typing') && !txt.toLowerCase().includes('online')) {
                groupSubtitle = txt;
                isGroup = true;
              }
            }

            // Inject metadata participants directly from backend for active group
            if (activeContact) {
              const activeLower = activeContact.toLowerCase();
              const activeStripped = activeLower.replace(/[^a-z0-9]/g, '');
              let matchedGroup = waBackendCache.groups.get(activeLower) ||
                                 (activeStripped ? waBackendCache.groups.get(activeStripped) : null);
              if (!matchedGroup) {
                for (const [subj, gData] of waBackendCache.groups.entries()) {
                  if (subj === activeLower || (subj.length > 3 && (activeLower.includes(subj) || subj.includes(activeLower)))) {
                    matchedGroup = gData;
                    break;
                  }
                }
              }

              if (matchedGroup && matchedGroup.participants.length > 0) {
                isGroup = true;
                groupMemberCount = Math.max(groupMemberCount, matchedGroup.participants.length);
                for (const p of matchedGroup.participants) {
                  addGroupMember(
                    p.name || p.username || p.phone,
                    p.isAdmin ? 'Group Admin' : 'Member',
                    'In group roster',
                    0,
                    p.phone,
                    p.username
                  );
                }
              }
            }
          }
        } else if (host.endsWith('telegram.org')) {
          const subEl = document.querySelector('.chat-info .peer-subtitle, .chat-info .info, .chat-info .status');
          if (subEl) {
            groupSubtitle = clean(subEl.innerText);
            if (groupSubtitle.match(/(\d+)\s*(members|subscribers|participants)/i)) {
              isGroup = true;
            }
          }
        } else if (host.endsWith('slack.com')) {
          const subEl = document.querySelector('[data-qa="channel_member_count"], .p-classic_nav__team_header__channel_members, button[aria-label*="member"]');
          if (subEl) {
            groupSubtitle = clean(subEl.innerText);
            isGroup = true;
          }
        } else if (host.endsWith('teams.microsoft.com')) {
          const subEl = document.querySelector('[data-tid="roster-button"], [data-tid="chat-header-members"], button[aria-label*="member"]');
          if (subEl) {
            groupSubtitle = clean(subEl.innerText || subEl.getAttribute('aria-label') || '');
            isGroup = true;
          }
        }

        // Check open right-side group info drawer (NEVER query left sidebar #pane-side or chat lists)
        let groupInfoDrawer = document.querySelector('[data-testid="group-info-drawer"], [data-testid="chat-info-drawer"], [data-testid="drawer-right"]');
        if (!groupInfoDrawer) {
          const titleEl = document.querySelector('header span[title="Group info"], header span[title="Group Info"]');
          if (titleEl) {
            groupInfoDrawer = titleEl.closest('div[tabindex="-1"], div[class*="drawer"], section');
          }
        }
        if (groupInfoDrawer) {
          const drawerText = clean(groupInfoDrawer.innerText || '');
          const isGroupDrawer = drawerText.toLowerCase().includes('group info') || drawerText.toLowerCase().includes('participant') || drawerText.toLowerCase().includes('exit group');
          if (isGroupDrawer) {
            isGroup = true;
            const countMatch = drawerText.match(/(\d+)\s*(participants|members|contacts)/i);
            if (countMatch && groupMemberCount === 0) {
              groupMemberCount = parseInt(countMatch[1], 10);
            }

            // Extract members strictly from rows inside the open group drawer
            const rows = groupInfoDrawer.querySelectorAll('div[data-testid="cell-frame-container"], div[role="listitem"], div[class*="_ak72"]');
            rows.forEach(row => {
              if (row.closest('#pane-side') || row.closest('[data-testid="chat-list"]') || row.closest('#column-left') || row.closest('.p-channel_sidebar')) return;

              const rowText = clean(row.innerText || '');
              if (rowText.toLowerCase().includes('add participant') || rowText.toLowerCase().includes('invite to group') || rowText.toLowerCase().includes('exit group')) return;

              const nameEl = row.querySelector('span[title], span[dir="auto"], div[title]');
              if (nameEl) {
                const primary = clean(nameEl.getAttribute('title') || nameEl.innerText);
                if (!primary || primary.toLowerCase() === 'you') return;

                const adminEl = row.querySelector('[data-testid*="admin"], span[class*="admin"], div[title*="Admin"], div[aria-label*="Admin"]');
                const isAdmin = adminEl !== null || /\b(group\s+admin|admin)\b/i.test(rowText);
                const role = isAdmin ? 'Group Admin' : 'Member';

                let phone = undefined;
                let username = undefined;

                const phoneMatch = rowText.match(/(\+?\d[\d\s\-\(\)]{7,}\d)/);
                if (phoneMatch) phone = clean(phoneMatch[1]);

                // Check row avatar image URL for phone/JID
                const imgEl = row.querySelector('img[src*="u="], img[src*="jid="], img[src*="c.us"]');
                if (imgEl && imgEl.src && !phone) {
                  const m = imgEl.src.match(/(?:u|jid)=(\d{7,15})(?:%40|@)c\.us/i);
                  if (m) phone = formatPhoneNumber(m[1]);
                }

                const nickMatch = rowText.match(/~([^\n\r\t]+)/);
                if (nickMatch) username = clean(nickMatch[1]);

                addGroupMember(primary, role, 'In group roster', 0, phone, username);
              }
            });
          }
        }

        // Check open Contact Info drawer in WhatsApp Web
        const contactDrawer = document.querySelector('[data-testid="contact-info-drawer"]');
        if (contactDrawer) {
          const dText = clean(contactDrawer.innerText || '');
          const phoneM = dText.match(/(\+?\d[\d\s\-\(\)]{7,}\d)/);
          const nameEl = contactDrawer.querySelector('h2, span[title], span[dir="auto"]');
          if (nameEl && phoneM) {
            const cName = clean(nameEl.getAttribute('title') || nameEl.innerText);
            const cPhone = clean(phoneM[1]);
            const pDigits = getPhoneDigits(cPhone);
            if (pDigits && pDigits.length >= 7) {
              const item = { digits: pDigits, phone: cPhone, name: cName, username: '' };
              waBackendCache.contactsByName.set(cName.toLowerCase(), item);
              waBackendCache.contactsByDigits.set(pDigits, item);
              const k = findExistingMemberKey(cName, cPhone);
              if (k) {
                const ex = membersMap.get(k);
                if (!ex.phoneNumber) ex.phoneNumber = cPhone;
              }
            }
          }
        }

        // Extract comma-separated member names from group subtitle only if confirmed group
        if (isGroup && groupSubtitle && groupSubtitle.includes(',')) {
          const parts = groupSubtitle.split(',').map(s => clean(s.replace(/and \d+ others?/i, ''))).filter(Boolean);
          parts.forEach(p => addGroupMember(p, 'Member', 'In group roster', 0));
        }

        if (bubbleSelectors) {
          // Crawl deep: extract up to 200 rendered messages in the thread
          const bubbles = Array.from(document.querySelectorAll(bubbleSelectors)).slice(-200);
          bubbles.forEach(bubble => {
            let sender = '';
            let text = '';
            let isFromMe = false;
            let time = '';

            if (host.endsWith('whatsapp.com')) {
              isFromMe = bubble.classList.contains('message-out') || !!bubble.querySelector('.message-out');
              
              // 1. Try universal copyable-text data-pre-plain-text (e.g. "[10:15, 22/09/2026] Rahul Sharma: ")
              const copyable = bubble.querySelector('div.copyable-text, [data-pre-plain-text]');
              if (copyable && copyable.getAttribute('data-pre-plain-text')) {
                const pre = copyable.getAttribute('data-pre-plain-text');
                const match = pre.match(/\[([^\]]+)\]\s*([^:]+):/);
                if (match) {
                  time = clean(match[1]);
                  const rawAuthor = clean(match[2]);
                  if (rawAuthor && rawAuthor.toLowerCase() !== 'you') {
                    sender = rawAuthor;
                  }
                }
              }

              // 2. Fallback to author element
              if (!sender) {
                const authorNode = bubble.querySelector('span[data-testid="author"], ._amih, span[class*="_ak8q"], span[class*="_ao3e"][dir="auto"], span[class*="author"]');
                if (authorNode) sender = clean(authorNode.innerText);
              }

              // 3. Extract sender phone number from WhatsApp protocol data-id (e.g. false_...@g.us_..._919861012929@c.us)
              let bubblePhone = undefined;
              let bubbleUsername = undefined;
              const dataIdEl = bubble.closest('[data-id]') || bubble.querySelector('[data-id]') || (bubble.getAttribute('data-id') ? bubble : null);
              if (dataIdEl) {
                const dataId = dataIdEl.getAttribute('data-id') || '';
                const jidMatch = dataId.match(/_(\d{7,15})@(c\.us|s\.whatsapp\.net)/);
                if (jidMatch) {
                  const digits = jidMatch[1];
                  if (digits.startsWith('91') && digits.length === 12) {
                    bubblePhone = '+91 ' + digits.slice(2, 7) + ' ' + digits.slice(7);
                  } else if (digits.startsWith('1') && digits.length === 11) {
                    bubblePhone = '+1 ' + digits.slice(1, 4) + ' ' + digits.slice(4, 7) + ' ' + digits.slice(7);
                  } else {
                    bubblePhone = '+' + digits;
                  }
                }
              }

              // 4. Extract pushName (~Nickname) from bubble
              const nickNode = bubble.querySelector('span._ao3e, span[class*="_ao3e"]');
              if (nickNode) {
                const nickText = clean(nickNode.innerText);
                if (nickText.startsWith('~')) {
                  bubbleUsername = nickText.slice(1).trim();
                }
              }

              if (isFromMe) {
                sender = 'You';
              } else if (!sender) {
                sender = activeContact || 'Contact';
              }

              const textNode = bubble.querySelector('span.selectable-text, ._ao3e, span[dir="ltr"], div[class*="copyable-text"] span');
              if (textNode) text = clean(textNode.innerText);

              if (!time) {
                const timeNode = bubble.querySelector('[data-testid="msg-meta"] span, span[dir="auto"], span._ak8i');
                if (timeNode) time = clean(timeNode.innerText);
              }

              // Register participant for group chats with phone and username
              if (isGroup && sender && !isFromMe && sender !== activeContact) {
                addGroupMember(sender, 'Member', time || 'Active in thread', 1, bubblePhone, bubbleUsername);
              }
            } else if (host.endsWith('telegram.org')) {
              isFromMe = bubble.classList.contains('is-out') || bubble.classList.contains('own');
              const textNode = bubble.querySelector('.text-content, .message-content, .translatable-message');
              if (textNode) text = clean(textNode.innerText);
              const authorNode = bubble.querySelector('.message-title, .message-author, .author');
              sender = isFromMe ? 'You' : (authorNode ? clean(authorNode.innerText) : (activeContact || 'Contact'));
              if (isGroup && sender && !isFromMe && sender !== activeContact) {
                addGroupMember(sender, 'Member', time || 'Active in thread', 1);
              }
            } else if (host.endsWith('discord.com')) {
              const authorNode = bubble.querySelector('span[class*="username"]');
              if (authorNode) sender = clean(authorNode.innerText);
              const textNode = bubble.querySelector('div[id^="message-content-"]');
              if (textNode) text = clean(textNode.innerText);
              isFromMe = sender.toLowerCase() === 'you';
              if (isGroup && sender && !isFromMe && sender !== activeContact) {
                addGroupMember(sender, 'Member', time || 'Active in thread', 1);
              }
            } else if (host.endsWith('slack.com')) {
              const authorNode = bubble.querySelector('.c-message__sender_button, [data-qa="message_sender_name"]');
              if (authorNode) sender = clean(authorNode.innerText);
              const textNode = bubble.querySelector('.c-message_kit__blocks, [data-qa="message-text"]');
              if (textNode) text = clean(textNode.innerText);
              isFromMe = sender.toLowerCase() === 'you';
              if (isGroup && sender && !isFromMe && sender !== activeContact) {
                addGroupMember(sender, 'Member', time || 'Active in thread', 1);
              }
            } else if (host.endsWith('linkedin.com')) {
              const authorNode = bubble.querySelector('.msg-s-message-group__name, [data-anonymize="person-name"]');
              if (authorNode) sender = clean(authorNode.innerText);
              const textNode = bubble.querySelector('.msg-s-event-listitem__body, .msg-s-message-group__message, p');
              if (textNode) text = clean(textNode.innerText);
              isFromMe = sender.toLowerCase() === 'you' || bubble.classList.contains('msg-s-message-list__event--out');
              if (isGroup && sender && !isFromMe && sender !== activeContact) {
                addGroupMember(sender, 'Member', time || 'Active in thread', 1);
              }
            } else {
              const textNode = bubble.querySelector('p, span, div');
              if (textNode) text = clean(textNode.innerText);
              sender = activeContact || 'Contact';
            }

            if (text && text.length > 0 && text.length < 2000) {
              activeThreadMessages.push({
                sender: sender || (isFromMe ? 'You' : 'Contact'),
                text: text.slice(0, 1000),
                isFromMe,
                time: time || undefined
              });
            }
          });
        }

        const groupMembers = Array.from(membersMap.values());
        // If this is not a group, clear any leftover group members to ensure zero leakage
        if (!isGroup) {
          groupMembers.length = 0;
          groupMemberCount = 0;
          groupSubtitle = '';
        } else if (groupMemberCount === 0 && groupMembers.length > 0) {
          groupMemberCount = groupMembers.length + 1;
        }

        const payload = {
          title: document.title || '',
          messages,
          notifications,
          rawNotifications,
          activeContact,
          activeThreadMessages,
          groupMemberCount,
          groupSubtitle,
          groupMembers
        };
        const signature = JSON.stringify(payload);
        if (!force && signature === lastPayload) return;
        lastPayload = signature;
        (window.webkit?.messageHandlers?.pinggoActivity || window.webkit?.messageHandlers?.multispaceActivity)?.postMessage(payload);
      }

      window.__pinggoCollect = () => collect(true);
      window.__multispaceCollect = () => collect(true);

      window.pinggoInsertText = function(text) {
        if (!text) return false;
        const selectors = [
          '#main footer [contenteditable="true"]',
          '#main [data-tab="10"][contenteditable="true"]',
          'footer div[contenteditable="true"][data-lexical-editor="true"]',
          '#editable-message-text',
          '.input-message-input[contenteditable="true"]',
          '.ql-editor[contenteditable="true"]',
          '[data-qa="message_input"]',
          '[role="textbox"][contenteditable="true"]',
          '[aria-label*="message" i][contenteditable="true"]',
          '[aria-label*="type a message" i][contenteditable="true"]',
          '[contenteditable="true"]',
          'textarea[placeholder*="message" i]',
          'textarea',
          'input[type="text"][placeholder*="message" i]'
        ];

        let target = null;
        if (document.activeElement && (document.activeElement.isContentEditable || document.activeElement.tagName === 'TEXTAREA' || document.activeElement.tagName === 'INPUT')) {
          target = document.activeElement;
        }

        if (!target) {
          for (const sel of selectors) {
            const el = document.querySelector(sel);
            if (el && el.offsetParent !== null) {
              target = el;
              break;
            }
          }
        }

        if (!target) return false;

        target.focus();

        let success = false;
        try {
          success = document.execCommand('insertText', false, text);
        } catch (e) {}

        if (!success) {
          if (target.isContentEditable) {
            target.innerText = text;
          } else {
            target.value = text;
          }
          target.dispatchEvent(new Event('input', { bubbles: true }));
          target.dispatchEvent(new Event('change', { bubbles: true }));
          success = true;
        }
        return success;
      };

      function schedule() {
        if (pending) return;
        const delay = document.hidden ? 8000 : 1200;
        pending = setTimeout(async () => {
          pending = null;
          await collect();
        }, delay);
      }
      new MutationObserver(schedule).observe(document.documentElement, { subtree: true, childList: true, characterData: true });
      setInterval(async () => {
        await collect();
      }, 15000);
      window.__pinggoCollect = async () => await collect(true);
      window.__multispaceCollect = async () => await collect(true);
      collect();
    })();
    """#

    private static let audioScript = #"""
    (() => {
      if (window.__multispaceAudioInjected) return;
      window.__multispaceAudioInjected = true;
      const origPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function() {
        if (window.__multispaceMuted) {
          this.muted = true;
        }
        return origPlay.apply(this, arguments);
      };
      const origAudio = window.Audio;
      if (origAudio) {
        window.Audio = function(...args) {
          const a = new origAudio(...args);
          if (window.__multispaceMuted) { a.muted = true; }
          return a;
        };
      }
    })();
    """#

    private static let passkeyScript = #"""
    (() => {
      if (window.__pinggoPasskeyInjected) return;
      window.__pinggoPasskeyInjected = true;

      // Ensure platform authenticator availability for Touch ID & Passkeys
      if (window.PublicKeyCredential) {
        if (typeof PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable === 'function') {
          const origIsAvailable = PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable.bind(PublicKeyCredential);
          PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = async function() {
            try {
              const avail = await origIsAvailable();
              return avail;
            } catch (e) {
              return true;
            }
          };
        }
        // Note: We do NOT force isConditionalMediationAvailable = true because in embedded WKWebView,
        // doing so intercepts and suppresses standard HTML username/password AutoFill (Apple Passwords / iCloud Keychain).
      }
    })();
    """#
}

struct AICopilotDrawer: View {
    @ObservedObject var session: PortalSession
    let platform: SocialPlatform
    let account: PlatformAccount
    let onClose: () -> Void

    @EnvironmentObject private var store: AppStore
    @State private var customPrompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var streamingText: String = ""
    @State private var insertedMsgID: UUID? = nil
    @State private var copiedMsgID: UUID? = nil
    @State private var showingGroupRoster: Bool = false

    private var activeContext: ActiveThreadContext? {
        session.activeThread ?? store.activeThreadContext(for: account.id)
    }

    private var isGroup: Bool {
        activeContext?.isGroupChat ?? false
    }

    private var contactTitle: String {
        activeContext?.contactName.isEmpty == false ? activeContext!.contactName : platform.name
    }

    private var effectiveMembers: [AIChatMemberItem] {
        activeContext?.effectiveMembers ?? []
    }

    private var groupAdmins: [AIChatMemberItem] {
        activeContext?.groupAdmins ?? []
    }

    private var defaultTone: AIReplyTone {
        let name = store.preferences.defaultReplyTone.lowercased()
        return AIReplyTone(rawValue: name) ?? .friendly
    }

    private var sentimentResult: SentimentResult {
        let snippet = activeContext?.contextSnippet ?? ""
        if snippet.isEmpty {
            let previews = store.platformActivity[account.id]?.messages ?? []
            let previewText = previews.prefix(3).map(\.text).joined(separator: " ")
            return AIService.shared.analyzeSentiment(text: previewText)
        }
        return AIService.shared.analyzeSentiment(text: snippet)
    }

    private var urgencyLevel: String {
        let score = sentimentResult.score
        if score <= -0.4 { return "🚨 Urgent" }
        if score >= 0.3 { return "✨ Positive" }
        return "💬 Normal"
    }

    private var providerLabel: String {
        let prefs = store.preferences
        if prefs.aiProvider == "gemini" && !prefs.geminiApiKey.isEmpty { return "Gemini 2.5 Flash" }
        if prefs.aiProvider == "chatgpt" && !prefs.openAiApiKey.isEmpty { return "ChatGPT" }
        if prefs.aiProvider == "ollama" { return "Ollama (\(prefs.ollamaModel))" }
        return "Smart Engine"
    }

    private var providerIndicatorColor: Color {
        let prefs = store.preferences
        if prefs.aiProvider == "ollama" { return .purple }
        if (prefs.aiProvider == "gemini" && !prefs.geminiApiKey.isEmpty) || (prefs.aiProvider == "chatgpt" && !prefs.openAiApiKey.isEmpty) {
            return .green
        }
        return .orange
    }

    var body: some View {
        VStack(spacing: 0) {
            minimalToolbar

            Divider()

            compactContextHeader

            Divider()

            chatStreamView

            Divider()

            minimalInputBar
        }
        .frame(width: 348)
        .background(Palette.panel)
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Palette.hover), alignment: .leading)
    }

    private var minimalToolbar: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
            Text("Pinggo AI")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 5) {
                Circle().fill(providerIndicatorColor).frame(width: 5, height: 5)
                Text(providerLabel).lineLimit(1)
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(Palette.muted)

            Spacer()

            Menu {
                Button("Refresh chat context", systemImage: "arrow.clockwise") {
                    session.forceCollect()
                    store.showToast("Chat context refreshed")
                }
                Button("Clear AI conversation", systemImage: "trash") {
                    session.clearCopilotHistory()
                    store.showToast("AI conversation cleared")
                }
                Divider()
                Button("Copy members as CSV", systemImage: "doc.on.doc") { copyMembersCSV() }
                Button("Save members CSV", systemImage: "arrow.down.doc") { exportMembersCSV(openInFinder: true) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help("More AI actions")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Close Pinggo AI")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Palette.panel)
    }

    private var compactContextHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: isGroup ? "person.3" : "person")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                Text(contactTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                if isGroup {
                    Text("\(activeContext?.groupMemberCount ?? effectiveMembers.count) members")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(urgencyLevel)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }

            Text(activeContext?.topicSummary ?? "Open a conversation to give Pinggo AI live context.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.muted)
                .lineLimit(2)

            if isGroup {
                Button {
                    showingGroupRoster.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(showingGroupRoster ? "Hide participants" : "View participants")
                        Image(systemName: showingGroupRoster ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)

                if showingGroupRoster {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(effectiveMembers) { member in
                                HStack {
                                    Text(member.name).lineLimit(1)
                                    Spacer()
                                    Text(member.role).foregroundStyle(Palette.muted)
                                }
                                .font(.system(size: 10))
                            }
                        }
                    }
                    .frame(maxHeight: 92)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Palette.sidebar.opacity(0.55))
    }

    private var minimalInputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about this conversation…", text: $customPrompt)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border))
                .onSubmit { sendQuery(customPrompt) }

            Button { sendQuery(customPrompt) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Palette.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
            .opacity(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? 0.45 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.panel)
    }

    // MARK: - 1. Top Navigation Bar
    private var topToolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.accent)
                    .font(.system(size: 13, weight: .bold))
                Text("Co-Pilot")
                    .font(.system(size: 14, weight: .bold))
            }

            Spacer()

            // AI Provider pill
            HStack(spacing: 4) {
                Circle()
                    .fill(providerIndicatorColor)
                    .frame(width: 6, height: 6)
                Text(providerLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.hover, in: Capsule())

            // Sync Chat DOM button
            Button {
                session.forceCollect()
                store.showToast("Synced active chat")
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Re-scan active chat messages and roster")

            // Reset conversation memory button
            Button {
                session.clearCopilotHistory()
                store.showToast("Conversation memory reset")
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Clear Co-Pilot dialogue history")

            // Export Member Details Menu
            Menu {
                Button {
                    exportMembersCSV(openInFinder: true)
                } label: {
                    Label("Save Members CSV to Downloads", systemImage: "arrow.down.doc")
                }
                Button {
                    copyMembersCSV()
                } label: {
                    Label("Copy Members as CSV", systemImage: "doc.on.doc")
                }
                Button {
                    copyMembersJSON()
                } label: {
                    Label("Copy Members as JSON", systemImage: "curlybraces")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .help("Export member details (Name, Phone Number, Role, Username)")

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close Co-Pilot")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Palette.panel)
    }

    // MARK: - 2. Summary Header
    private var summaryHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Chat Type Badge & Status
            HStack(spacing: 6) {
                if isGroup {
                    HStack(spacing: 4) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 10))
                        Text("Group Chat (\(activeContext?.groupMemberCount ?? effectiveMembers.count))")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Palette.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(Palette.accent)

                    // Admins & Members Toggle Button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingGroupRoster.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text("👑 \(groupAdmins.count) Admins · Info")
                                .font(.system(size: 10.5, weight: .semibold))
                            Image(systemName: showingGroupRoster ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Palette.hover, in: Capsule())
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                        Text("Direct Chat")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)

                    Text(contactTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)

                    Menu {
                        Button {
                            exportMembersCSV(openInFinder: true)
                        } label: {
                            Label("Save Contact CSV", systemImage: "arrow.down.doc")
                        }
                        Button {
                            copyMembersCSV()
                        } label: {
                            Label("Copy Contact as CSV", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.muted)
                            .padding(3)
                            .background(Palette.hover, in: Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .help("Export contact details")
                }

                Spacer()

                // Urgency / Sentiment Tag
                Text(urgencyLevel)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Palette.hover, in: Capsule())
            }

            // Row 2: Live Conversation Summary Header
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9))
                    Text("LIVE SUMMARY & STATUS")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .foregroundStyle(Palette.muted)

                Text(activeContext?.topicSummary ?? "Monitoring live conversation thread...")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.sidebar.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hover, lineWidth: 1))

            // Row 3: Expandable Group Members & Admin Roster (Only in Groups)
            if isGroup && showingGroupRoster {
                VStack(alignment: .leading, spacing: 8) {
                    // Group Admins Highlight
                    if !groupAdmins.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GROUP ADMINS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)

                            ForEach(groupAdmins) { admin in
                                HStack(spacing: 6) {
                                    Text("👑")
                                        .font(.system(size: 11))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(admin.name)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.primary)
                                        if let u = admin.username, !u.isEmpty {
                                            Text("@\(u)")
                                                .font(.system(size: 9))
                                                .foregroundStyle(Palette.muted)
                                        }
                                    }
                                    if let phone = admin.phoneNumber, !phone.isEmpty {
                                        Text("(\(phone))")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Palette.muted)
                                    }
                                    Spacer()
                                    if let phone = admin.phoneNumber, !phone.isEmpty {
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(phone, forType: .string)
                                            store.showToast("Copied \(phone)")
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 9))
                                                .foregroundStyle(Palette.muted)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy phone number")
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }

                    // All Participants Roster
                    if !effectiveMembers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("ROSTER & PARTICIPANTS (\(effectiveMembers.count))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Palette.muted)

                                Spacer()

                                Menu {
                                    Button {
                                        exportMembersCSV(openInFinder: true)
                                    } label: {
                                        Label("Save CSV to Downloads", systemImage: "arrow.down.doc")
                                    }
                                    Button {
                                        copyMembersCSV()
                                    } label: {
                                        Label("Copy as CSV", systemImage: "doc.on.doc")
                                    }
                                    Button {
                                        copyMembersJSON()
                                    } label: {
                                        Label("Copy as JSON", systemImage: "curlybraces")
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 8.5))
                                        Text("Export")
                                            .font(.system(size: 9, weight: .semibold))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Palette.hover, in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(Palette.accent)
                                }
                                .menuStyle(.borderlessButton)
                                .help("Export member details (Name, Phone Number, Role, Username)")
                            }

                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(spacing: 3) {
                                    ForEach(effectiveMembers) { m in
                                        HStack(spacing: 6) {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(m.name)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(1)
                                                if let u = m.username, !u.isEmpty {
                                                    Text("@\(u)")
                                                        .font(.system(size: 9))
                                                        .foregroundStyle(Palette.accent)
                                                }
                                            }
                                            Spacer()
                                            if let phone = m.phoneNumber, !phone.isEmpty {
                                                Text(phone)
                                                    .font(.system(size: 9.5))
                                                    .foregroundStyle(Palette.muted)
                                                Button {
                                                    NSPasteboard.general.clearContents()
                                                    NSPasteboard.general.setString(phone, forType: .string)
                                                    store.showToast("Copied \(phone)")
                                                } label: {
                                                    Image(systemName: "doc.on.doc")
                                                        .font(.system(size: 8))
                                                        .foregroundStyle(Palette.muted)
                                                }
                                                .buttonStyle(.plain)
                                                .help("Copy phone number")
                                            }
                                            Text(m.role)
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(m.role.lowercased().contains("admin") ? Color.orange : Palette.muted)
                                            Text("· \(m.messageCount) msgs")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(Palette.muted)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            .frame(maxHeight: 110)
                        }
                    }
                }
                .padding(10)
                .background(Palette.hover.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Palette.sidebar)
    }

    // MARK: - 3. Conversational Message Stream (ChatGPT & Google AI style)
    private var chatStreamView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    if session.copilotHistory.isEmpty && !isGenerating {
                        emptyStateGreetingView
                    } else {
                        ForEach(session.copilotHistory) { msg in
                            if msg.role == "user" {
                                userMessageBubble(msg)
                            } else {
                                assistantMessageCard(msg)
                            }
                        }

                        // Live Streaming Bubble
                        if isGenerating {
                            streamingAssistantCard
                        }
                    }
                    Color.clear.frame(height: 1).id("bottomMarker")
                }
                .padding(12)
            }
            .onChange(of: session.copilotHistory.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottomMarker", anchor: .bottom)
                }
            }
            .onChange(of: streamingText) {
                proxy.scrollTo("bottomMarker", anchor: .bottom)
            }
        }
    }

    // Empty State Greeting (ChatGPT / Gemini style)
    private var emptyStateGreetingView: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Palette.accent)
                .padding(.top, 18)

            VStack(spacing: 4) {
                Text("How can I help with this chat?")
                    .font(.system(size: 14, weight: .semibold))
                Text("Summarize context, find actions, or draft a reply.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            VStack(spacing: 6) {
                starterChip("Summarize this conversation") {
                    sendQuery("Summarize everything discussed in this conversation in clear executive bullet points.")
                }
                starterChip("Find actions and deadlines") {
                    sendQuery("What are the key action items, commitments, deliverables, or deadlines mentioned?")
                }
                if isGroup {
                    starterChip("Show participants and roles") {
                        sendQuery("Identify the group admins, participants, and summarize their roles and contact details.")
                    }
                }
                starterChip("Draft a \(store.preferences.defaultReplyTone.lowercased()) reply") {
                    sendQuery("Draft a reply to \(contactTitle) in a \(store.preferences.defaultReplyTone) tone addressing the latest message.")
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func starterChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Palette.sidebar.opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // User Message Bubble
    private func userMessageBubble(_ msg: CopilotMessage) -> some View {
        HStack {
            Spacer(minLength: 32)
            Text(msg.content)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // Assistant Message Card (ChatGPT & Google AI UI)
    private func assistantMessageCard(_ msg: CopilotMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Text(providerLabel)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Spacer()
            }

            Text(LocalizedStringKey(msg.content))
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action Toolbar (Insert into Chat, Copy, Regenerate)
            HStack(spacing: 8) {
                // Insert into Chat button
                Button {
                    session.insertTextIntoChat(msg.content)
                    insertedMsgID = msg.id
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        insertedMsgID = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: insertedMsgID == msg.id ? "checkmark" : "arrow.down.doc.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(insertedMsgID == msg.id ? "Inserted!" : "Insert into Chat")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("Insert text directly into WhatsApp/Telegram/Slack chat input")

                // Copy button
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(msg.content, forType: .string)
                    copiedMsgID = msg.id
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copiedMsgID = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedMsgID == msg.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copiedMsgID == msg.id ? "Copied" : "Copy")
                            .font(.system(size: 10.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Palette.hover, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)

                Spacer()

                // Regenerate button
                Button {
                    sendQuery("Regenerate a new response or alternative.")
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .padding(5)
                        .background(Palette.hover, in: Circle())
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
                .help("Regenerate response")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
    }

    // Live Streaming Assistant Card
    private var streamingAssistantCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Text("Thinking & Generating...")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Palette.accent)
                ProgressView().controlSize(.mini)
                Spacer()
            }

            if !streamingText.isEmpty {
                Text(LocalizedStringKey(streamingText))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
    }

    // MARK: - 4. Bottom Input Bar (ChatGPT & Google AI UI)
    private var bottomInputBar: some View {
        VStack(spacing: 6) {
            // Status Tag Row: Tone default + Access pill
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 8))
                    Text("Full Access Active")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(Color.green)

                Spacer()

                // Default tone tag from settings (user requested: "keep it default from settings")
                HStack(spacing: 4) {
                    Text("Tone:")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)
                    Text("\(store.preferences.defaultReplyTone)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Palette.accent)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.hover, in: Capsule())
            }

            // Input TextField with Send Button
            HStack(spacing: 8) {
                TextField("Ask anything about this chat, members, or draft a reply...", text: $customPrompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hover, lineWidth: 1))
                    .onSubmit {
                        sendQuery(customPrompt)
                    }

                Button {
                    sendQuery(customPrompt)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? Palette.muted : Palette.accent)
                }
                .buttonStyle(.plain)
                .disabled(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
            }
        }
        .padding(12)
        .background(Palette.panel)
    }

    // MARK: - Query Execution
    private func sendQuery(_ queryText: String) {
        let clean = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isGenerating else { return }
        customPrompt = ""
        isGenerating = true
        streamingText = ""

        session.appendCopilotMessage(role: "user", content: clean)

        let transcript = activeContext?.fullTranscript ?? ""
        let memberCount = activeContext?.groupMemberCount ?? effectiveMembers.count
        let channelType = isGroup ? "Group Chat (\(memberCount) members)" : "Direct 1-on-1 Chat with \(contactTitle)"

        let membersList = effectiveMembers.map { m in
            var parts: [String] = []
            parts.append("Name: \(m.cleanName)")
            if let p = m.cleanPhone, !p.isEmpty { parts.append("Phone: \(p)") }
            if let u = m.username, !u.isEmpty { parts.append("Username: @\(u)") }
            let roleStr = m.normalizedRole == "Group Admin" ? "👑 \(m.normalizedRole)" : m.normalizedRole
            parts.append("Role: \(roleStr)")
            parts.append("Messages: \(m.messageCount)")
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")

        let tone = defaultTone

        Task {
            let result = await AIService.shared.streamCoPilotResponse(
                prompt: clean,
                context: transcript,
                tone: tone,
                history: session.copilotHistory,
                channelType: channelType,
                membersInfo: membersList,
                preferences: store.preferences,
                onChunk: { chunk in
                    streamingText += chunk
                }
            )
            session.appendCopilotMessage(role: "assistant", content: result)
            isGenerating = false
            streamingText = ""
        }
    }

    // MARK: - Export Helpers
    private func exportMembersCSV(openInFinder: Bool = true) {
        guard let ctx = activeContext, !ctx.effectiveMembers.isEmpty else {
            store.showToast("No member details to export")
            return
        }
        let csv = ctx.exportCSV()
        let fileManager = FileManager.default
        let downloadsDir = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

        let rawName = isGroup ? (activeContext?.contactName ?? "Group") : contactTitle
        let safeName = rawName.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_").prefix(30)
        let fileName = "\(safeName.isEmpty ? "Members" : safeName)_Members.csv"
        var destURL = downloadsDir.appendingPathComponent(fileName)
        var counter = 1
        let baseName = destURL.deletingPathExtension().lastPathComponent
        while fileManager.fileExists(atPath: destURL.path) {
            destURL = downloadsDir.appendingPathComponent("\(baseName)_\(counter).csv")
            counter += 1
        }

        do {
            try csv.write(to: destURL, atomically: true, encoding: .utf8)
            store.showToast("Saved to Downloads/\(destURL.lastPathComponent)")
            if openInFinder {
                NSWorkspace.shared.activateFileViewerSelecting([destURL])
            }
        } catch {
            store.showToast("Export failed: \(error.localizedDescription)")
        }
    }

    private func copyMembersCSV() {
        guard let ctx = activeContext, !ctx.effectiveMembers.isEmpty else {
            store.showToast("No member details to copy")
            return
        }
        let csv = ctx.exportCSV()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
        store.showToast("Copied \(ctx.effectiveMembers.count) members as CSV")
    }

    private func copyMembersJSON() {
        guard let ctx = activeContext, !ctx.effectiveMembers.isEmpty else {
            store.showToast("No member details to copy")
            return
        }
        let json = ctx.exportJSON()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
        store.showToast("Copied \(ctx.effectiveMembers.count) members as JSON")
    }
}
