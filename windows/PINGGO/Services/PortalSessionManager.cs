using System;
using System.Collections.Concurrent;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;
using PINGGO.Models;

namespace PINGGO.Services
{
    public class PortalSessionManager
    {
        private static readonly Lazy<PortalSessionManager> _instance = new(() => new PortalSessionManager());
        public static PortalSessionManager Shared => _instance.Value;

        private readonly ConcurrentDictionary<Guid, CoreWebView2Environment> _environments = new();
        public event Action<Guid, string, int>? OnActivityUpdated;
        public event Action<string>? OnDownloadCaptured;

        public async Task<CoreWebView2Environment> GetOrCreateEnvironmentAsync(PlatformAccount account)
        {
            if (_environments.TryGetValue(account.Id, out var existing))
            {
                return existing;
            }

            var profilePath = DataStoreService.Shared.GetProfileDirectory(account.Id);
            var options = new CoreWebView2EnvironmentOptions();
            var env = await CoreWebView2Environment.CreateAsync(null, profilePath, options);

            _environments[account.Id] = env;
            return env;
        }

        public void ConfigureSessionWebView(CoreWebView2 webView, PlatformAccount account, SocialPlatform platform)
        {
            // 1. Grant microphone and camera automatically for calling
            webView.PermissionRequested += (s, e) =>
            {
                if (e.PermissionKind is CoreWebView2PermissionKind.Microphone or
                    CoreWebView2PermissionKind.Camera or
                    CoreWebView2PermissionKind.Notifications)
                {
                    e.State = CoreWebView2PermissionState.Allow;
                }
            };

            // 2. Download capture
            webView.DownloadStarting += (s, e) =>
            {
                var downloadsDir = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                var downloadsPath = Path.Combine(downloadsDir, "Downloads", Path.GetFileName(e.ResultFilePath));
                e.ResultFilePath = downloadsPath;
                OnDownloadCaptured?.Invoke(Path.GetFileName(downloadsPath));
            };

            // 3. Activity & unread tracking script injection
            var activityScript = $$"""
                (() => {
                    function reportActivity() {
                        const title = document.title || '';
                        let unread = 0;
                        const match = title.match(/\((\d+)\)/);
                        if (match) {
                            unread = parseInt(match[1]);
                        }
                        const selector = '{{platform.UnreadBadgeSelector ?? ""}}';
                        if (selector && unread === 0) {
                            try {
                                const el = document.querySelector(selector);
                                if (el) {
                                    const num = parseInt(el.textContent.replace(/[^0-9]/g, ''));
                                    if (!isNaN(num)) unread = num;
                                }
                            } catch(e) {}
                        }
                        window.chrome.webview.postMessage({
                            type: 'activity',
                            accountId: '{{account.Id}}',
                            title: title,
                            unread: unread
                        });
                    }
                    setInterval(reportActivity, 3000);
                    reportActivity();
                })();
            """;

            webView.NavigationCompleted += async (s, e) =>
            {
                if (e.IsSuccess)
                {
                    if (!string.IsNullOrEmpty(platform.CustomCSS))
                    {
                        var cssScript = $"const style = document.createElement('style'); style.textContent = `{platform.CustomCSS}`; document.head.appendChild(style);";
                        await webView.ExecuteScriptAsync(cssScript);
                    }

                    if (!string.IsNullOrEmpty(platform.CustomJS))
                    {
                        await webView.ExecuteScriptAsync(platform.CustomJS);
                    }

                    await webView.ExecuteScriptAsync(activityScript);
                }
            };

            webView.WebMessageReceived += (s, e) =>
            {
                try
                {
                    var msg = e.TryGetWebMessageAsString();
                    if (!string.IsNullOrEmpty(msg) && msg.Contains("activity"))
                    {
                        using var doc = System.Text.Json.JsonDocument.Parse(msg);
                        if (doc.RootElement.TryGetProperty("unread", out var unreadProp) &&
                            doc.RootElement.TryGetProperty("title", out var titleProp))
                        {
                            OnActivityUpdated?.Invoke(account.Id, titleProp.GetString() ?? "", unreadProp.GetInt32());
                        }
                    }
                }
                catch { }
            };
        }
    }
}
