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
        public event Action<Guid, ActiveThreadContext>? OnActiveThreadUpdated;
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

        public void ConfigureSessionWebView(CoreWebView2 webView, PlatformAccount account, SocialPlatform platform,
                                            Action<string>? downloadCompleted = null)
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
                var userDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                var downloadsDirectory = Path.Combine(userDirectory, "Downloads");
                Directory.CreateDirectory(downloadsDirectory);
                var suggestedName = Path.GetFileName(e.ResultFilePath);
                if (string.IsNullOrWhiteSpace(suggestedName)) suggestedName = "download";
                var downloadsPath = UniqueDownloadPath(downloadsDirectory, suggestedName);
                e.ResultFilePath = downloadsPath;
                OnDownloadCaptured?.Invoke(Path.GetFileName(downloadsPath));
                e.DownloadOperation.StateChanged += (_, _) =>
                {
                    if (e.DownloadOperation.State == CoreWebView2DownloadState.Completed)
                    {
                        downloadCompleted?.Invoke(downloadsPath);
                    }
                };
            };

            // 3. Activity, unread, active thread scraper, and 1-click text injector
            var activityScript = $$"""
                (() => {
                    const clean = val => (val || '').replace(/\s+/g, ' ').trim();

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

                        // Scrape active contact
                        const host = location.hostname.toLowerCase();
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

                        // Scrape active thread messages
                        const activeMessages = [];
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
                            const bubbles = Array.from(document.querySelectorAll(bubbleSelectors)).slice(-10);
                            bubbles.forEach(bubble => {
                                let sender = '';
                                let text = '';
                                let isFromMe = false;

                                if (host.endsWith('whatsapp.com')) {
                                    isFromMe = bubble.classList.contains('message-out');
                                    const textNode = bubble.querySelector('span.selectable-text, ._ao3e, span[dir="ltr"]');
                                    if (textNode) text = clean(textNode.innerText);
                                    sender = isFromMe ? 'You' : (activeContact || 'Contact');
                                } else if (host.endsWith('telegram.org')) {
                                    isFromMe = bubble.classList.contains('is-out') || bubble.classList.contains('own');
                                    const textNode = bubble.querySelector('.text-content, .message-content, .translatable-message');
                                    if (textNode) text = clean(textNode.innerText);
                                    sender = isFromMe ? 'You' : (activeContact || 'Contact');
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

                                if (text && text.length > 0) {
                                    activeMessages.push({ sender, text: text.slice(0, 300), isFromMe });
                                }
                            });
                        }

                        window.chrome.webview.postMessage({
                            type: 'activity',
                            accountId: '{{account.Id}}',
                            title: title,
                            unread: unread,
                            activeContact: activeContact,
                            messages: activeMessages
                        });
                    }
                    setInterval(reportActivity, 2500);
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

                        var activeContact = doc.RootElement.TryGetProperty("activeContact", out var cProp) ? cProp.GetString() ?? "" : "";
                        var msgs = new List<ActiveChatMessage>();
                        if (doc.RootElement.TryGetProperty("messages", out var msgsProp) && msgsProp.ValueKind == System.Text.Json.JsonValueKind.Array)
                        {
                            foreach (var item in msgsProp.EnumerateArray())
                            {
                                msgs.Add(new ActiveChatMessage
                                {
                                    Sender = item.TryGetProperty("sender", out var s) ? s.GetString() ?? "" : "",
                                    Text = item.TryGetProperty("text", out var t) ? t.GetString() ?? "" : "",
                                    IsFromMe = item.TryGetProperty("isFromMe", out var m) && m.GetBoolean()
                                });
                            }
                        }

                        if (!string.IsNullOrEmpty(activeContact) || msgs.Count > 0)
                        {
                            var ctx = new ActiveThreadContext
                            {
                                ContactName = string.IsNullOrEmpty(activeContact) ? (msgs.Find(m => !m.IsFromMe)?.Sender ?? "Current Chat") : activeContact,
                                PlatformId = platform.Id,
                                Messages = msgs,
                                UpdatedAt = DateTime.UtcNow
                            };
                            OnActiveThreadUpdated?.Invoke(account.Id, ctx);
                        }
                    }
                }
                catch { }
            };
        }

        public async Task<bool> InsertTextIntoChatAsync(CoreWebView2 webView, string text)
        {
            var escaped = System.Text.Json.JsonSerializer.Serialize(text);
            var script = $"window.pinggoInsertText ? window.pinggoInsertText({escaped}) : false;";
            var res = await webView.ExecuteScriptAsync(script);
            return bool.TryParse(res, out var ok) && ok;
        }

        public void ForgetSession(Guid accountId)
        {
            _environments.TryRemove(accountId, out _);
            _ = Task.Run(async () =>
            {
                for (var attempt = 0; attempt < 4; attempt++)
                {
                    if (DataStoreService.Shared.DeleteProfileDirectory(accountId)) return;
                    await Task.Delay(500 * (attempt + 1));
                }
            });
        }

        private static string UniqueDownloadPath(string directory, string suggestedName)
        {
            var candidate = Path.Combine(directory, suggestedName);
            var baseName = Path.GetFileNameWithoutExtension(suggestedName);
            var extension = Path.GetExtension(suggestedName);
            var counter = 1;
            while (File.Exists(candidate))
            {
                candidate = Path.Combine(directory, $"{baseName} ({counter}){extension}");
                counter++;
            }
            return candidate;
        }
    }
}
