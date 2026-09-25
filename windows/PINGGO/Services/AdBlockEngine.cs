using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Microsoft.Web.WebView2.Core;

namespace PINGGO.Services
{
    public class AdBlockEngine
    {
        private static readonly HashSet<string> BlockedDomains = new(StringComparer.OrdinalIgnoreCase)
        {
            "doubleclick.net",
            "googleadservices.com",
            "googlesyndication.com",
            "adservice.google.com",
            "googleads.g.doubleclick.net",
            "pagead2.googlesyndication.com",
            "adnxs.com",
            "advertising.com",
            "scorecardresearch.com",
            "criteo.com",
            "outbrain.com",
            "taboola.com",
            "adroll.com",
            "quantserve.com",
            "popads.net",
            "popcash.net",
            "bidswitch.net",
            "rubiconproject.com",
            "pubmatic.com",
            "openx.net",
            "smartadserver.com",
            "amazon-adsystem.com",
            "casalemedia.com",
            "lijit.com",
            "exponential.com",
            "contextweb.com",
            "advertising.amazon.com",
            "media.net",
            "sovrn.com",
            "liveramp.com",
            "inmobi.com",
            "unityads.unity3d.com",
            "applovin.com",
            "ironsrc.com",
            "vungle.com"
        };

        private static readonly Regex AdUrlRegex = new(
            @".*(adserver|adservices|adsystem|googlesyndication|googleadservices|doubleclick|taboola|outbrain|adnxs|carbonads|adroll|popads|popcash|smartadserver|criteo|rubiconproject|pubmatic).*",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);

        private static readonly Regex YouTubeAdUrlRegex = new(
            @".*youtube\.com/(pagead/|api/stats/ads|youtubei/v1/player/ad_break|get_midroll_info|ptracking).*",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);

        public const string CosmeticCss = """
            .ad, .ads, .adsbygoogle, .ad-container, .ad-banner, .advertisement,
            [id^='ad_'], [id^='google_ads_'], [class*='sponsored'], [class*='promoted'],
            .ad-box, .banner-ad, iframe[id*='google_ads'], div[data-ad-unit],
            .sidebar-ads, [data-ad-slot], .native-ad, .outbrain, .taboola,
            #onetrust-banner-sdk, .cookie-banner, .cookie-consent, #cookie-notice,
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
            tp-yt-iron-overlay-backdrop
            { display: none !important; visibility: hidden !important; height: 0 !important; }
        """;

        public const string EarlyScript = """
            (() => {
                if (window.__pinggo_early_injected) return;
                window.__pinggo_early_injected = true;

                function cleanseYT(data) {
                    if (!data || typeof data !== 'object') return;
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
            })();
        """;

        public const string CountScript = """
            (() => {
                if (window.__pinggo_runtime_injected) return;
                window.__pinggo_runtime_injected = true;

                let skippedAds = 0;
                let lastReported = 0;

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

                function handleYouTubeAds() {
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
                        for (const sel of skipSelectors) {
                            const btn = document.querySelector(sel);
                            if (btn && typeof btn.click === 'function') {
                                btn.click();
                                break;
                            }
                        }

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

                setInterval(handleYouTubeAds, 60);

                try {
                    const observer = new MutationObserver(() => handleYouTubeAds());
                    observer.observe(document.body || document.documentElement, {
                        childList: true,
                        subtree: true,
                        attributes: true,
                        attributeFilter: ['class', 'src']
                    });
                } catch(e) {}

                function inspectBlockedAds() {
                    const adNodes = document.querySelectorAll('.ad, .ads, .adsbygoogle, .ad-container, .ad-banner, .advertisement, [id^="ad_"], [id^="google_ads_"], [class*="sponsored"], [class*="promoted"], .banner-ad, iframe[id*="google_ads"], div[data-ad-unit], ytd-ad-slot-renderer, ytd-banner-promo-renderer, #masthead-ad');
                    let count = 0;
                    adNodes.forEach(node => {
                        const style = window.getComputedStyle(node);
                        if (style.display === 'none' || node.offsetParent === null) {
                            count++;
                        }
                    });

                    const total = count + skippedAds;
                    if (total !== lastReported) {
                        lastReported = total;
                        try {
                            window.chrome.webview.postMessage({ type: 'pinggoAdBlock', count: total });
                        } catch(e) {}
                    }
                }
                setInterval(inspectBlockedAds, 1500);
                inspectBlockedAds();
            })();
        """;

        public static bool ShouldBlock(Uri uri, bool blockAds = true, bool blockTrackers = true)
        {
            if (!blockAds && !blockTrackers) return false;

            var host = uri.Host;
            foreach (var blocked in BlockedDomains)
            {
                if (host.EndsWith(blocked, StringComparison.OrdinalIgnoreCase) || host.Equals(blocked, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }

            if (blockAds)
            {
                if (AdUrlRegex.IsMatch(uri.AbsoluteUri) || YouTubeAdUrlRegex.IsMatch(uri.AbsoluteUri))
                {
                    return true;
                }
            }

            return false;
        }

        public static Func<string, bool>? IsDomainWhitelisted { get; set; }

        public static async void AttachToWebView(CoreWebView2 webView, Action<int>? onAdBlocked = null)
        {
            webView.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);

            try
            {
                await webView.AddScriptToExecuteOnDocumentCreatedAsync(EarlyScript);
            }
            catch { }

            webView.WebResourceRequested += (s, e) =>
            {
                var docUri = webView.Source;
                if (!string.IsNullOrEmpty(docUri) && Uri.TryCreate(docUri, UriKind.Absolute, out var topUri))
                {
                    if (IsDomainWhitelisted?.Invoke(topUri.Host) == true)
                    {
                        return; // Whitelisted site: allow all resources
                    }
                }

                if (Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var uri))
                {
                    if (ShouldBlock(uri))
                    {
                        // Block request by returning a 403 response
                        var response = webView.Environment.CreateWebResourceResponse(null, 403, "Blocked by PINGGO AdBlocker", "");
                        e.Response = response;
                    }
                }
            };

            webView.NavigationCompleted += async (s, e) =>
            {
                if (e.IsSuccess)
                {
                    var docUri = webView.Source;
                    if (!string.IsNullOrEmpty(docUri) && Uri.TryCreate(docUri, UriKind.Absolute, out var topUri))
                    {
                        if (IsDomainWhitelisted?.Invoke(topUri.Host) == true)
                        {
                            return; // Whitelisted site: skip hiding cosmetic ads
                        }
                    }

                    // Inject cosmetic CSS
                    var cssScript = $"const style = document.createElement('style'); style.textContent = `{CosmeticCss}`; (document.head || document.documentElement).appendChild(style);";
                    await webView.ExecuteScriptAsync(cssScript);
                    await webView.ExecuteScriptAsync(CountScript);
                }
            };

            webView.WebMessageReceived += (s, e) =>
            {
                try
                {
                    var raw = e.TryGetWebMessageAsString();
                    if (!string.IsNullOrEmpty(raw) && raw.Contains("pinggoAdBlock"))
                    {
                        using var doc = System.Text.Json.JsonDocument.Parse(raw);
                        if (doc.RootElement.TryGetProperty("count", out var countProp))
                        {
                            onAdBlocked?.Invoke(countProp.GetInt32());
                        }
                    }
                }
                catch { }
            };
        }
    }
}
