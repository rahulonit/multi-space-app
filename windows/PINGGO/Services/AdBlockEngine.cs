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
            "advertising.amazon.com"
        };

        private static readonly Regex AdUrlRegex = new(
            @".*(adserver|adservices|adsystem|googlesyndication|googleadservices|doubleclick|taboola|outbrain|adnxs|carbonads|adroll|popads|popcash).*",
            RegexOptions.Compiled | RegexOptions.IgnoreCase);

        public const string CosmeticCss = """
            .ad, .ads, .adsbygoogle, .ad-container, .ad-banner, .advertisement,
            [id^='ad_'], [id^='google_ads_'], [class*='sponsored'], [class*='promoted'],
            .ad-box, .banner-ad, iframe[id*='google_ads'], div[data-ad-unit],
            .sidebar-ads, [data-ad-slot], .native-ad, .outbrain, .taboola
            { display: none !important; visibility: hidden !important; height: 0 !important; }
        """;

        public const string CountScript = """
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
                            window.chrome.webview.postMessage({ type: 'pinggoAdBlock', count: count });
                        } catch(e) {}
                    }
                }
                setInterval(inspectBlockedAds, 2000);
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

            if (blockAds && AdUrlRegex.IsMatch(uri.AbsoluteUri))
            {
                return true;
            }

            return false;
        }

        public static void AttachToWebView(CoreWebView2 webView, Action<int>? onAdBlocked = null)
        {
            webView.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);

            webView.WebResourceRequested += (s, e) =>
            {
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
                    // Inject cosmetic CSS
                    var cssScript = $"const style = document.createElement('style'); style.textContent = `{CosmeticCss}`; document.head.appendChild(style);";
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
