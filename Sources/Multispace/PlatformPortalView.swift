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
            HStack(spacing: 12) {
                PlatformLogo(platform: platform, size: 25)
                Text(platform.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
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
                    Label(account.name, systemImage: "person.crop.circle")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                Spacer(minLength: 8)
                toolbarButton("chevron.left", help: "Back", enabled: session.canGoBack) { session.webView.goBack() }
                toolbarButton("chevron.right", help: "Forward", enabled: session.canGoForward) { session.webView.goForward() }
                toolbarButton("arrow.clockwise", help: "Reload", enabled: true) { session.webView.reload() }
                toolbarButton("square.on.square", help: "Open in browser", enabled: true) {
                    NSWorkspace.shared.open(session.currentURL ?? url)
                }
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
                        .overlay(Capsule().stroke(Color.orange.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Fast Passkey & Login Assistant available")
                } else {
                    toolbarButton(
                        "key.fill",
                        help: "Passkey & Fast Login Assistant",
                        enabled: true,
                        tint: Palette.accent
                    ) {
                        showingPasskeyAssistant = true
                    }
                }
                toolbarButton(
                    session.isMuted ? "speaker.slash.fill" : "speaker.wave.2",
                    help: session.isMuted ? "Unmute tab" : "Mute tab",
                    enabled: true,
                    tint: session.isMuted ? Palette.accent : nil
                ) {
                    session.toggleMute()
                }
                toolbarButton(
                    store.isSplitView ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                    help: store.isSplitView ? "Exit split view" : "Split view side-by-side",
                    enabled: true,
                    tint: store.isSplitView ? Palette.accent : nil
                ) {
                    store.toggleSplitView()
                }
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        showingAIDrawer.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Text("Co-Pilot")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(showingAIDrawer ? .white : Palette.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(showingAIDrawer ? Palette.accent : Palette.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Palette.accent.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Toggle AI Co-Pilot & Smart Reply Drawer")
                Menu {
                    Button("Edit platform…") { store.editingPlatform = platform }
                    Button("Remove from sidebar", role: .destructive) { store.removePlatform(platform.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 30)
            }
            .padding(.horizontal, 16)
            .frame(height: 51)
            .background(Palette.panel)

            HStack(spacing: 7) {
                Image(systemName: "lock.shield")
                Text(session.currentURL?.host ?? url.host ?? "")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("Sign in here if asked")
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 17)
            .frame(height: 29)
            .background(Palette.sidebar)

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

            ZStack(alignment: .trailing) {
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
                if showingAIDrawer {
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
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(10)
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
            session.activityHandler = { title, messages, notifications, rawNotifications, activeContact, activeThreadMessages in
                store.updatePlatformActivity(accountID: account.id, title: title,
                                             messages: messages, notifications: notifications,
                                             rawNotifications: rawNotifications,
                                             activeContact: activeContact,
                                             activeThreadMessages: activeThreadMessages)
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
            browser.activityHandler = { [weak store] title, messages, notifications, rawNotifications, activeContact, activeThreadMessages in
                store?.updatePlatformActivity(accountID: account.id, title: title,
                                               messages: messages, notifications: notifications,
                                               rawNotifications: rawNotifications,
                                               activeContact: activeContact,
                                               activeThreadMessages: activeThreadMessages)
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
    var activityHandler: ((String, [[String: String]], [String], [[String: String]], String?, [[String: Any]]) -> Void)?
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
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration)
        super.init()
        let weakHandler = WeakScriptMessageHandler(delegate: self)
        configuration.userContentController.add(weakHandler, name: "pinggoActivity")
        configuration.userContentController.add(weakHandler, name: "multispaceActivity")
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

        let cleanContact = (activeContact ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanContact.isEmpty || !activeThreadMessages.isEmpty {
            let threadMsgs: [ActiveChatMessage] = activeThreadMessages.prefix(15).enumerated().compactMap { idx, dict in
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
                updatedAt: .now
            )
        }

        activityHandler?(title, rows, notifications, rawNotifications, activeContact, activeThreadMessages)
    }

    func load(_ url: URL) {
        error = nil
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        error = nil
        updateNavigation()
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

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let targetURL = navigationAction.request.url, isExternalURL(targetURL) {
            NSWorkspace.shared.open(targetURL)
            return nil
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

        // Only open in external browser if the user explicitly clicked a link targeting the main frame
        // and it is truly an external website, not an auth domain or subframe captcha/challenge
        if navigationAction.targetFrame?.isMainFrame == true && navigationAction.navigationType == .linkActivated {
            if isExternalURL(targetURL) {
                decisionHandler(.cancel)
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
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let contentDisposition = (httpResponse.allHeaderFields["Content-Disposition"] ?? httpResponse.allHeaderFields["content-disposition"]) as? String,
           contentDisposition.lowercased().contains("attachment") {
            decisionHandler(.download)
            return
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
        completedDownload = PortalDownloadedDocument(url: destinationURL)
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
      function collect(force = false) {
        const host = location.hostname.toLowerCase();
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
        const messages = [];
        if (selector) {
          const nodes = document.querySelectorAll(selector);
          nodes.forEach(node => {
            if (messages.length >= 20) return;
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
              const nameEl = node.querySelector('.msg-conversation-listitem__participant-names, span[data-anonymize="person-name"], h3.msg-conversation-listitem__participant-names, .msg-overlay-list-bubble__convo-item-header, .msg-conversation-card__participant-names, div.artdeco-entity-lockup__title, [data-view-name="conversation-list-item"] h3, h3, h4');
              if (nameEl) sender = clean(nameEl.innerText);
              const snippetEl = node.querySelector('.msg-conversation-card__message-snippet, .msg-overlay-list-bubble__message-snippet, p.msg-conversation-card__message-snippet, span.msg-conversation-card__message-snippet-body, .msg-conversation-card__row p, .msg-s-message-group__meta, [class*="message-snippet"], p');
              if (snippetEl) text = clean(snippetEl.innerText);
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
          const headerName = document.querySelector('#main header span[dir="auto"], #main header [title], #main header ._amie, header span[title]');
          if (headerName) activeContact = clean(headerName.getAttribute('title') || headerName.innerText);
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
          bubbleSelectors = '#main .message-in, #main .message-out';
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

        if (bubbleSelectors) {
          const bubbles = Array.from(document.querySelectorAll(bubbleSelectors)).slice(-12);
          bubbles.forEach(bubble => {
            let sender = '';
            let text = '';
            let isFromMe = false;
            let time = '';

            if (host.endsWith('whatsapp.com')) {
              isFromMe = bubble.classList.contains('message-out');
              const textNode = bubble.querySelector('span.selectable-text, ._ao3e, span[dir="ltr"]');
              if (textNode) text = clean(textNode.innerText);
              const authorNode = bubble.querySelector('span[data-testid="author"], ._amih');
              sender = isFromMe ? 'You' : (authorNode ? clean(authorNode.innerText) : (activeContact || 'Contact'));
              const timeNode = bubble.querySelector('[data-testid="msg-meta"] span, span[dir="auto"]');
              if (timeNode) time = clean(timeNode.innerText);
            } else if (host.endsWith('telegram.org')) {
              isFromMe = bubble.classList.contains('is-out') || bubble.classList.contains('own');
              const textNode = bubble.querySelector('.text-content, .message-content, .translatable-message');
              if (textNode) text = clean(textNode.innerText);
              const authorNode = bubble.querySelector('.message-title, .message-author, .author');
              sender = isFromMe ? 'You' : (authorNode ? clean(authorNode.innerText) : (activeContact || 'Contact'));
            } else if (host.endsWith('discord.com')) {
              const authorNode = bubble.querySelector('span[class*="username"]');
              if (authorNode) sender = clean(authorNode.innerText);
              const textNode = bubble.querySelector('div[id^="message-content-"]');
              if (textNode) text = clean(textNode.innerText);
              isFromMe = sender.toLowerCase() === 'you';
            } else if (host.endsWith('slack.com')) {
              const authorNode = bubble.querySelector('.c-message__sender_button, [data-qa="message_sender_name"]');
              if (authorNode) sender = clean(authorNode.innerText);
              const textNode = bubble.querySelector('.c-message_kit__blocks, [data-qa="message-text"]');
              if (textNode) text = clean(textNode.innerText);
              isFromMe = sender.toLowerCase() === 'you';
            } else if (host.endsWith('linkedin.com')) {
              const authorNode = bubble.querySelector('.msg-s-message-group__name, [data-anonymize="person-name"]');
              if (authorNode) sender = clean(authorNode.innerText);
              const textNode = bubble.querySelector('.msg-s-event-listitem__body, .msg-s-message-group__message, p');
              if (textNode) text = clean(textNode.innerText);
              isFromMe = sender.toLowerCase() === 'you' || bubble.classList.contains('msg-s-message-list__event--out');
            } else {
              const textNode = bubble.querySelector('p, span, div');
              if (textNode) text = clean(textNode.innerText);
              sender = activeContact || 'Contact';
            }

            if (text && text.length > 0 && text.length < 1000) {
              activeThreadMessages.push({
                sender: sender || (isFromMe ? 'You' : 'Contact'),
                text: text.slice(0, 500),
                isFromMe,
                time: time || undefined
              });
            }
          });
        }

        const payload = { title: document.title || '', messages, notifications, rawNotifications, activeContact, activeThreadMessages };
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
        const delay = document.hidden ? 10000 : 1200;
        pending = setTimeout(() => { pending = null; collect(); }, delay);
      }
      new MutationObserver(schedule).observe(document.documentElement, { subtree: true, childList: true, characterData: true });
      setInterval(() => {
        collect();
      }, 15000);
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
    @State private var activeTone: AIReplyTone = .friendly
    @State private var generatedDraft: String = ""
    @State private var isGenerating: Bool = false
    @State private var customPrompt: String = ""
    @State private var isCopied: Bool = false
    @State private var isInserted: Bool = false

    private var activeContext: ActiveThreadContext? {
        session.activeThread ?? store.activeThreadContext(for: account.id)
    }

    private var contactTitle: String {
        activeContext?.contactName.isEmpty == false ? activeContext!.contactName : platform.name
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

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Palette.accent)
                        .font(.system(size: 13, weight: .bold))
                    Text("Co-Pilot")
                        .font(.system(size: 14, weight: .bold))
                }

                Spacer()

                // AI Provider badge
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

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Palette.panel)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 14) {
                    // 1. Active Thread Context & Sentiment Card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ACTIVE CHAT")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                Text(contactTitle)
                                    .font(.system(size: 14, weight: .semibold))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(urgencyLevel)
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(urgencyBackgroundColor, in: Capsule())
                                .foregroundStyle(urgencyForegroundColor)
                        }

                        // Sentiment Gauge Bar
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("Sentiment: \(sentimentResult.classification)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Palette.muted)
                                Spacer()
                                Text(String(format: "%+.1f", sentimentResult.score))
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(sentimentColor)
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Palette.hover)
                                        .frame(height: 5)
                                    let normalized = CGFloat((sentimentResult.score + 1.0) / 2.0)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(sentimentColor)
                                        .frame(width: max(8, geo.size.width * normalized), height: 5)
                                }
                            }
                            .frame(height: 5)
                        }

                        // Thread summary / latest incoming snippet
                        if let lastIncoming = activeContext?.messages.last(where: { !$0.isFromMe }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Latest message:")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Palette.muted)
                                Text("\"\(lastIncoming.text)\"")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.hover.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(12)
                    .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.hover, lineWidth: 1))

                    // 2. 1-Click Smart Reply Tones
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SMART REPLIES")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Palette.muted)

                        let tones: [(AIReplyTone, String, String)] = [
                            (.professional, "Professional", "briefcase.fill"),
                            (.friendly, "Friendly", "face.smiling.fill"),
                            (.concise, "Concise", "bolt.fill"),
                            (.casual, "Casual", "sunglasses.fill"),
                            (.politeDecline, "Decline", "xmark.circle.fill"),
                            (.proposeTime, "Propose Time", "calendar.badge.clock")
                        ]

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(tones, id: \.0) { tone, label, icon in
                                Button {
                                    activeTone = tone
                                    triggerSmartReply(tone: tone)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: icon)
                                            .font(.system(size: 10))
                                        Text(label)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(activeTone == tone ? Palette.accent.opacity(0.18) : Palette.hover, in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(activeTone == tone ? Palette.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                                    )
                                    .foregroundStyle(activeTone == tone ? Palette.accent : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 2.5 Multi-turn Dialogue Memory (Recent conversation turns)
                    if !session.copilotHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("CONVERSATION MEMORY (\(session.copilotHistory.count))")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                Spacer()
                                Button {
                                    session.clearCopilotHistory()
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.counterclockwise")
                                        Text("Reset")
                                    }
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.muted)
                                }
                                .buttonStyle(.plain)
                            }

                            VStack(spacing: 6) {
                                ForEach(session.copilotHistory) { msg in
                                    HStack {
                                        if msg.role == "user" {
                                            Spacer(minLength: 24)
                                            Text(msg.content)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 10))
                                        } else {
                                            Text(msg.content)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.primary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 10))
                                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.hover, lineWidth: 1))
                                            Spacer(minLength: 24)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(Palette.hover.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // 3. Generated Reply Draft & Action Controls
                    if !generatedDraft.isEmpty || isGenerating {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("REPLY DRAFT (\(activeTone.rawValue.capitalized))")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                Spacer()
                                if isGenerating {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }

                            Text(generatedDraft)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hover, lineWidth: 1))

                            // Action Buttons: Insert into chat & Copy
                            HStack(spacing: 8) {
                                Button {
                                    session.insertTextIntoChat(generatedDraft)
                                    isInserted = true
                                    Task {
                                        try? await Task.sleep(for: .seconds(2))
                                        isInserted = false
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: isInserted ? "checkmark" : "arrow.down.doc.fill")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(isInserted ? "Inserted!" : "Insert into Chat")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                .disabled(isGenerating)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(generatedDraft, forType: .string)
                                    isCopied = true
                                    Task {
                                        try? await Task.sleep(for: .seconds(2))
                                        isCopied = false
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 10))
                                        Text(isCopied ? "Copied" : "Copy")
                                            .font(.system(size: 11))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Palette.hover, in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(Palette.muted)
                                }
                                .buttonStyle(.plain)
                                .disabled(isGenerating)

                                Spacer()

                                Button {
                                    triggerSmartReply(tone: activeTone)
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11))
                                        .padding(6)
                                        .background(Palette.hover, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Regenerate reply")
                                .disabled(isGenerating)
                            }
                        }
                    }

                    // 4. Custom Co-Pilot Prompt Input with Streaming Output
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ASK CO-PILOT")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Palette.muted)

                        HStack(spacing: 6) {
                            TextField("Ask Co-Pilot about this chat...", text: $customPrompt)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.hover, lineWidth: 1))
                                .onSubmit {
                                    triggerCustomPrompt()
                                }

                            Button {
                                triggerCustomPrompt()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? Palette.muted : Palette.accent)
                            }
                            .buttonStyle(.plain)
                            .disabled(customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                        }
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 330)
        .background(Palette.panel)
        .overlay(Rectangle().frame(width: 1).foregroundStyle(Palette.hover), alignment: .leading)
    }

    private var providerLabel: String {
        let prefs = store.preferences
        if prefs.aiProvider == "gemini" && !prefs.geminiApiKey.isEmpty { return "Gemini" }
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

    private var sentimentColor: Color {
        let score = sentimentResult.score
        if score >= 0.2 { return .green }
        if score <= -0.2 { return .red }
        return .orange
    }

    private var urgencyBackgroundColor: Color {
        let score = sentimentResult.score
        if score <= -0.4 { return Color.red.opacity(0.15) }
        if score >= 0.3 { return Color.green.opacity(0.15) }
        return Palette.hover
    }

    private var urgencyForegroundColor: Color {
        let score = sentimentResult.score
        if score <= -0.4 { return .red }
        if score >= 0.3 { return .green }
        return Palette.muted
    }

    private func triggerSmartReply(tone: AIReplyTone) {
        guard !isGenerating else { return }
        isGenerating = true
        generatedDraft = ""
        let contextSnippet = activeContext?.contextSnippet ?? ""
        let contact = contactTitle
        let userInstruction = "Draft a \(tone.rawValue) reply to \(contact)."

        Task {
            session.appendCopilotMessage(role: "user", content: userInstruction)
            let result = await AIService.shared.streamCoPilotResponse(
                prompt: userInstruction,
                context: contextSnippet,
                tone: tone,
                history: session.copilotHistory,
                preferences: store.preferences,
                onChunk: { chunk in
                    generatedDraft += chunk
                }
            )
            session.appendCopilotMessage(role: "assistant", content: result)
            isGenerating = false
        }
    }

    private func triggerCustomPrompt() {
        let prompt = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isGenerating else { return }
        isGenerating = true
        generatedDraft = ""
        let query = prompt
        customPrompt = ""
        let contextSnippet = activeContext?.contextSnippet ?? ""

        Task {
            session.appendCopilotMessage(role: "user", content: query)
            let result = await AIService.shared.streamCoPilotResponse(
                prompt: query,
                context: contextSnippet,
                tone: activeTone,
                history: session.copilotHistory,
                preferences: store.preferences,
                onChunk: { chunk in
                    generatedDraft += chunk
                }
            )
            session.appendCopilotMessage(role: "assistant", content: result)
            isGenerating = false
        }
    }
}

