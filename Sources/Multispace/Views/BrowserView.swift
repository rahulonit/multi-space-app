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
                    "*googleads.g.doubleclick.net*",
                    "*pagead2.googlesyndication.com*",
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
                    "*advertising.amazon.com*",
                    "*media.net*",
                    "*sovrn.com*",
                    "*liveramp.com*",
                    "*inmobi.com*",
                    "*unityads.unity3d.com*",
                    "*applovin.com*",
                    "*ironsrc.com*",
                    "*vungle.com*"
                ]
            },
            "action": {
                "type": "block"
            }
        },
        {
            "trigger": {
                "url-filter": ".*(pagead|googleadservices|googlesyndication|doubleclick|taboola|outbrain|adnxs|carbonads|adroll|popads|popcash|smartadserver|criteo|rubiconproject|pubmatic).*"
            },
            "action": {
                "type": "block"
            }
        },
        {
            "trigger": {
                "url-filter": ".*youtube\\\\.com/(pagead/|api/stats/ads|youtubei/v1/player/ad_break|get_midroll_info|ptracking).*"
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
                "selector": ".ad, .ads, .adsbygoogle, .ad-container, .ad-banner, .advertisement, [id^='ad_'], [id^='google_ads_'], [class*='sponsored'], [class*='promoted'], .ad-box, .banner-ad, iframe[id*='google_ads'], div[data-ad-unit], .sidebar-ads, [data-ad-slot], .native-ad, .outbrain, .taboola, ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer, ytd-statement-banner-renderer, #masthead-ad, ytd-engagement-panel-section-list-renderer[target-id='engagement-panel-ads'], .ytp-ad-overlay-container, .ytp-ad-message-container, .ytp-ad-progress-list, .ytp-ad-player-overlay, .ytp-ad-player-overlay-layout, .ytp-ad-action-interstitial, #player-ads, ytd-promoted-sparkles-web-renderer, ytd-compact-promoted-video-renderer, ytd-promoted-video-renderer, ytd-display-ad-renderer, .sparkles-light-cta, ytd-feed-nudge-renderer, ytd-search-pyv-renderer, ytd-merch-shelf-renderer, .ytd-mealbar-promo-renderer, ytd-enforcement-message-view-model, tp-yt-iron-overlay-backdrop, #onetrust-banner-sdk, .cookie-banner, .cookie-consent, #cookie-notice"
            }
        }
    ]
    """

    static func earlyScript(blockYouTube: Bool = true) -> String {
        """
        (() => {
            if (window.__pinggo_early_injected) return;
            window.__pinggo_early_injected = true;

            const blockYT = \(blockYouTube);

            function cleanseYT(data) {
                if (!blockYT || !data || typeof data !== 'object') return;
                try {
                    delete data.adPlacements;
                    delete data.playerAds;
                    delete data.adSlots;
                    if (data.playbackTracking) {
                        delete data.playbackTracking.videostatsPlaybackUrl;
                        delete data.playbackTracking.videostatsDelayplayUrl;
                        delete data.playbackTracking.videostatsWatchtimeUrl;
                        delete data.playbackTracking.videostatsAdPlaybackUrl;
                    }
                } catch (e) {}
            }

            if (blockYT) {
                try {
                    let _ytInitialPlayerResponse = window.ytInitialPlayerResponse;
                    cleanseYT(_ytInitialPlayerResponse);
                    Object.defineProperty(window, 'ytInitialPlayerResponse', {
                        get: () => _ytInitialPlayerResponse,
                        set: (val) => {
                            cleanseYT(val);
                            _ytInitialPlayerResponse = val;
                        },
                        configurable: true,
                        enumerable: true
                    });
                } catch (e) {}

                if (typeof window.fetch === 'function') {
                    const origFetch = window.fetch;
                    window.fetch = async function(...args) {
                        const url = (typeof args[0] === 'string') ? args[0] : (args[0] && args[0].url ? args[0].url : '');
                        if (typeof url === 'string' && (url.includes('/youtubei/v1/player') || url.includes('/youtubei/v1/next'))) {
                            try {
                                const response = await origFetch.apply(this, args);
                                const clone = response.clone();
                                const text = await clone.text();
                                try {
                                    const json = JSON.parse(text);
                                    cleanseYT(json);
                                    return new Response(JSON.stringify(json), {
                                        status: response.status,
                                        statusText: response.statusText,
                                        headers: response.headers
                                    });
                                } catch (pe) {
                                    return response;
                                }
                            } catch (e) {
                                return origFetch.apply(this, args);
                            }
                        }
                        return origFetch.apply(this, args);
                    };
                }
            }

            function injectStyles() {
                if (document.getElementById('pinggo-adblock-styles')) return;
                const style = document.createElement('style');
                style.id = 'pinggo-adblock-styles';
                let css = `
                    .ad, .ads, .adsbygoogle, .ad-container, .ad-banner, .advertisement,
                    [id^='ad_'], [id^='google_ads_'], [class*='sponsored'], [class*='promoted'],
                    .ad-box, .banner-ad, iframe[id*='google_ads'], div[data-ad-unit],
                    .sidebar-ads, [data-ad-slot], .native-ad, .outbrain, .taboola,
                    #onetrust-banner-sdk, .cookie-banner, .cookie-consent, #cookie-notice {
                        display: none !important;
                    }
                `;
                if (blockYT) {
                    css += `
                        ytd-ad-slot-renderer,
                        ytd-rich-item-renderer:has(ytd-ad-slot-renderer),
                        ytd-rich-section-renderer:has(ytd-statement-banner-renderer),
                        ytd-in-feed-ad-layout-renderer,
                        ytd-banner-promo-renderer,
                        ytd-statement-banner-renderer,
                        #masthead-ad,
                        ytd-engagement-panel-section-list-renderer[target-id='engagement-panel-ads'],
                        .ytp-ad-overlay-container,
                        .ytp-ad-message-container,
                        .ytp-ad-progress-list,
                        .ytp-ad-player-overlay,
                        .ytp-ad-player-overlay-layout,
                        .ytp-ad-action-interstitial,
                        #player-ads,
                        ytd-promoted-sparkles-web-renderer,
                        ytd-compact-promoted-video-renderer,
                        ytd-promoted-video-renderer,
                        ytd-display-ad-renderer,
                        .sparkles-light-cta,
                        ytd-feed-nudge-renderer,
                        ytd-search-pyv-renderer,
                        ytd-merch-shelf-renderer,
                        .ytd-mealbar-promo-renderer,
                        ytd-enforcement-message-view-model,
                        tp-yt-paper-dialog:has(ytd-enforcement-message-view-model),
                        tp-yt-iron-overlay-backdrop {
                            display: none !important;
                        }
                    `;
                }
                style.textContent = css;
                const head = document.head || document.documentElement;
                if (head) head.appendChild(style);
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', injectStyles, { once: true });
            } else {
                injectStyles();
            }
        })();
        """
    }

    static func runtimeScript(blockYouTube: Bool = true) -> String {
        """
        (() => {
            if (window.__pinggo_runtime_injected) return;
            window.__pinggo_runtime_injected = true;

            const blockYT = \(blockYouTube);
            let skippedAds = 0;
            let lastReported = -1;

            const skipSelectors = [
                '.ytp-ad-skip-button',
                '.ytp-ad-skip-button-modern',
                '.ytp-skip-ad-button',
                '.ytp-ad-skip-button-slot button',
                'button.ytp-ad-skip-button-modern',
                '.ytp-ad-overlay-close-button',
                '[id^="skip-button"] button',
                '.videoAdUiSkipButton'
            ];

            function handleAds() {
                if (!blockYT) return;
                const isYouTube = window.location.hostname.includes('youtube.com');
                if (!isYouTube) return;

                // 1. Bypass & dismiss anti-adblock enforcement dialog
                const enforcement = document.querySelector('ytd-enforcement-message-view-model');
                if (enforcement) {
                    const dialog = enforcement.closest('tp-yt-paper-dialog') || enforcement;
                    try { dialog.remove(); } catch(e) {}
                    document.querySelectorAll('tp-yt-iron-overlay-backdrop').forEach(b => {
                        try { b.remove(); } catch(e) {}
                    });
                    document.body.style.overflow = 'auto';
                    const v = document.querySelector('video');
                    if (v && v.paused) {
                        v.play().catch(() => {});
                    }
                    skippedAds++;
                }

                // 2. Video ad detection & high-speed fast forward
                const player = document.getElementById('movie_player') || document.querySelector('.html5-video-player');
                const isAdShowing = player && (
                    player.classList.contains('ad-showing') ||
                    player.classList.contains('ad-interrupting') ||
                    document.querySelector('.ytp-ad-player-overlay') !== null
                );

                if (isAdShowing) {
                    // Click skip button immediately
                    for (const sel of skipSelectors) {
                        const btn = document.querySelector(sel);
                        if (btn && typeof btn.click === 'function') {
                            btn.click();
                            break;
                        }
                    }

                    // Native player skip if supported
                    if (player && typeof player.skipAd === 'function') {
                        try { player.skipAd(); } catch(e) {}
                    }

                    const video = document.querySelector('video.html5-main-video') || document.querySelector('video');
                    if (video) {
                        if (!video.muted) {
                            video.muted = true;
                            video.__pinggo_ad_muted = true;
                        }
                        video.playbackRate = 16.0;
                        if (isFinite(video.duration) && video.duration > 0) {
                            video.currentTime = video.duration - 0.02;
                        } else {
                            video.currentTime = 99999;
                        }
                        skippedAds++;
                    }
                } else {
                    const video = document.querySelector('video.html5-main-video') || document.querySelector('video');
                    if (video) {
                        if (video.__pinggo_ad_muted) {
                            video.muted = false;
                            video.__pinggo_ad_muted = false;
                        }
                        if (video.playbackRate > 4.0) {
                            video.playbackRate = 1.0;
                        }
                    }
                }
            }

            if (blockYT) {
                setInterval(handleAds, 50);
                try {
                    const observer = new MutationObserver(() => handleAds());
                    observer.observe(document.body || document.documentElement, {
                        childList: true,
                        subtree: true,
                        attributes: true,
                        attributeFilter: ['class', 'src']
                    });
                } catch(e) {}
            }

            function inspectBlockedAds() {
                const adNodes = document.querySelectorAll(
                    '.ad, .ads, .adsbygoogle, .ad-container, .ad-banner, .advertisement, [id^="ad_"], [id^="google_ads_"], [class*="sponsored"], [class*="promoted"], .banner-ad, iframe[id*="google_ads"], div[data-ad-unit], ytd-ad-slot-renderer, ytd-banner-promo-renderer, #masthead-ad'
                );
                let hiddenCount = 0;
                adNodes.forEach(node => {
                    const style = window.getComputedStyle(node);
                    if (style.display === 'none' || node.offsetParent === null) {
                        hiddenCount++;
                    }
                });

                const total = hiddenCount + skippedAds;
                if (total !== lastReported) {
                    lastReported = total;
                    try {
                        window.webkit.messageHandlers.pinggoAdBlock.postMessage({ count: total });
                    } catch(e) {}
                }
            }

            setInterval(inspectBlockedAds, 1200);
            inspectBlockedAds();
        })();
        """
    }

    @MainActor
    static func compileRuleList(completion: @escaping @MainActor @Sendable (WKContentRuleList?) -> Void) {
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "PinggoAdBlockRuleList",
            encodedContentRuleList: rulesJSON
        ) { ruleList, error in
            if let error = error {
                print("[PinggoAdBlock] Rule list compilation failed: \(error)")
            } else {
                print("[PinggoAdBlock] Rule list compiled successfully")
            }
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
    var faviconURLString: String? = nil
}

struct SavedBrowserSession: Codable {
    let tabs: [SavedBrowserTab]
    let activeTabID: UUID
}

// MARK: - Browser History Model
struct BrowserHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let urlString: String
    let visitedAt: Date
    var faviconURLString: String?

    init(id: UUID = UUID(), title: String, urlString: String, visitedAt: Date = Date(), faviconURLString: String? = nil) {
        self.id = id
        self.title = title.isEmpty ? (URL(string: urlString)?.host ?? urlString) : title
        self.urlString = urlString
        self.visitedAt = visitedAt
        self.faviconURLString = faviconURLString
    }
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
    var faviconURL: URL? = nil
    var isIncognito: Bool = false
}

// MARK: - Dedicated Tab WKWebView Subclass
final class PinggoTabWebView: WKWebView {
    let tabID: UUID
    let isIncognito: Bool

    init(tabID: UUID, frame: CGRect, configuration: WKWebViewConfiguration, isIncognito: Bool = false) {
        self.tabID = tabID
        self.isIncognito = isIncognito
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
    private let whitelistKey = "pinggo.browser.whitelisted_domains"
    private let historyKey = "pinggo.browser.saved_history"

    @Published var tabs: [BrowserTabItem] = []
    @Published var activeTabID: UUID = UUID()
    @Published var whitelistedDomains: Set<String> = []
    @Published var history: [BrowserHistoryItem] = []

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
    @Published var blockYouTubeAds: Bool = true
    @Published var blockTrackers: Bool = true
    @Published var blockCookieBanners: Bool = true

    // Find in Page State
    @Published var isFindInPageActive: Bool = false
    @Published var findQuery: String = ""
    @Published var findMatchCount: Int = 0
    @Published var currentMatchIndex: Int = 0

    // Zoom State
    @Published var currentZoom: Double = 1.0

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

    var currentHost: String? {
        currentURL?.host?.lowercased()
    }

    var isCurrentDomainWhitelisted: Bool {
        guard let host = currentHost else { return false }
        return whitelistedDomains.contains(host)
    }

    init() {
        // 1. Restore bookmarks if previously customized
        if let bData = UserDefaults.standard.data(forKey: bookmarksKey),
           let bDecoded = try? JSONDecoder().decode([BrowserBookmark].self, from: bData),
           !bDecoded.isEmpty {
            self.bookmarks = bDecoded
        }

        // 2. Restore whitelisted AdBlock domains
        if let wData = UserDefaults.standard.data(forKey: whitelistKey),
           let wDecoded = try? JSONDecoder().decode([String].self, from: wData) {
            self.whitelistedDomains = Set(wDecoded)
        }

        // 3. Restore saved session or fallback to blank New Tab
        if let data = UserDefaults.standard.data(forKey: sessionKey),
           let session = try? JSONDecoder().decode(SavedBrowserSession.self, from: data),
           !session.tabs.isEmpty {
            var restoredTabs: [BrowserTabItem] = []
            for saved in session.tabs {
                let currentURL = saved.urlString.isEmpty ? nil : URL(string: saved.urlString)
                let favURL = saved.faviconURLString.flatMap { URL(string: $0) } ?? (currentURL?.host.flatMap { URL(string: "https://www.google.com/s2/favicons?domain=\($0)&sz=64") })
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
                    readerContent: nil,
                    faviconURL: favURL
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
                    readerContent: nil,
                    faviconURL: nil
                )
            ]
        }

        // 4. Restore browsing history
        if let hData = UserDefaults.standard.data(forKey: historyKey),
           let hDecoded = try? JSONDecoder().decode([BrowserHistoryItem].self, from: hData) {
            self.history = hDecoded
        }

        AdBlockEngine.compileRuleList { [weak self] list in
            guard let self = self else { return }
            self.contentRuleList = list
            self.applyAdBlockerState()
        }
    }

    func saveSession() {
        saveActiveTabSnapshot()
        let savedTabs = tabs.filter { !$0.isIncognito }.map { tab in
            SavedBrowserTab(
                id: tab.id,
                title: tab.title,
                urlString: tab.urlString,
                pageTitle: tab.pageTitle,
                isReaderModeActive: tab.isReaderModeActive,
                blockedAdsCount: tab.blockedAdsCount,
                faviconURLString: tab.faviconURL?.absoluteString
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

        let tab = tabs.first(where: { $0.id == tabID })
        let isIncognito = tab?.isIncognito ?? false

        let configuration = WKWebViewConfiguration()
        if isIncognito {
            configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let host = tab?.currentURL?.host?.lowercased()
        let isWhitelisted = host != nil && whitelistedDomains.contains(host!)
        if isAdBlockerActive && !isWhitelisted {
            if let ruleList = contentRuleList {
                configuration.userContentController.add(ruleList)
            }
            configuration.userContentController.addUserScript(
                WKUserScript(source: AdBlockEngine.earlyScript(blockYouTube: blockYouTubeAds), injectionTime: .atDocumentStart, forMainFrameOnly: false)
            )
            configuration.userContentController.addUserScript(
                WKUserScript(source: AdBlockEngine.runtimeScript(blockYouTube: blockYouTubeAds), injectionTime: .atDocumentEnd, forMainFrameOnly: false)
            )
        }
        configuration.userContentController.add(coordinator, name: "pinggoAdBlock")
        configuration.userContentController.addUserScript(
            WKUserScript(source: VideoDownloadManager.snifferScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        configuration.userContentController.add(coordinator, name: "pinggoVideoSniffer")
        configuration.userContentController.add(coordinator, name: "pinggoVideoDownload")

        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let wv = PinggoTabWebView(tabID: tabID, frame: .zero, configuration: configuration, isIncognito: isIncognito)
        wv.navigationDelegate = coordinator
        wv.uiDelegate = coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.pageZoom = CGFloat(currentZoom)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"

        tabWebViews[tabID] = wv
        coordinator.setupObservation(tabID: tabID, webView: wv)

        // If tab has a saved URL, load it into this new webView
        if let tab = tabs.first(where: { $0.id == tabID }), let url = tab.currentURL, wv.url == nil {
            wv.load(URLRequest(url: url))
        }

        return wv
    }

    func addNewTab(urlString: String = "", isIncognito: Bool = false) {
        saveActiveTabSnapshot()
        let newID = UUID()
        let initialURL = urlString.isEmpty ? nil : (URL(string: urlString) ?? searchURL(for: urlString))
        let newTab = BrowserTabItem(
            id: newID,
            title: isIncognito ? "Private Tab" : "New Tab",
            urlString: initialURL?.absoluteString ?? "",
            currentURL: initialURL,
            pageTitle: "",
            isLoading: false,
            estimatedProgress: 0.0,
            canGoBack: false,
            canGoForward: false,
            blockedAdsCount: 0,
            isReaderModeActive: false,
            readerContent: nil,
            faviconURL: nil,
            isIncognito: isIncognito
        )
        tabs.append(newTab)
        activeTabID = newID
        restoreTab(newTab)
        if !isIncognito {
            saveSession()
        }

        if let target = initialURL {
            activeWebView?.load(URLRequest(url: target))
        }
    }

    func addNewIncognitoTab() {
        addNewTab(urlString: "", isIncognito: true)
    }

    var activeTabIsIncognito: Bool {
        tabs.first(where: { $0.id == activeTabID })?.isIncognito ?? false
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
        VideoDownloadManager.shared.clearDetectedVideos(forTabID: id)
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

    func applyAdBlockerState() {
        for (tabID, wv) in tabWebViews {
            let ucc = wv.configuration.userContentController
            if let ruleList = contentRuleList {
                ucc.remove(ruleList)
            }
            ucc.removeAllUserScripts()
            let tab = tabs.first(where: { $0.id == tabID })
            let host = tab?.currentURL?.host?.lowercased()
            let isWhitelisted = host != nil && whitelistedDomains.contains(host!)
            if isAdBlockerActive && !isWhitelisted {
                if let ruleList = contentRuleList {
                    ucc.add(ruleList)
                }
                ucc.addUserScript(
                    WKUserScript(source: AdBlockEngine.earlyScript(blockYouTube: blockYouTubeAds), injectionTime: .atDocumentStart, forMainFrameOnly: false)
                )
                ucc.addUserScript(
                    WKUserScript(source: AdBlockEngine.runtimeScript(blockYouTube: blockYouTubeAds), injectionTime: .atDocumentEnd, forMainFrameOnly: false)
                )
            }
        }
    }

    func toggleYouTubeAdBlocker() {
        blockYouTubeAds.toggle()
        applyAdBlockerState()
        if let host = currentHost, host.contains("youtube.com") {
            activeWebView?.reload()
        }
    }

    func toggleAdBlocker() {
        isAdBlockerActive.toggle()
        applyAdBlockerState()
        activeWebView?.reload()
    }

    func toggleWhitelistCurrentDomain() {
        guard let host = currentHost, !host.isEmpty else { return }
        if whitelistedDomains.contains(host) {
            whitelistedDomains.remove(host)
        } else {
            whitelistedDomains.insert(host)
        }
        if let data = try? JSONEncoder().encode(Array(whitelistedDomains)) {
            UserDefaults.standard.set(data, forKey: whitelistKey)
        }
        applyAdBlockerState()
        activeWebView?.reload()
    }

    // MARK: - Zoom Controls
    func zoomIn() {
        currentZoom = min(3.0, (currentZoom + 0.1 * 10).rounded() / 10)
        activeWebView?.pageZoom = CGFloat(currentZoom)
    }

    func zoomOut() {
        currentZoom = max(0.5, (currentZoom - 0.1 * 10).rounded() / 10)
        activeWebView?.pageZoom = CGFloat(currentZoom)
    }

    func resetZoom() {
        currentZoom = 1.0
        activeWebView?.pageZoom = 1.0
    }

    // MARK: - Find in Page
    func showFindInPage() {
        isFindInPageActive = true
        if !findQuery.isEmpty {
            performFind(forward: true)
        }
    }

    func hideFindInPage() {
        isFindInPageActive = false
        findQuery = ""
        findMatchCount = 0
        currentMatchIndex = 0
        activeWebView?.evaluateJavaScript("window.getSelection()?.removeAllRanges();", completionHandler: nil)
    }

    func updateFindQuery(_ query: String) {
        findQuery = query
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            findMatchCount = 0
            currentMatchIndex = 0
            activeWebView?.evaluateJavaScript("window.getSelection()?.removeAllRanges();", completionHandler: nil)
            return
        }
        countMatches(query: query)
        performFind(forward: true)
    }

    func findNext() {
        guard !findQuery.isEmpty else { return }
        if findMatchCount > 0 {
            currentMatchIndex = (currentMatchIndex % findMatchCount) + 1
        }
        performFind(forward: true)
    }

    func findPrevious() {
        guard !findQuery.isEmpty else { return }
        if findMatchCount > 0 {
            currentMatchIndex = (currentMatchIndex - 2 + findMatchCount) % findMatchCount + 1
        }
        performFind(forward: false)
    }

    private func performFind(forward: Bool) {
        guard let wv = activeWebView, !findQuery.isEmpty else { return }
        let escaped = findQuery
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "window.find(\"\(escaped)\", false, \(!forward), true, false, true, false);"
        wv.evaluateJavaScript(script, completionHandler: nil)
    }

    private func countMatches(query: String) {
        guard let wv = activeWebView else { return }
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        (() => {
            try {
                const text = document.body ? document.body.innerText : '';
                const query = "\(escaped)";
                if (!query) return 0;
                const escapedQuery = query.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                const regex = new RegExp(escapedQuery, 'gi');
                const matches = text.match(regex);
                return matches ? matches.length : 0;
            } catch(e) {
                return 0;
            }
        })();
        """
        wv.evaluateJavaScript(script) { [weak self] result, _ in
            DispatchQueue.main.async {
                if let count = result as? Int {
                    self?.findMatchCount = count
                    if count > 0 && self?.currentMatchIndex == 0 {
                        self?.currentMatchIndex = 1
                    } else if count == 0 {
                        self?.currentMatchIndex = 0
                    }
                }
            }
        }
    }

    func reorderTab(draggedID: UUID, targetID: UUID) {
        guard draggedID != targetID,
              let fromIndex = tabs.firstIndex(where: { $0.id == draggedID }),
              let toIndex = tabs.firstIndex(where: { $0.id == targetID }) else { return }
        let item = tabs.remove(at: fromIndex)
        tabs.insert(item, at: toIndex)
        saveSession()
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
            if !tabs[idx].isIncognito, let url = tabs[idx].currentURL {
                updateHistoryTitle(url: url, title: title)
            }
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
            if let host = url.host, !host.isEmpty {
                tabs[idx].faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
            }
            if tabs[idx].title.isEmpty || tabs[idx].title == "New Tab" {
                tabs[idx].title = url.host ?? url.absoluteString
            }
            if !tabs[idx].isIncognito {
                recordHistory(url: url, title: tabs[idx].title, faviconURL: tabs[idx].faviconURL)
            }
        }
        if id == activeTabID {
            self.currentURL = url
            self.urlInput = url.absoluteString
            applyAdBlockerState()
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

    // MARK: - Browsing History Methods
    func recordHistory(url: URL, title: String, faviconURL: URL?) {
        let urlStr = url.absoluteString
        guard !urlStr.isEmpty, urlStr.hasPrefix("http") else { return }

        // Deduplicate consecutive visits to identical URL within 10 seconds
        if let first = history.first, first.urlString == urlStr, abs(first.visitedAt.timeIntervalSinceNow) < 10 {
            return
        }

        let item = BrowserHistoryItem(
            title: title.isEmpty ? (url.host ?? urlStr) : title,
            urlString: urlStr,
            visitedAt: Date(),
            faviconURLString: faviconURL?.absoluteString
        )
        history.insert(item, at: 0)
        if history.count > 2500 {
            history.removeLast(history.count - 2500)
        }
        saveHistory()
    }

    func updateHistoryTitle(url: URL, title: String) {
        let urlStr = url.absoluteString
        guard !title.isEmpty, !urlStr.isEmpty else { return }
        if let idx = history.firstIndex(where: { $0.urlString == urlStr && abs($0.visitedAt.timeIntervalSinceNow) < 60 }) {
            history[idx].title = title
            saveHistory()
        }
    }

    func removeHistoryItem(id: UUID) {
        history.removeAll(where: { $0.id == id })
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    func clearBrowsingData(clearHistory: Bool, clearCookies: Bool, clearCache: Bool, completion: (@MainActor @Sendable () -> Void)? = nil) {
        if clearHistory {
            self.clearHistory()
        }
        var dataTypes = Set<String>()
        if clearCookies {
            dataTypes.insert(WKWebsiteDataTypeCookies)
            dataTypes.insert(WKWebsiteDataTypeLocalStorage)
            dataTypes.insert(WKWebsiteDataTypeSessionStorage)
            dataTypes.insert(WKWebsiteDataTypeIndexedDBDatabases)
            dataTypes.insert(WKWebsiteDataTypeWebSQLDatabases)
        }
        if clearCache {
            dataTypes.insert(WKWebsiteDataTypeDiskCache)
            dataTypes.insert(WKWebsiteDataTypeMemoryCache)
        }
        if !dataTypes.isEmpty {
            WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
                Task { @MainActor in
                    completion?()
                }
            }
        } else {
            completion?()
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
    @State private var showingHistoryPopover: Bool = false
    @State private var showingClearDataDialog: Bool = false
    @State private var historySearchQuery: String = ""
    @State private var clearHistoryChecked: Bool = true
    @State private var clearCookiesChecked: Bool = true
    @State private var clearCacheChecked: Bool = true
    @State private var isClearingData: Bool = false
    @State private var draggedTabID: UUID? = nil
    @ObservedObject private var downloadManager: VideoDownloadManager = VideoDownloadManager.shared

    private var activeTabVideos: [DetectedVideoMedia] {
        downloadManager.detectedVideosByTab[browserState.activeTabID] ?? []
    }

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
            ZStack(alignment: .topTrailing) {
                if browserState.isReaderModeActive, let content = browserState.readerContent {
                    readerModeView(content: content)
                } else {
                    BrowserWebContainer(state: browserState)
                        .opacity(browserState.currentURL == nil ? 0 : 1)

                    if browserState.currentURL == nil {
                        BrowserStartPage(state: browserState)
                    }
                }

                if browserState.isFindInPageActive {
                    findInPageOverlay
                        .padding(.top, 10)
                        .padding(.trailing, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.background)
            .background {
                // Invisible buttons for global shortcuts within BrowserView
                Group {
                    Button("") {
                        if browserState.isFindInPageActive {
                            browserState.hideFindInPage()
                        } else {
                            browserState.showFindInPage()
                        }
                    }
                    .keyboardShortcut("f", modifiers: .command)

                    Button("") { browserState.zoomIn() }
                        .keyboardShortcut("=", modifiers: .command)

                    Button("") { browserState.zoomIn() }
                        .keyboardShortcut("+", modifiers: .command)

                    Button("") { browserState.zoomOut() }
                        .keyboardShortcut("-", modifiers: .command)

                    Button("") { browserState.resetZoom() }
                        .keyboardShortcut("0", modifiers: .command)

                    Button("") { showingHistoryPopover.toggle() }
                        .keyboardShortcut("y", modifiers: .command)

                    Button("") { browserState.addNewIncognitoTab() }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                }
                .opacity(0)
                .allowsHitTesting(false)
            }

            // 4. Download Notification Toast Banner
            if let notice = downloadManager.notificationMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(notice)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Show in Downloads") {
                        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                        NSWorkspace.shared.open(downloadsDir)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
                            } else if let fav = tab.faviconURL {
                                AsyncImage(url: fav) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable()
                                            .scaledToFit()
                                            .frame(width: 12, height: 12)
                                            .clipShape(RoundedRectangle(cornerRadius: 2))
                                    default:
                                        Image(systemName: "globe")
                                            .font(.system(size: 10))
                                            .foregroundStyle(isActive ? Palette.accent : Palette.muted)
                                    }
                                }
                                .frame(width: 12, height: 12)
                            } else {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                    .foregroundStyle(isActive ? Palette.accent : Palette.muted)
                            }

                            if tab.isIncognito {
                                Image(systemName: "eye.slash.fill")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.purple)
                            }

                            Text(tab.title.isEmpty ? (tab.isIncognito ? "Private Tab" : "New Tab") : tab.title)
                                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(isActive ? (tab.isIncognito ? Color.purple : Color.primary) : Palette.muted)
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
                            isActive ? (tab.isIncognito ? Color.purple.opacity(0.18) : Palette.panel) : Palette.card.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isActive ? (tab.isIncognito ? Color.purple.opacity(0.6) : Palette.accent.opacity(0.5)) : Palette.border.opacity(0.5), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            browserState.selectTab(id: tab.id)
                        }
                        .onDrag {
                            self.draggedTabID = tab.id
                            return NSItemProvider(object: tab.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], isTargeted: nil) { _ in
                            guard let dragged = self.draggedTabID, dragged != tab.id else { return false }
                            browserState.reorderTab(draggedID: dragged, targetID: tab.id)
                            self.draggedTabID = nil
                            return true
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            // New Tab & Private Tab buttons
            HStack(spacing: 4) {
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

                Button {
                    browserState.addNewIncognitoTab()
                } label: {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.purple)
                        .frame(width: 24, height: 24)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.purple.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("New Private Tab (⌘⇧N)")
            }
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

            // Video Downloader Pill
            if !activeTabVideos.isEmpty {
                videoDownloaderPill
            }

            // Download Tracker Pill
            let ongoingDownloads = downloadManager.activeDownloads.filter { !$0.isComplete && $0.error == nil }
            if !browserState.recentDownloads.isEmpty || !downloadManager.activeDownloads.isEmpty {
                Button {
                    showingDownloadsPopover.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.accent)
                        if !ongoingDownloads.isEmpty {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 12, height: 12)
                            Text("\(ongoingDownloads.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.accent)
                        } else {
                            Text("\(browserState.recentDownloads.count + downloadManager.activeDownloads.filter { $0.isComplete }.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(Palette.accent.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Palette.accent.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Downloads & Media Progress")
                .popover(isPresented: $showingDownloadsPopover, arrowEdge: .bottom) {
                    downloadsPopoverContent
                }
            }

            // Action controls
            HStack(spacing: 6) {
                // Find in Page Button
                Button {
                    if browserState.isFindInPageActive {
                        browserState.hideFindInPage()
                    } else {
                        browserState.showFindInPage()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(browserState.isFindInPageActive ? Palette.accent : Color.primary.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(browserState.isFindInPageActive ? Palette.accent.opacity(0.15) : Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(browserState.isFindInPageActive ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Find in Page (⌘F)")

                // Zoom Level Controls
                Menu {
                    Button("Zoom In (⌘+)") { browserState.zoomIn() }
                    Button("Zoom Out (⌘-)") { browserState.zoomOut() }
                    Divider()
                    Button("Reset to 100% (⌘0)") { browserState.resetZoom() }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "textformat.size")
                            .font(.system(size: 10))
                        Text("\(Int((browserState.currentZoom * 100).rounded()))%")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .padding(.horizontal, 6)
                    .frame(height: 32)
                    .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 64)
                .help("Page Zoom Level (⌘+ / ⌘-)")

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

                // Browsing History Popover Button
                Button { showingHistoryPopover.toggle() } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(showingHistoryPopover ? Palette.accent : Color.primary.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(showingHistoryPopover ? Palette.accent.opacity(0.15) : Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(showingHistoryPopover ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Browsing History (⌘Y)")
                .popover(isPresented: $showingHistoryPopover, arrowEdge: .bottom) {
                    historyPopoverContent
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
                // Security / Search / Private Indicator
                if browserState.activeTabIsIncognito {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 9))
                        Text("Private")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.purple.opacity(0.15), in: Capsule())
                } else if browserState.currentURL != nil {
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
                if browserState.isCurrentDomainWhitelisted {
                    Image(systemName: "shield.slash.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.orange)

                    Text("Paused")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.orange)
                } else {
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
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                browserState.isCurrentDomainWhitelisted
                    ? Color.orange.opacity(0.12)
                    : (browserState.isAdBlockerActive ? Color.green.opacity(0.12) : Palette.card.opacity(0.5)),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    browserState.isCurrentDomainWhitelisted
                        ? Color.orange.opacity(0.3)
                        : (browserState.isAdBlockerActive ? Color.green.opacity(0.3) : Palette.border),
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
                Image(systemName: browserState.isCurrentDomainWhitelisted ? "shield.slash.fill" : "shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(browserState.isCurrentDomainWhitelisted ? Color.orange : (browserState.isAdBlockerActive ? Color.green : Palette.muted))

                VStack(alignment: .leading, spacing: 2) {
                    Text("PINGGO AdBlocker Shield")
                        .font(.system(size: 13, weight: .bold))
                    Text(browserState.isCurrentDomainWhitelisted ? "Domain Whitelisted" : (browserState.isAdBlockerActive ? "Actively blocking third-party ads & trackers" : "Protection paused"))
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

            // Per-site Whitelisting Section
            if let host = browserState.currentHost, !host.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host)
                                .font(.system(size: 11.5, weight: .bold))
                                .lineLimit(1)
                            Text(browserState.isCurrentDomainWhitelisted ? "AdBlock paused for this site" : "AdBlock active for this site")
                                .font(.system(size: 10))
                                .foregroundStyle(browserState.isCurrentDomainWhitelisted ? Color.orange : Color.green)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { browserState.isCurrentDomainWhitelisted },
                            set: { _ in browserState.toggleWhitelistCurrentDomain() }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    Text("Whitelist site to support creators or if a website is broken.")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
                .padding(10)
                .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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
                    Text("YouTube pre-roll & mid-roll ads eliminated")
                        .font(.system(size: 11))
                }
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
                    Text("Anti-adblock detection bypassed")
                        .font(.system(size: 11))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("PROTECTION CATEGORIES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.muted)

                HStack {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                    Text("YouTube Video Ads & Promos")
                        .font(.system(size: 11.5))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { browserState.blockYouTubeAds },
                        set: { _ in browserState.toggleYouTubeAdBlocker() }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

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

    // MARK: - Video Downloader Pill
    private var videoDownloaderPill: some View {
        Menu {
            ForEach(activeTabVideos) { media in
                Section(header: Text(media.title).lineLimit(1)) {
                    ForEach(media.availableOptions) { opt in
                        Button {
                            downloadManager.startDownload(media: media, quality: opt, webView: browserState.activeWebView)
                        } label: {
                            HStack {
                                Text(opt.label)
                                Spacer()
                                Text(opt.format.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Text("Download Video (\(activeTabVideos.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.accent.opacity(0.8))
            }
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(Palette.accent.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Palette.accent.opacity(0.4), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .help("Download video with audio in full quality or selected resolution")
    }

    // MARK: - Downloads Popover Content
    private var downloadsPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Palette.accent)
                Text("Downloads & Media")
                    .font(.system(size: 12.5, weight: .bold))
                Spacer()
                Button("Clear") {
                    browserState.recentDownloads.removeAll()
                    downloadManager.activeDownloads.removeAll(where: { $0.isComplete })
                    showingDownloadsPopover = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
            }
            Divider()

            // Active Video Downloads
            let ongoing = downloadManager.activeDownloads.filter { !$0.isComplete }
            if !ongoing.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE DOWNLOADS")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Palette.accent)
                    ForEach(ongoing) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(item.qualityLabel)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(Palette.muted)
                            }
                            ProgressView(value: item.progress)
                                .progressViewStyle(.linear)
                            HStack {
                                Text(item.statusText)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(item.error != nil ? Color.red : Palette.muted)
                                Spacer()
                                Text("\(Int(item.progress * 100))%")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                        .padding(6)
                        .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Divider()
                }
            }

            // Completed Video Downloads
            let completedVideos = downloadManager.activeDownloads.filter { $0.isComplete && $0.savedFileURL != nil }
            if !completedVideos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("COMPLETED VIDEOS")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Palette.muted)
                    ForEach(completedVideos.suffix(5).reversed()) { item in
                        if let fileURL = item.savedFileURL {
                            HStack(spacing: 8) {
                                Image(systemName: "film.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 11.5))
                                        .lineLimit(1)
                                    Text(item.qualityLabel)
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(.plain)
                                .help("Show in Finder")

                                Button {
                                    NSWorkspace.shared.open(fileURL)
                                } label: {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(.plain)
                                .help("Play Video")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    if !browserState.recentDownloads.isEmpty {
                        Divider()
                    }
                }
            }

            // Other Recent Downloads
            if !browserState.recentDownloads.isEmpty {
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
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Find In Page Overlay
    private var findInPageOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)

            TextField("Find in page…", text: Binding(
                get: { browserState.findQuery },
                set: { browserState.updateFindQuery($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .frame(width: 140)
            .onSubmit {
                browserState.findNext()
            }

            if !browserState.findQuery.isEmpty {
                Text(browserState.findMatchCount > 0 ? "\(browserState.currentMatchIndex) of \(browserState.findMatchCount)" : "0 matches")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(browserState.findMatchCount > 0 ? Palette.muted : Color.red.opacity(0.85))
            }

            Divider().frame(height: 14)

            Button { browserState.findPrevious() } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 20, height: 20)
                    .background(Palette.hover, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Previous match (Shift+Enter)")

            Button { browserState.findNext() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 20, height: 20)
                    .background(Palette.hover, in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Next match (Enter)")

            Button { browserState.hideFindInPage() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 20, height: 20)
                    .background(Palette.hover, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.card, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
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

    // MARK: - History Popover Content
    private var historyPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Palette.accent)
                    Text("Browsing History")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                Button("Clear Data…") {
                    showingClearDataDialog = true
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Search filter
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                TextField("Search history…", text: $historySearchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                if !historySearchQuery.isEmpty {
                    Button {
                        historySearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.card, lineWidth: 1))

            Divider()

            let filteredHistory = browserState.history.filter { item in
                if historySearchQuery.isEmpty { return true }
                let q = historySearchQuery.lowercased()
                return item.title.lowercased().contains(q) || item.urlString.lowercased().contains(q)
            }

            if filteredHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 24))
                        .foregroundStyle(Palette.muted.opacity(0.6))
                    Text(historySearchQuery.isEmpty ? "No browsing history recorded" : "No matching history results")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        let grouped = groupHistoryByDate(filteredHistory)
                        ForEach(grouped, id: \.section) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.section.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.muted)
                                    .padding(.horizontal, 4)

                                ForEach(group.items) { item in
                                    HStack(spacing: 8) {
                                        if let favStr = item.faviconURLString, let favURL = URL(string: favStr) {
                                            AsyncImage(url: favURL) { phase in
                                                switch phase {
                                                case .success(let img):
                                                    img.resizable().scaledToFit().frame(width: 14, height: 14).clipShape(RoundedRectangle(cornerRadius: 2))
                                                default:
                                                    Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(Palette.muted)
                                                }
                                            }
                                            .frame(width: 14, height: 14)
                                        } else {
                                            Image(systemName: "globe")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Palette.muted)
                                                .frame(width: 14, height: 14)
                                        }

                                        VStack(alignment: .leading, spacing: 1.5) {
                                            Text(item.title)
                                                .font(.system(size: 11.5, weight: .medium))
                                                .foregroundStyle(Color.primary)
                                                .lineLimit(1)

                                            Text(URL(string: item.urlString)?.host ?? item.urlString)
                                                .font(.system(size: 10))
                                                .foregroundStyle(Palette.muted)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Text(formatHistoryTime(item.visitedAt))
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(Palette.muted)

                                        // Open in new tab
                                        Button {
                                            browserState.addNewTab(urlString: item.urlString)
                                            showingHistoryPopover = false
                                        } label: {
                                            Image(systemName: "plus.square.on.square")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Palette.muted)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Open in New Tab")

                                        // Delete item
                                        Button {
                                            browserState.removeHistoryItem(id: item.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(Palette.muted)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove from history")
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Palette.hover.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        browserState.load(urlString: item.urlString)
                                        showingHistoryPopover = false
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 300)
            }
        }
        .padding(14)
        .frame(width: 360)
        .sheet(isPresented: $showingClearDataDialog) {
            clearBrowsingDataModal
        }
    }

    // MARK: - Clear Browsing Data Modal
    private var clearBrowsingDataModal: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.red)
                Text("Clear Browsing Data")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    showingClearDataDialog = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.muted)
                }
                .buttonStyle(.plain)
            }

            Text("Select data types to remove from PINGGO:")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $clearHistoryChecked) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browsing History")
                            .font(.system(size: 12, weight: .medium))
                        Text("Clears recorded page visits and URLs")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                }

                Toggle(isOn: $clearCookiesChecked) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cookies & Site Data")
                            .font(.system(size: 12, weight: .medium))
                        Text("Signs you out of most websites")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                }

                Toggle(isOn: $clearCacheChecked) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cached Images & Files")
                            .font(.system(size: 12, weight: .medium))
                        Text("Frees disk and memory cache")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }
            .padding(12)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Cancel") {
                    showingClearDataDialog = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button {
                    isClearingData = true
                    browserState.clearBrowsingData(
                        clearHistory: clearHistoryChecked,
                        clearCookies: clearCookiesChecked,
                        clearCache: clearCacheChecked
                    ) {
                        isClearingData = false
                        showingClearDataDialog = false
                    }
                } label: {
                    if isClearingData {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small)
                            Text("Clearing...")
                        }
                    } else {
                        Text("Clear Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isClearingData || (!clearHistoryChecked && !clearCookiesChecked && !clearCacheChecked))
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private struct HistoryGroup {
        let section: String
        let items: [BrowserHistoryItem]
    }

    private func groupHistoryByDate(_ items: [BrowserHistoryItem]) -> [HistoryGroup] {
        let calendar = Calendar.current
        var today: [BrowserHistoryItem] = []
        var yesterday: [BrowserHistoryItem] = []
        var last7Days: [BrowserHistoryItem] = []
        var older: [BrowserHistoryItem] = []

        for item in items {
            if calendar.isDateInToday(item.visitedAt) {
                today.append(item)
            } else if calendar.isDateInYesterday(item.visitedAt) {
                yesterday.append(item)
            } else if let daysAgo = calendar.dateComponents([.day], from: item.visitedAt, to: Date()).day, daysAgo <= 7 {
                last7Days.append(item)
            } else {
                older.append(item)
            }
        }

        var res: [HistoryGroup] = []
        if !today.isEmpty { res.append(HistoryGroup(section: "Today", items: today)) }
        if !yesterday.isEmpty { res.append(HistoryGroup(section: "Yesterday", items: yesterday)) }
        if !last7Days.isEmpty { res.append(HistoryGroup(section: "Past 7 Days", items: last7Days)) }
        if !older.isEmpty { res.append(HistoryGroup(section: "Older", items: older)) }
        return res
    }

    private func formatHistoryTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: date)
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
                        Text("Complete AdBlocker Active · YouTube Ads Blocked · Zero Trackers")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.muted)
                    }

                    if state.activeTabIsIncognito {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.purple)
                            Text("Private Mode Active · Zero history or cookies saved")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.purple)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.purple.opacity(0.3), lineWidth: 1))
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
                VideoDownloadManager.shared.clearDetectedVideos(forTabID: tabWV.tabID)
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
            } else if message.name == "pinggoVideoSniffer", let dict = message.body as? [String: Any] {
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

                DispatchQueue.main.async {
                    if let tabWV = message.webView as? PinggoTabWebView {
                        VideoDownloadManager.shared.registerDetectedVideo(media, forTabID: tabWV.tabID)
                    }
                }
            } else if message.name == "pinggoVideoDownload", let dict = message.body as? [String: Any] {
                let action = dict["action"] as? String ?? ""
                if action == "blobChunk" || action == "blobError" {
                    DispatchQueue.main.async {
                        VideoDownloadManager.shared.handleBlobChunkMessage(dict)
                    }
                } else if action == "triggerVideoDownload", let videoId = dict["videoId"] as? String {
                    DispatchQueue.main.async {
                        if let tabWV = message.webView as? PinggoTabWebView,
                           let mediaList = VideoDownloadManager.shared.detectedVideosByTab[tabWV.tabID],
                           let media = mediaList.first(where: { $0.id == videoId }),
                           let best = media.bestQuality {
                            VideoDownloadManager.shared.startDownload(media: media, quality: best, webView: tabWV)
                        }
                    }
                }
            }
        }
    }
}
