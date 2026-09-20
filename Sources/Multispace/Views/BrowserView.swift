import SwiftUI
import WebKit
import AppKit

// MARK: - Browser Models
struct BrowserBookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var urlString: String
    var symbol: String
}

// MARK: - AdBlocker Rules & Engine
enum AdBlockEngine {
    static let rulesJSON = """
    [
        {
            "trigger": {
                "url-filter": ".*",
                "load-type": ["third-party"],
                "if-domain": [
                    "*doubleclick.net*",
                    "*googleadservices.com*",
                    "*googlesyndication.com*",
                    "*adservice.google.*",
                    "*adnxs.com*",
                    "*advertising.com*",
                    "*scorecardresearch.com*",
                    "*criteo.com*",
                    "*outbrain.com*",
                    "*taboola.com*",
                    "*adroll.com*",
                    "*quantserve.com*",
                    "*popads.net*",
                    "*popcash.net*",
                    "*bidswitch.net*",
                    "*rubiconproject.com*",
                    "*pubmatic.com*",
                    "*openx.net*",
                    "*smartadserver.com*",
                    "*amazon-adsystem.com*",
                    "*casalemedia.com*",
                    "*lijit.com*",
                    "*exponential.com*",
                    "*contextweb.com*",
                    "*advertising.amazon.com*"
                ]
            },
            "action": {
                "type": "block"
            }
        },
        {
            "trigger": {
                "url-filter": ".*(adserver|adservices|adsystem|googlesyndication|googleadservices|doubleclick|taboola|outbrain|adnxs|carbonads|adroll|popads|popcash).*"
            },
            "action": {
                "type": "block"
            }
        },
        {
            "trigger": {
                "url-filter": ".*"
            },
            "action": {
                "type": "css-display-none",
                "selector": ".ad, .ads, .adsbygoogle, .ad-container, .ad-banner, .advertisement, [id^='ad_'], [id^='google_ads_'], [class*='sponsored'], [class*='promoted'], .ad-box, .banner-ad, iframe[id*='google_ads'], div[data-ad-unit], .sidebar-ads, [data-ad-slot], .native-ad, .outbrain, .taboola"
            }
        }
    ]
    """

    static let countScript = """
    (() => {
        let lastReported = 0;
        function inspectBlockedAds() {
            const adNodes = document.querySelectorAll('.ad, .ads, .adsbygoogle, .ad-container, .ad-banner, .advertisement, [id^="ad_"], [id^="google_ads_"], [class*="sponsored"], [class*="promoted"], .banner-ad, iframe[id*="google_ads"], div[data-ad-unit]');
            let count = 0;
            adNodes.forEach(node => {
                const style = window.getComputedStyle(node);
                if (style.display === 'none' || node.offsetParent === null) {
                    count++;
                }
            });
            if (count !== lastReported) {
                lastReported = count;
                try {
                    window.webkit.messageHandlers.pinggoAdBlock.postMessage({ count: count });
                } catch(e) {}
            }
        }
        setInterval(inspectBlockedAds, 1500);
        inspectBlockedAds();
    })();
    """

    @MainActor
    static func compileRuleList(completion: @escaping @MainActor @Sendable (WKContentRuleList?) -> Void) {
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "PinggoAdBlockRuleList",
            encodedContentRuleList: rulesJSON
        ) { ruleList, _ in
            completion(ruleList)
        }
    }
}

// MARK: - Browser Session Storage Models
struct SavedBrowserTab: Codable {
    let id: UUID
    let title: String
    let urlString: String
    let pageTitle: String
    let isReaderModeActive: Bool
    let blockedAdsCount: Int
}

struct SavedBrowserSession: Codable {
    let tabs: [SavedBrowserTab]
    let activeTabID: UUID
}

// MARK: - Browser Tab Item Model
struct BrowserTabItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var urlString: String
    var currentURL: URL?
    var pageTitle: String
    var isLoading: Bool
    var estimatedProgress: Double
    var canGoBack: Bool
    var canGoForward: Bool
    var blockedAdsCount: Int
    var isReaderModeActive: Bool
    var readerContent: String?
}

// MARK: - Dedicated Tab WKWebView Subclass
final class PinggoTabWebView: WKWebView {
    let tabID: UUID

