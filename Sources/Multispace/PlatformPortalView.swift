import AppKit
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

struct PlatformPortalView: View {
    @EnvironmentObject private var store: AppStore
    let platformID: String

    var body: some View {
        if let platform = store.platform(platformID) {
            if let url = platform.resolvedWebsiteURL {
                PortalBrowser(platform: platform, url: url)
                    .id("\(platform.id):\(url.absoluteString)")
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
    let url: URL
    @ObservedObject private var session: PortalSession

    init(platform: SocialPlatform, url: URL) {
        self.platform = platform
        self.url = url
        _session = ObservedObject(wrappedValue: PortalSessionRegistry.shared.session(for: platform.id, url: url))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PlatformLogo(platform: platform, size: 25)
                Text(platform.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                toolbarButton("chevron.left", help: "Back", enabled: session.canGoBack) { session.webView.goBack() }
                toolbarButton("chevron.right", help: "Forward", enabled: session.canGoForward) { session.webView.goForward() }
                toolbarButton("arrow.clockwise", help: "Reload", enabled: true) { session.webView.reload() }
                toolbarButton("square.on.square", help: "Open in browser", enabled: true) {
                    NSWorkspace.shared.open(session.currentURL ?? url)
                }
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
            }
            .background(.white)
        }
        .overlay(alignment: .top) {
            if session.isLoading {
                ProgressView().progressViewStyle(.linear).tint(Palette.accent)
                    .padding(.top, 78)
            }
        }
    }

    private func toolbarButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 27, height: 27)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}

private struct PortalWebView: NSViewRepresentable {
    @ObservedObject var session: PortalSession

    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

@MainActor
final class PortalSessionRegistry {
    static let shared = PortalSessionRegistry()
    private var sessions: [String: PortalSession] = [:]

    func session(for id: String, url: URL) -> PortalSession {
        if let existing = sessions[id], existing.homeURL == url { return existing }
        sessions[id]?.stop()
        let created = PortalSession(id: id, url: url)
        sessions[id] = created
        return created
    }

    func monitor(_ platforms: [SocialPlatform], store: AppStore) {
        let activeIDs = Set(platforms.map(\.id))
        for id in Array(sessions.keys) where !activeIDs.contains(id) {
            sessions[id]?.stop()
            sessions.removeValue(forKey: id)
        }
        for platform in platforms {
            guard let url = platform.resolvedWebsiteURL else { continue }
            let browser = session(for: platform.id, url: url)
            browser.activityHandler = { [weak store] title, messages, notifications in
                store?.updatePlatformActivity(id: platform.id, title: title,
                                              messages: messages, notifications: notifications)
            }
        }
    }
}

@MainActor
final class PortalSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL: URL?
    @Published var error: String?
    let webView: WKWebView
    let homeURL: URL
    let platformID: String
    var activityHandler: ((String, [[String: String]], [String]) -> Void)?

    init(id: String, url: URL) {
        platformID = id
        homeURL = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(WKUserScript(source: Self.activityScript,
                                                                       injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        configuration.userContentController.add(self, name: "multispaceActivity")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // Some portals use the Safari version token to decide whether to show their web app.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"
        load(url)
    }

    func stop() {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "multispaceActivity")
        activityHandler = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "multispaceActivity",
              let currentHost = webView.url?.host?.lowercased(),
              let homeHost = homeURL.host?.lowercased() else { return }
        let baseHost = homeHost.replacingOccurrences(of: "^(www|web)\\.", with: "", options: .regularExpression)
        guard currentHost == baseHost || currentHost.hasSuffix(".\(baseHost)") else { return }
        guard let body = message.body as? [String: Any] else { return }
        let title = body["title"] as? String ?? ""
        let rows = (body["messages"] as? [[String: Any]] ?? []).map { row in
            ["sender": row["sender"] as? String ?? "", "text": row["text"] as? String ?? ""]
        }
        let notifications = body["notifications"] as? [String] ?? []
        activityHandler?(title, rows, notifications)
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
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
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
      function collect() {
        const host = location.hostname.toLowerCase();
        let selector = '';
        if (host.endsWith('whatsapp.com')) selector = '[data-testid="cell-frame-container"]';
        else if (host.endsWith('instagram.com')) selector = 'a[href*="/direct/t/"]';
        else if (host.endsWith('telegram.org')) selector = '.chat-list .ListItem, .chat-list-item';
        else if (host.endsWith('facebook.com')) selector = 'a[href*="/messages/t/"]';
        else if (host.endsWith('snapchat.com')) selector = '[data-testid*="conversation-list"] [role="button"]';
        const messages = [];
        if (selector) {
          document.querySelectorAll(selector).forEach(node => {
            if (messages.length >= 8) return;
            const lines = (node.innerText || '').split(/\n+/).map(clean).filter(Boolean);
            if (lines.length < 2) return;
            const sender = lines[0].slice(0, 80);
            if (sender.toLowerCase() === 'archived') return;
            const text = lines.slice(1).join(' ').slice(0, 240);
            if (sender && text) messages.push({ sender, text });
          });
        }
        const notifications = [];
        document.querySelectorAll('[role="alert"], [aria-live="assertive"], [data-testid*="notification"]').forEach(node => {
          if (notifications.length >= 8) return;
          const text = clean(node.innerText).slice(0, 240);
          if (text && !notifications.includes(text)) notifications.push(text);
        });
        const payload = { title: document.title || '', messages, notifications };
        const signature = JSON.stringify(payload);
        if (signature === lastPayload) return;
        lastPayload = signature;
        window.webkit?.messageHandlers?.multispaceActivity?.postMessage(payload);
      }
      function schedule() {
        if (pending) return;
        pending = setTimeout(() => { pending = null; collect(); }, 1000);
      }
      new MutationObserver(schedule).observe(document.documentElement, { subtree: true, childList: true, characterData: true });
      setInterval(collect, 15000);
      collect();
    })();
    """#
}