    init(tabID: UUID, frame: CGRect, configuration: WKWebViewConfiguration) {
        self.tabID = tabID
        super.init(frame: frame, configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Browser State Controller
@MainActor
final class BrowserState: ObservableObject {
    static let shared = BrowserState()

    private let sessionKey = "pinggo.browser.saved_session"
    private let bookmarksKey = "pinggo.browser.saved_bookmarks"

    @Published var tabs: [BrowserTabItem] = []
    @Published var activeTabID: UUID = UUID()

    @Published var urlInput: String = ""
    @Published var currentURL: URL? = nil
    @Published var pageTitle: String = ""
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isAdBlockerActive: Bool = true
    @Published var blockedAdsCount: Int = 0
    @Published var isReaderModeActive: Bool = false
    @Published var readerContent: String? = nil
    @Published var searchEngine: String = "DuckDuckGo" // "DuckDuckGo", "Google", "Bing"

    // Granular AdBlock Filter Categories
    @Published var blockAds: Bool = true
    @Published var blockTrackers: Bool = true
    @Published var blockCookieBanners: Bool = true

    // Download Tracker
    @Published var recentDownloads: [String] = []
    @Published var activeDownloadCount: Int = 0

    @Published var bookmarks: [BrowserBookmark] = [
        BrowserBookmark(title: "Google", urlString: "https://www.google.com", symbol: "magnifyingglass"),
        BrowserBookmark(title: "GitHub", urlString: "https://github.com", symbol: "chevron.left.forwardslash.chevron.right"),
        BrowserBookmark(title: "Hacker News", urlString: "https://news.ycombinator.com", symbol: "y.square.fill"),
        BrowserBookmark(title: "YouTube", urlString: "https://www.youtube.com", symbol: "play.rectangle.fill"),
        BrowserBookmark(title: "Reddit", urlString: "https://www.reddit.com", symbol: "bubble.left.and.bubble.right.fill"),
        BrowserBookmark(title: "Wikipedia", urlString: "https://www.wikipedia.org", symbol: "book.fill"),
        BrowserBookmark(title: "ChatGPT", urlString: "https://chatgpt.com", symbol: "sparkles"),
        BrowserBookmark(title: "Apple", urlString: "https://www.apple.com", symbol: "applelogo")
    ]

    var tabWebViews: [UUID: PinggoTabWebView] = [:]
    var contentRuleList: WKContentRuleList? = nil

    var activeWebView: PinggoTabWebView? {
        tabWebViews[activeTabID]
    }

    var webView: WKWebView? {
        activeWebView
    }

    init() {
        // 1. Restore bookmarks if previously customized
        if let bData = UserDefaults.standard.data(forKey: bookmarksKey),
           let bDecoded = try? JSONDecoder().decode([BrowserBookmark].self, from: bData),
           !bDecoded.isEmpty {
            self.bookmarks = bDecoded
        }

        // 2. Restore saved session or fallback to blank New Tab
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let session = try? JSONDecoder().decode(SavedBrowserSession.self, from: data),
           !session.tabs.isEmpty {
            var restoredTabs: [BrowserTabItem] = []
            for saved in session.tabs {
                let currentURL = saved.urlString.isEmpty ? nil : URL(string: saved.urlString)
                restoredTabs.append(BrowserTabItem(
                    id: saved.id,
                    title: saved.title.isEmpty ? (currentURL?.host ?? "New Tab") : saved.title,
                    urlString: saved.urlString,
                    currentURL: currentURL,
                    pageTitle: saved.pageTitle,
                    isLoading: false,
                    estimatedProgress: 0.0,
                    canGoBack: false,
                    canGoForward: false,
                    blockedAdsCount: saved.blockedAdsCount,
                    isReaderModeActive: saved.isReaderModeActive,
                    readerContent: nil
                ))
            }
            self.tabs = restoredTabs
            let targetActiveID = restoredTabs.contains(where: { $0.id == session.activeTabID })
                ? session.activeTabID
                : restoredTabs[0].id
            self.activeTabID = targetActiveID

            if let activeTab = restoredTabs.first(where: { $0.id == targetActiveID }) {
                self.restoreTab(activeTab)
            }
        } else {
            let initialID = UUID()
            self.activeTabID = initialID
            self.tabs = [
                BrowserTabItem(
                    id: initialID,
                    title: "New Tab",
                    urlString: "",
                    currentURL: nil,
                    pageTitle: "",
                    isLoading: false,
                    estimatedProgress: 0.0,
                    canGoBack: false,
                    canGoForward: false,
                    blockedAdsCount: 0,
                    isReaderModeActive: false,
                    readerContent: nil
                )
            ]
        }

        AdBlockEngine.compileRuleList { [weak self] list in
            guard let self = self else { return }
            self.contentRuleList = list
            if self.isAdBlockerActive, let list = list {
                for (_, wv) in self.tabWebViews {
                    wv.configuration.userContentController.add(list)
                }
            }
        }
    }

    func saveSession() {
        saveActiveTabSnapshot()
        let savedTabs = tabs.map { tab in
            SavedBrowserTab(
                id: tab.id,
                title: tab.title,
                urlString: tab.urlString,
                pageTitle: tab.pageTitle,
                isReaderModeActive: tab.isReaderModeActive,
                blockedAdsCount: tab.blockedAdsCount
            )
        }
        let session = SavedBrowserSession(tabs: savedTabs, activeTabID: activeTabID)
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }

    func webView(for tabID: UUID, coordinator: BrowserWebContainer.Coordinator) -> PinggoTabWebView {
        if let existing = tabWebViews[tabID] {
            existing.navigationDelegate = coordinator
            existing.uiDelegate = coordinator
            existing.configuration.userContentController.removeScriptMessageHandler(forName: "pinggoAdBlock")
            existing.configuration.userContentController.add(coordinator, name: "pinggoAdBlock")
            coordinator.setupObservation(tabID: tabID, webView: existing)
            return existing
        }

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        if let ruleList = contentRuleList, isAdBlockerActive {
            configuration.userContentController.add(ruleList)
        }

        configuration.userContentController.addUserScript(
            WKUserScript(source: AdBlockEngine.countScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        configuration.userContentController.add(coordinator, name: "pinggoAdBlock")

        let wv = PinggoTabWebView(tabID: tabID, frame: .zero, configuration: configuration)
        wv.navigationDelegate = coordinator
        wv.uiDelegate = coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

        tabWebViews[tabID] = wv
        coordinator.setupObservation(tabID: tabID, webView: wv)

        // If tab has a saved URL, load it into this new webView
        if let tab = tabs.first(where: { $0.id == tabID }), let url = tab.currentURL, wv.url == nil {
            wv.load(URLRequest(url: url))
        }

        return wv
    }

    func addNewTab(urlString: String = "") {
        saveActiveTabSnapshot()
        let newID = UUID()
        let initialURL = urlString.isEmpty ? nil : (URL(string: urlString) ?? searchURL(for: urlString))
        let newTab = BrowserTabItem(
            id: newID,
            title: "New Tab",
            urlString: initialURL?.absoluteString ?? "",
            currentURL: initialURL,
            pageTitle: "",
            isLoading: false,
            estimatedProgress: 0.0,
            canGoBack: false,
            canGoForward: false,
            blockedAdsCount: 0,
            isReaderModeActive: false,
            readerContent: nil
        )
        tabs.append(newTab)
        activeTabID = newID
        restoreTab(newTab)
        saveSession()

        if let target = initialURL {
            activeWebView?.load(URLRequest(url: target))
        }
    }

    func selectTab(id: UUID) {
        guard id != activeTabID, let target = tabs.first(where: { $0.id == id }) else { return }
        saveActiveTabSnapshot()
        activeTabID = id
        restoreTab(target)
        saveSession()
    }

    func closeTab(id: UUID) {
        if let wv = tabWebViews.removeValue(forKey: id) {
            wv.stopLoading()
            wv.removeFromSuperview()
        }
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: idx)
        if tabs.isEmpty {
            addNewTab()
        } else if activeTabID == id {
            let nextIndex = min(idx, tabs.count - 1)
            let nextTab = tabs[nextIndex]
            activeTabID = nextTab.id
            restoreTab(nextTab)
        }
        saveSession()
    }

    private func saveActiveTabSnapshot() {
        if let idx = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[idx].title = pageTitle.isEmpty ? (currentURL?.host ?? "New Tab") : pageTitle
            tabs[idx].urlString = urlInput
            tabs[idx].currentURL = currentURL
            tabs[idx].pageTitle = pageTitle
            tabs[idx].isLoading = isLoading
            tabs[idx].estimatedProgress = estimatedProgress
            tabs[idx].canGoBack = canGoBack
            tabs[idx].canGoForward = canGoForward
            tabs[idx].blockedAdsCount = blockedAdsCount
            tabs[idx].isReaderModeActive = isReaderModeActive
            tabs[idx].readerContent = readerContent
        }
    }

    private func restoreTab(_ tab: BrowserTabItem) {
        urlInput = tab.urlString
        currentURL = tab.currentURL
        pageTitle = tab.pageTitle
        isLoading = tab.isLoading
        estimatedProgress = tab.estimatedProgress
        canGoBack = tab.canGoBack
        canGoForward = tab.canGoForward
        blockedAdsCount = tab.blockedAdsCount
        isReaderModeActive = tab.isReaderModeActive
        readerContent = tab.readerContent
    }

    func syncActiveTabMetadata() {
        if let idx = tabs.firstIndex(where: { $0.id == activeTabID }) {
            tabs[idx].title = pageTitle.isEmpty ? (currentURL?.host ?? "New Tab") : pageTitle
            tabs[idx].urlString = urlInput
            tabs[idx].currentURL = currentURL
            tabs[idx].pageTitle = pageTitle
            tabs[idx].isLoading = isLoading
            tabs[idx].estimatedProgress = estimatedProgress
            tabs[idx].canGoBack = canGoBack
            tabs[idx].canGoForward = canGoForward
            tabs[idx].blockedAdsCount = blockedAdsCount
        }
    }

    func load(urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetURL: URL
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            targetURL = URL(string: trimmed) ?? searchURL(for: trimmed)
        } else if trimmed.contains(".") && !trimmed.contains(" ") {
            targetURL = URL(string: "https://\(trimmed)") ?? searchURL(for: trimmed)
        } else {
            targetURL = searchURL(for: trimmed)
        }

        urlInput = targetURL.absoluteString
        currentURL = targetURL
        blockedAdsCount = 0
        isReaderModeActive = false
        readerContent = nil

        syncActiveTabMetadata()
        saveSession()

        let request = URLRequest(url: targetURL)
        activeWebView?.load(request)
    }

    func searchURL(for query: String) -> URL {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch searchEngine {
        case "Google":
            return URL(string: "https://www.google.com/search?q=\(encoded)")!
        case "Bing":
            return URL(string: "https://www.bing.com/search?q=\(encoded)")!
        default:
            return URL(string: "https://duckduckgo.com/?q=\(encoded)")!
        }
    }

    func reload() {
        activeWebView?.reload()
    }

    func stopLoading() {
        activeWebView?.stopLoading()
    }

    func goBack() {
        activeWebView?.goBack()
    }

    func goForward() {
        activeWebView?.goForward()
    }

    func goHome() {
        currentURL = nil
        urlInput = ""
        pageTitle = ""
        isReaderModeActive = false
        readerContent = nil
        syncActiveTabMetadata()
        saveSession()
    }

    func toggleAdBlocker() {
        isAdBlockerActive.toggle()
        guard let ruleList = contentRuleList else { return }
        for (_, wv) in tabWebViews {
            let ucc = wv.configuration.userContentController
            if isAdBlockerActive {
                ucc.add(ruleList)
            } else {
                ucc.remove(ruleList)
            }
        }
        activeWebView?.reload()
    }

    func toggleBookmark() {
        guard let url = currentURL else { return }
        let str = url.absoluteString
        if let idx = bookmarks.firstIndex(where: { $0.urlString == str }) {
            bookmarks.remove(at: idx)
        } else {
            let title = pageTitle.isEmpty ? (url.host ?? "Website") : pageTitle
            bookmarks.append(BrowserBookmark(title: title, urlString: str, symbol: "globe"))
        }
        saveBookmarks()
    }

    var isCurrentBookmarked: Bool {
        guard let url = currentURL else { return false }
        return bookmarks.contains { $0.urlString == url.absoluteString }
    }

    func extractReaderMode() {
        guard let webView = activeWebView else { return }
        let script = """
        (() => {
            const article = document.querySelector('article') || document.querySelector('[role="main"]') || document.querySelector('.main-content') || document.body;
            const title = document.title || '';
            const paragraphs = Array.from(article.querySelectorAll('p, h1, h2, h3, h4, blockquote, pre')).map(p => {
                const tag = p.tagName.toLowerCase();
                const text = p.innerText.trim();
                if (!text) return '';
                if (tag === 'h1') return '# ' + text;
                if (tag === 'h2') return '## ' + text;
                if (tag === 'h3') return '### ' + text;
                if (tag === 'blockquote') return '> ' + text;
                return text;
            }).filter(Boolean);
            return { title: title, content: paragraphs.join('\\n\\n') };
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let dict = result as? [String: Any], let content = dict["content"] as? String, !content.isEmpty {
                self?.readerContent = content
                self?.isReaderModeActive = true
            }
        }
    }

    func updateTabLoading(id: UUID, isLoading: Bool) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].isLoading = isLoading
        }
        if id == activeTabID {
            self.isLoading = isLoading
        }
    }

    func updateTabProgress(id: UUID, progress: Double) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].estimatedProgress = progress
        }
        if id == activeTabID {
            self.estimatedProgress = progress
        }
    }

    func updateTabTitle(id: UUID, title: String) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].pageTitle = title
            tabs[idx].title = title
        }
        if id == activeTabID {
            self.pageTitle = title
        }
        saveSession()
    }

    func updateTabURL(id: UUID, url: URL) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].currentURL = url
            tabs[idx].urlString = url.absoluteString
            if tabs[idx].title.isEmpty || tabs[idx].title == "New Tab" {
                tabs[idx].title = url.host ?? url.absoluteString
            }
        }
        if id == activeTabID {
            self.currentURL = url
            self.urlInput = url.absoluteString
        }
        saveSession()
    }

    func updateTabCanGoBack(id: UUID, canGoBack: Bool) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].canGoBack = canGoBack
        }
        if id == activeTabID {
            self.canGoBack = canGoBack
        }
    }

    func updateTabCanGoForward(id: UUID, canGoForward: Bool) {
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            tabs[idx].canGoForward = canGoForward
        }
        if id == activeTabID {
            self.canGoForward = canGoForward
        }
    }
}

// MARK: - Main Browser View
struct BrowserView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var browserState: BrowserState = BrowserState.shared
    @State private var showingAdBlockPopover: Bool = false
    @State private var showingBookmarksPopover: Bool = false
    @State private var showingDownloadsPopover: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 1. Browser Tab Bar (36px)
            browserTabBar
                .frame(height: 36)
                .background(Palette.sidebar)

            Divider()
                .background(Palette.border)

            // 2. Browser Navigation & Omnibar (52px)
            browserToolbar
                .frame(height: 52)
                .background(Palette.panel)

            Divider()
                .background(Palette.border)

            // 3. Web View or Start Page or Reader Mode
            ZStack {
                if browserState.isReaderModeActive, let content = browserState.readerContent {
                    readerModeView(content: content)
                } else {
                    BrowserWebContainer(state: browserState)
                        .opacity(browserState.currentURL == nil ? 0 : 1)

                    if browserState.currentURL == nil {
                        BrowserStartPage(state: browserState)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
        }
        .onAppear {
            handleRequestedURL()
        }
        .onChange(of: store.browserRequestedURL) { _, _ in
            handleRequestedURL()
        }
    }

    private func handleRequestedURL() {
        guard let requested = store.browserRequestedURL else { return }
        store.browserRequestedURL = nil
        if browserState.currentURL == nil && browserState.urlInput.isEmpty {
            browserState.load(urlString: requested.absoluteString)
        } else {
            browserState.addNewTab(urlString: requested.absoluteString)
        }
    }

    // MARK: - Browser Tab Bar
    private var browserTabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(browserState.tabs) { tab in
                        let isActive = tab.id == browserState.activeTabID
                        HStack(spacing: 6) {
                            if tab.isLoading {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                    .foregroundStyle(isActive ? Palette.accent : Palette.muted)
                            }

                            Text(tab.title.isEmpty ? "New Tab" : tab.title)
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? Color.primary : Palette.muted)
                                .lineLimit(1)
                                .frame(maxWidth: 130, alignment: .leading)

                            Button {
                                browserState.closeTab(id: tab.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 16, height: 16)
                                    .background(Palette.card.opacity(0.6), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Close tab")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isActive ? Palette.panel : Palette.card.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isActive ? Palette.accent.opacity(0.5) : Palette.border.opacity(0.5), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            browserState.selectTab(id: tab.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            // New Tab button
            Button {
                browserState.addNewTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 24, height: 24)
                    .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("New Tab (⌘T)")
            .padding(.trailing, 8)
        }
        .frame(height: 36)
    }

    // MARK: - Browser Toolbar
    private var browserToolbar: some View {
        HStack(spacing: 10) {
            // Navigation buttons
            HStack(spacing: 4) {
                Button { browserState.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(browserState.canGoBack ? Color.primary : Palette.muted.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!browserState.canGoBack)
                .help("Back (⌘[)")

                Button { browserState.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(browserState.canGoForward ? Color.primary : Palette.muted.opacity(0.4))
                        .frame(width: 28, height: 28)
                        .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!browserState.canGoForward)
                .help("Forward (⌘])")

                Button {
                    if browserState.isLoading {
                        browserState.stopLoading()
                    } else {
                        browserState.reload()
                    }
                } label: {
                    Image(systemName: browserState.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: 28, height: 28)
                        .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(browserState.isLoading ? "Stop loading (Esc)" : "Reload page (⌘R)")

                Button { browserState.goHome() } label: {
                    Image(systemName: "house.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .frame(width: 28, height: 28)
                        .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Browser Start Page & Favorites")
            }

            // Smart Omnibar (Address & Search Bar)
            omnibarField

            // AdBlocker Status Pill
            adBlockerPill

            // Download Tracker Pill
            if !browserState.recentDownloads.isEmpty {
                Button {
                    showingDownloadsPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.accent)
                        Text("\(browserState.recentDownloads.count)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.accent)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(Palette.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Palette.accent.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Recent Downloads")
                .popover(isPresented: $showingDownloadsPopover, arrowEdge: .bottom) {
                    downloadsPopoverContent
                }
            }

            // Action controls
            HStack(spacing: 6) {
                // Bookmarks Popover Button
                Button { showingBookmarksPopover.toggle() } label: {
                    Image(systemName: "book.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Bookmarks & Quick Access")
                .popover(isPresented: $showingBookmarksPopover, arrowEdge: .bottom) {
                    bookmarksPopoverContent
                }

                // Open in External Safari
                if let url = browserState.currentURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .frame(width: 32, height: 32)
                            .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Open current URL in Safari")
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Smart Omnibar (Address & Search Bar)
    private var omnibarField: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 8) {
                // Security / Search Indicator
                if browserState.currentURL != nil {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }

                TextField("Search or enter web address…", text: $browserState.urlInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit {
                        browserState.load(urlString: browserState.urlInput)
                    }

                if !browserState.urlInput.isEmpty {
                    Button {
                        browserState.urlInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                }

                // Reader mode toggle
                if browserState.currentURL != nil {
                    Button {
                        if browserState.isReaderModeActive {
                            browserState.isReaderModeActive = false
                        } else {
                            browserState.extractReaderMode()
                        }
                    } label: {
                        Image(systemName: browserState.isReaderModeActive ? "doc.plaintext.fill" : "doc.plaintext")
                            .font(.system(size: 11))
                            .foregroundStyle(browserState.isReaderModeActive ? Palette.accent : Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Reader Mode (Distraction-free article view)")

                    // Bookmark star
                    Button {
                        browserState.toggleBookmark()
                    } label: {
                        Image(systemName: browserState.isCurrentBookmarked ? "star.fill" : "star")
                            .font(.system(size: 11.5))
                            .foregroundStyle(browserState.isCurrentBookmarked ? Color.yellow : Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .help(browserState.isCurrentBookmarked ? "Remove Bookmark" : "Bookmark this page")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Palette.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))

            // Progress bar
            if browserState.isLoading && browserState.estimatedProgress < 1.0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Palette.accent)
                        .frame(width: geo.size.width * CGFloat(browserState.estimatedProgress), height: 2)
                }
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: 1))
            }
        }
    }

    // MARK: - AdBlocker Status Pill
    private var adBlockerPill: some View {
        Button {
            showingAdBlockPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: browserState.isAdBlockerActive ? "shield.checkered" : "shield.slash")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(browserState.isAdBlockerActive ? Color.green : Palette.muted)

                Text(browserState.isAdBlockerActive ? "AdBlock" : "Off")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(browserState.isAdBlockerActive ? Color.green : Palette.muted)

                if browserState.isAdBlockerActive && browserState.blockedAdsCount > 0 {
                    Text("\(browserState.blockedAdsCount)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.85), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                browserState.isAdBlockerActive ? Color.green.opacity(0.12) : Palette.card.opacity(0.5),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    browserState.isAdBlockerActive ? Color.green.opacity(0.3) : Palette.border,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .help("Native AdBlocker Shield")
        .popover(isPresented: $showingAdBlockPopover, arrowEdge: .bottom) {
            adBlockerPopoverContent
        }
    }

    // MARK: - AdBlocker Dashboard Popover
    private var adBlockerPopoverContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(browserState.isAdBlockerActive ? Color.green : Palette.muted)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PINGGO AdBlocker Shield")
                        .font(.system(size: 13, weight: .bold))
                    Text(browserState.isAdBlockerActive ? "Actively blocking third-party ads & trackers" : "Protection paused")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { browserState.isAdBlockerActive },
                    set: { _ in browserState.toggleAdBlocker() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            Divider()

            // Metrics
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(browserState.blockedAdsCount)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.green)
                    Text("Ads & trackers blocked")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("WebKit")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.accent)
                    Text("Native rule list store")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("Third-party tracking cookies blocked")
                        .font(.system(size: 11))
                }
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("Intrusive popups & banner scripts suppressed")
                        .font(.system(size: 11))
                }
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                    Text("Zero CPU & battery overhead")
                        .font(.system(size: 11))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("PROTECTION CATEGORIES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)

                HStack {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                    Text("Block Banner Ads & Popups")
                        .font(.system(size: 11.5))
                    Spacer()
                    Toggle("", isOn: $browserState.blockAds)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                    Text("Block Trackers & Telemetry")
                        .font(.system(size: 11.5))
                    Spacer()
                    Toggle("", isOn: $browserState.blockTrackers)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                    Text("Block Cookie Consent Overlays")
                        .font(.system(size: 11.5))
                    Spacer()
                    Toggle("", isOn: $browserState.blockCookieBanners)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Downloads Popover Content
    private var downloadsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Palette.accent)
                Text("Recent Downloads")
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                Button("Clear") {
                    browserState.recentDownloads.removeAll()
                    showingDownloadsPopover = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
            }
            Divider()
            ForEach(browserState.recentDownloads.suffix(5).reversed(), id: \.self) { filename in
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                    Text(filename)
                        .font(.system(size: 11.5))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                        let fileURL = downloadsDir.appendingPathComponent(filename)
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - Bookmarks Popover Content
    private var bookmarksPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bookmarks & Favorites")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(browserState.bookmarks.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }

            Divider()

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(browserState.bookmarks) { item in
                        Button {
                            showingBookmarksPopover = false
                            browserState.load(urlString: item.urlString)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.accent)
                                    .frame(width: 20)

                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.primary)

                                Spacer()

                                Text(URL(string: item.urlString)?.host ?? "")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.muted)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Palette.hover.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 220)
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: - Reader Mode View
    private func readerModeView(content: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Button {
                        browserState.isReaderModeActive = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text("Exit Reader Mode")
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Text("Distraction-Free Reading")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }

                Text(browserState.pageTitle)
                    .font(.system(size: 26, weight: .bold))
                    .padding(.top, 8)

                if let host = browserState.currentURL?.host {
                    Text("Published on \(host)")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }

                Divider()

                Text(content)
                    .font(.system(size: 15))
                    .lineSpacing(7)
                    .foregroundStyle(Color.primary.opacity(0.9))
                    .textSelection(.enabled)
            }
            .padding(32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Browser Start Page (Speed Dial)
struct BrowserStartPage: View {
    @ObservedObject var state: BrowserState
    @State private var searchInput: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Hero / Branding
                VStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 64, height: 64)
                            .shadow(color: Palette.accent.opacity(0.3), radius: 12, y: 6)

                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                    }

                    Text("PINGGO Private Browser")
                        .font(.system(size: 22, weight: .bold))

                    HStack(spacing: 6) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("Native WebKit AdBlocker Active · Zero Trackers · Isolated Sandbox")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(.top, 40)

                // Big Centered Search Bar
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.muted)

                        TextField("Search the web with \(state.searchEngine) or enter a URL…", text: $searchInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .onSubmit {
                                state.load(urlString: searchInput)
                            }

                        Button {
                            state.load(urlString: searchInput)
                        } label: {
                            Text("Go")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.card, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                    // Search engine switcher
                    HStack(spacing: 12) {
                        Text("Search Engine:")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)

                        ForEach(["DuckDuckGo", "Google", "Bing"], id: \.self) { engine in
                            Button {
                                state.searchEngine = engine
                            } label: {
                                Text(engine)
                                    .font(.system(size: 11, weight: state.searchEngine == engine ? .bold : .regular))
                                    .foregroundStyle(state.searchEngine == engine ? Palette.accent : Palette.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 580)

                // Quick Favorites Grid
                VStack(alignment: .leading, spacing: 14) {
                    Text("TOP FAVORITES & QUICK LAUNCH")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.muted)
                        .tracking(1.2)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
                        ForEach(state.bookmarks) { bookmark in
                            Button {
                                state.load(urlString: bookmark.urlString)
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Palette.panel)
                                            .frame(width: 48, height: 48)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.card, lineWidth: 1))
                                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

                                        Image(systemName: bookmark.symbol)
                                            .font(.system(size: 20))
                                            .foregroundStyle(Palette.accent)
                                    }

                                    Text(bookmark.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Palette.hover.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Browser Host Container NSView
final class BrowserContainerHostView: NSView {
    private(set) var activeTabID: UUID?

    func displayTab(id: UUID, webView: PinggoTabWebView) {
        if webView.superview != self {
            webView.removeFromSuperview()
            addSubview(webView)
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                webView.topAnchor.constraint(equalTo: topAnchor),
                webView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        for subview in subviews {
            if let tabWV = subview as? PinggoTabWebView {
                tabWV.isHidden = (tabWV.tabID != id)
            }
        }
        activeTabID = id
    }
}

// MARK: - WebKit Container
struct BrowserWebContainer: NSViewRepresentable {
    @ObservedObject var state: BrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> BrowserContainerHostView {
        let hostView = BrowserContainerHostView()
        let activeWV = state.webView(for: state.activeTabID, coordinator: context.coordinator)
        hostView.displayTab(id: state.activeTabID, webView: activeWV)
        return hostView
    }

    func updateNSView(_ hostView: BrowserContainerHostView, context: Context) {
        let activeWV = state.webView(for: state.activeTabID, coordinator: context.coordinator)
        hostView.displayTab(id: state.activeTabID, webView: activeWV)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
        var parent: BrowserWebContainer
        var observations: [UUID: [NSKeyValueObservation]] = [:]

        init(_ parent: BrowserWebContainer) {
            self.parent = parent
        }

        func setupObservation(tabID: UUID, webView: PinggoTabWebView) {
            observations[tabID]?.forEach { $0.invalidate() }

            var tabObservers: [NSKeyValueObservation] = []

            tabObservers.append(webView.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.parent.state.updateTabProgress(id: tabID, progress: wv.estimatedProgress)
                }
            })

            tabObservers.append(webView.observe(\.title, options: .new) { [weak self] wv, _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let t = wv.title, !t.isEmpty {
                        self.parent.state.updateTabTitle(id: tabID, title: t)
                    }
                }
            })

            tabObservers.append(webView.observe(\.url, options: .new) { [weak self] wv, _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if let u = wv.url, u.absoluteString != "about:blank" {
                        self.parent.state.updateTabURL(id: tabID, url: u)
                    }
                }
            })

            tabObservers.append(webView.observe(\.canGoBack, options: .new) { [weak self] wv, _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.parent.state.updateTabCanGoBack(id: tabID, canGoBack: wv.canGoBack)
                }
            })

            tabObservers.append(webView.observe(\.canGoForward, options: .new) { [weak self] wv, _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.parent.state.updateTabCanGoForward(id: tabID, canGoForward: wv.canGoForward)
                }
            })

            observations[tabID] = tabObservers
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            guard let tabWV = webView as? PinggoTabWebView else { return }
            DispatchQueue.main.async {
                self.parent.state.updateTabLoading(id: tabWV.tabID, isLoading: true)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let tabWV = webView as? PinggoTabWebView else { return }
            DispatchQueue.main.async {
                self.parent.state.updateTabLoading(id: tabWV.tabID, isLoading: false)
                self.parent.state.saveSession()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard let tabWV = webView as? PinggoTabWebView else { return }
            DispatchQueue.main.async {
                self.parent.state.updateTabLoading(id: tabWV.tabID, isLoading: false)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard let tabWV = webView as? PinggoTabWebView else { return }
            tabWV.reload()
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
            let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            var destinationURL = downloadsDir.appendingPathComponent(suggestedFilename)
            var count = 1
            while FileManager.default.fileExists(atPath: destinationURL.path) {
                let name = (suggestedFilename as NSString).deletingPathExtension
                let ext = (suggestedFilename as NSString).pathExtension
                destinationURL = downloadsDir.appendingPathComponent("\(name) (\(count)).\(ext)")
                count += 1
            }
            DispatchQueue.main.async {
                self.parent.state.recentDownloads.append(suggestedFilename)
                self.parent.state.activeDownloadCount += 1
            }
            completionHandler(destinationURL)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "pinggoAdBlock", let dict = message.body as? [String: Any], let count = dict["count"] as? Int {
                DispatchQueue.main.async {
                    if let tabWV = message.webView as? PinggoTabWebView {
                        if let idx = self.parent.state.tabs.firstIndex(where: { $0.id == tabWV.tabID }) {
                            self.parent.state.tabs[idx].blockedAdsCount = max(self.parent.state.tabs[idx].blockedAdsCount, count)
                        }
                        if tabWV.tabID == self.parent.state.activeTabID {
                            self.parent.state.blockedAdsCount = max(self.parent.state.blockedAdsCount, count)
                        }
                    } else {
                        self.parent.state.blockedAdsCount = max(self.parent.state.blockedAdsCount, count)
                    }
                }
            }
        }
    }
}
