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
        public event Action<Guid, string, int, List<PlatformMessagePreview>>? OnPlatformSnapshotUpdated;
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

            // 2. Intercept attachment navigations (PDF -> browser, Media/Other files -> OS default app)
            webView.NavigationStarting += (s, e) =>
            {
                if (string.IsNullOrWhiteSpace(e.Uri)) return;
                if (e.Uri.StartsWith("blob:", StringComparison.OrdinalIgnoreCase) ||
                    e.Uri.StartsWith("data:", StringComparison.OrdinalIgnoreCase) ||
                    e.Uri.StartsWith("about:", StringComparison.OrdinalIgnoreCase)) return;

                if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri))
                {
                    var ext = Path.GetExtension(uri.AbsolutePath).TrimStart('.').ToLowerInvariant();
                    if (ext == "pdf")
                    {
                        e.Cancel = true;
                        try
                        {
                            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(e.Uri) { UseShellExecute = true });
                        }
                        catch { }
                        return;
                    }
                    if (IsMediaOrOtherFileExtension(ext))
                    {
                        e.Cancel = true;
                        try
                        {
                            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(e.Uri) { UseShellExecute = true });
                        }
                        catch { }
                        return;
                    }
                }
            };

            webView.NewWindowRequested += (s, e) =>
            {
                if (string.IsNullOrWhiteSpace(e.Uri)) return;
                e.Handled = true;
                try
                {
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(e.Uri) { UseShellExecute = true });
                }
                catch { }
            };

            // 3. Download capture
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
                            waBackendCache.groups.set(subject.toLowerCase(), groupData);
                        }
                        if (gid) {
                            waBackendCache.groups.set(gid.toLowerCase(), groupData);
                        }
                    }

                    let waSyncRunning = false;
                    function syncWhatsAppBackend() {
                        if (waSyncRunning) return;
                        if (!location.hostname.toLowerCase().endsWith('whatsapp.com')) return;
                        if (Date.now() - waBackendCache.lastSync < 8000 && waBackendCache.contactsByName.size > 0) return;
                        waSyncRunning = true;
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
                            if (window.indexedDB) {
                                const req = window.indexedDB.open('model-storage');
                                req.onsuccess = (e) => {
                                    const db = e.target.result;
                                    if (!db) return;
                                    const storeNames = Array.from(db.objectStoreNames || []);
                                    const cStoreName = storeNames.find(s => s === 'contact' || s.includes('contact'));
                                    const gStoreName = storeNames.find(s => s === 'group-metadata' || s.includes('group-metadata'));
                                    const needed = [cStoreName, gStoreName].filter(Boolean);
                                    if (needed.length === 0) { db.close(); return; }
                                    try {
                                        const tx = db.transaction(needed, 'readonly');
                                        if (cStoreName) {
                                            const cs = tx.objectStore(cStoreName);
                                            const csReq = cs.getAll();
                                            csReq.onsuccess = () => {
                                                for (const c of (csReq.result || [])) processRawContact(c);
                                            };
                                        }
                                        if (gStoreName) {
                                            const gs = tx.objectStore(gStoreName);
                                            const gsReq = gs.getAll();
                                            gsReq.onsuccess = () => {
                                                for (const g of (gsReq.result || [])) processRawGroup(g);
                                            };
                                        }
                                        tx.oncomplete = () => db.close();
                                        tx.onerror = () => db.close();
                                    } catch(err) { db.close(); }
                                };
                            }
                            waBackendCache.lastSync = Date.now();
                        } catch(e) {}
                        finally { waSyncRunning = false; }
                    }

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
                        const host = location.hostname.toLowerCase();
                        if (host.endsWith('whatsapp.com')) {
                            syncWhatsAppBackend();
                        }
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

                        if (host.endsWith('linkedin.com')) {
                            const minimizedDock = document.querySelector('.msg-overlay-list-bubble--is-minimized');
                            if (minimizedDock) {
                                const btn = minimizedDock.querySelector('.msg-overlay-bubble-header, button');
                                if (btn) btn.click();
                            }
                        }

                        // Scrape active contact
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

                        // Scrape active thread messages (deep crawl up to 150 messages)
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

                        // Deep group roster & participant crawling (strictly within the SELECTED chat)
                        let isGroup = false;
                        let groupMemberCount = 0;
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
                                if ((!existing.name || /^\+?[0-9\s\-()]{7,}$/.test(existing.name)) && finalName) existing.name = finalName;
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
                                activeContact = '';
                            } else {
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

                        if (isGroup && groupSubtitle && groupSubtitle.includes(',')) {
                            const parts = groupSubtitle.split(',').map(s => clean(s.replace(/and \d+ others?/i, ''))).filter(Boolean);
                            parts.forEach(p => addGroupMember(p, 'Member', 'In group roster', 0));
                        }

                        if (bubbleSelectors) {
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

                                if (text && text.length > 0) {
                                    activeMessages.push({ sender: sender || (isFromMe ? 'You' : 'Contact'), text: text.slice(0, 1000), isFromMe, time: time || undefined });
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

                        // Scrape inbox conversation previews across platforms
                        const inboxPreviews = [];
                        let previewSelector = '';
                        if (host.endsWith('whatsapp.com')) {
                            previewSelector = '#pane-side [role="row"], #pane-side [role="listitem"], [data-testid="cell-frame-container"]';
                        } else if (host.endsWith('instagram.com')) {
                            previewSelector = 'a[href*="/direct/t/"], div[role="listitem"] a[href*="/direct/"]';
                        } else if (host.endsWith('telegram.org')) {
                            previewSelector = '.chat-list .ListItem, .chat-list-item, .chatlist-chat, a.chatlist-chat';
                        } else if (host.endsWith('facebook.com') || host.endsWith('messenger.com')) {
                            previewSelector = 'a[href*="/messages/t/"], div[role="row"] a[role="link"]';
                        } else if (host.endsWith('linkedin.com')) {
                            previewSelector = 'li.msg-conversation-listitem, .msg-conversation-card, a[href*="/messaging/thread/"]';
                        } else if (host.endsWith('x.com') || host.endsWith('twitter.com')) {
                            previewSelector = '[data-testid="conversation"], a[href*="/messages/"]';
                        }

                        if (previewSelector) {
                            const pNodes = document.querySelectorAll(previewSelector);
                            pNodes.forEach((node, idx) => {
                                if (inboxPreviews.length >= 100) return;
                                let s = '';
                                let t = '';
                                let tm = '';
                                let u = false;

                                if (host.endsWith('whatsapp.com')) {
                                    const nameSpan = node.querySelector('span[title], div[class*="_ak8q"] span, span[data-testid="cell-frame-title"]');
                                    if (nameSpan) s = clean(nameSpan.getAttribute('title') || nameSpan.innerText);
                                    const textSpan = node.querySelector('[data-testid="last-msg-status"], span[class*="_ao3e"], div[class*="_ak8k"] span');
                                    if (textSpan) t = clean(textSpan.innerText);
                                    const timeSpan = node.querySelector('div._ak8i, span[data-testid="cell-frame-secondary-title"]');
                                    if (timeSpan) tm = clean(timeSpan.innerText);
                                    const badge = node.querySelector('span[aria-label*="unread" i], span._ak8j');
                                    if (badge) u = true;
                                } else if (host.endsWith('linkedin.com')) {
                                    const nameSpan = node.querySelector('.msg-conversation-listitem__participant-names, h3, .msg-conversation-card__participant-names');
                                    if (nameSpan) s = clean(nameSpan.innerText);
                                    const textSpan = node.querySelector('.msg-conversation-card__message-snippet, .msg-conversation-listitem__message-snippet, p');
                                    if (textSpan) t = clean(textSpan.innerText);
                                    const timeSpan = node.querySelector('time, .msg-conversation-listitem__time-stamp');
                                    if (timeSpan) tm = clean(timeSpan.innerText);
                                    const unreadIndicator = node.querySelector('.msg-conversation-card__unread-count, .notification-badge--unread');
                                    if (unreadIndicator) u = true;
                                } else if (host.endsWith('instagram.com')) {
                                    const spans = node.querySelectorAll('span[dir="auto"], span');
                                    if (spans.length > 0) s = clean(spans[0].innerText);
                                    if (spans.length > 1) t = clean(spans[1].innerText);
                                } else if (host.endsWith('telegram.org')) {
                                    const nameSpan = node.querySelector('.peer-title, .title');
                                    if (nameSpan) s = clean(nameSpan.innerText);
                                    const textSpan = node.querySelector('.last-message, .subtitle');
                                    if (textSpan) t = clean(textSpan.innerText);
                                    const timeSpan = node.querySelector('.message-time, .time');
                                    if (timeSpan) tm = clean(timeSpan.innerText);
                                    const unreadBadge = node.querySelector('.badge, .unread');
                                    if (unreadBadge) u = true;
                                } else {
                                    const spans = node.querySelectorAll('span, p, div');
                                    if (spans.length > 0) s = clean(spans[0].innerText);
                                    if (spans.length > 1) t = clean(spans[1].innerText);
                                }

                                if (s && (t || u)) {
                                    inboxPreviews.push({
                                        id: 'p-' + idx,
                                        sender: s,
                                        text: t || 'New message',
                                        time: tm || 'Recent',
                                        unread: u
                                    });
                                }
                            });
                        }

                        window.chrome.webview.postMessage({
                            type: 'activity',
                            accountId: '{{account.Id}}',
                            title: title,
                            unread: unread,
                            activeContact: activeContact,
                            messages: activeMessages,
                            inboxPreviews: inboxPreviews,
                            groupMemberCount: groupMemberCount,
                            groupSubtitle: groupSubtitle,
                            groupMembers: groupMembers
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
                        var unread = 0;
                        var title = "";
                        if (doc.RootElement.TryGetProperty("unread", out var unreadProp) &&
                            doc.RootElement.TryGetProperty("title", out var titleProp))
                        {
                            unread = unreadProp.GetInt32();
                            title = titleProp.GetString() ?? "";
                            OnActivityUpdated?.Invoke(account.Id, title, unread);
                        }

                        var previews = new List<PlatformMessagePreview>();
                        if (doc.RootElement.TryGetProperty("inboxPreviews", out var inboxesProp) && inboxesProp.ValueKind == System.Text.Json.JsonValueKind.Array)
                        {
                            foreach (var item in inboxesProp.EnumerateArray())
                            {
                                previews.Add(new PlatformMessagePreview
                                {
                                    Id = item.TryGetProperty("id", out var pid) ? pid.GetString() ?? Guid.NewGuid().ToString() : Guid.NewGuid().ToString(),
                                    Sender = item.TryGetProperty("sender", out var ps) ? ps.GetString() ?? "Contact" : "Contact",
                                    Text = item.TryGetProperty("text", out var pt) ? pt.GetString() ?? "" : "",
                                    Time = item.TryGetProperty("time", out var ptime) ? ptime.GetString() : null,
                                    Unread = item.TryGetProperty("unread", out var pu) && pu.GetBoolean()
                                });
                            }
                        }

                        OnPlatformSnapshotUpdated?.Invoke(account.Id, title, unread, previews);

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

                        int? groupMemberCount = null;
                        if (doc.RootElement.TryGetProperty("groupMemberCount", out var gmcProp) && gmcProp.TryGetInt32(out var gmcVal) && gmcVal > 0)
                        {
                            groupMemberCount = gmcVal;
                        }

                        var groupSubtitle = doc.RootElement.TryGetProperty("groupSubtitle", out var gsubProp) ? gsubProp.GetString() : null;

                        var groupMembersList = new List<AIChatMemberItem>();
                        if (doc.RootElement.TryGetProperty("groupMembers", out var gmProp) && gmProp.ValueKind == System.Text.Json.JsonValueKind.Array)
                        {
                            foreach (var item in gmProp.EnumerateArray())
                            {
                                var name = item.TryGetProperty("name", out var nProp) ? nProp.GetString() : null;
                                if (!string.IsNullOrEmpty(name))
                                {
                                    groupMembersList.Add(new AIChatMemberItem
                                    {
                                        Name = name,
                                        Role = item.TryGetProperty("role", out var rProp) ? rProp.GetString() ?? "Participant" : "Participant",
                                        Activity = item.TryGetProperty("activity", out var aProp) ? aProp.GetString() ?? "In group" : "In group",
                                        MessageCount = item.TryGetProperty("messageCount", out var mcProp) && mcProp.TryGetInt32(out var mcVal) ? mcVal : 1,
                                        PhoneNumber = item.TryGetProperty("phoneNumber", out var pProp) ? pProp.GetString() : null,
                                        Username = item.TryGetProperty("username", out var uProp) ? uProp.GetString() : null
                                    });
                                }
                            }
                        }

                        if (!string.IsNullOrEmpty(activeContact) || msgs.Count > 0)
                        {
                            var ctx = new ActiveThreadContext
                            {
                                ContactName = string.IsNullOrEmpty(activeContact) ? (msgs.Find(m => !m.IsFromMe)?.Sender ?? "Current Chat") : activeContact,
                                PlatformId = platform.Id,
                                Messages = msgs,
                                GroupMemberCount = groupMemberCount,
                                GroupSubtitle = groupSubtitle,
                                GroupMembers = groupMembersList.Count > 0 ? groupMembersList : null,
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

        private static readonly System.Collections.Generic.HashSet<string> _mediaAndFileExtensions = new(StringComparer.OrdinalIgnoreCase)
        {
            // Images
            "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico", "heic", "heif", "avif", "tiff", "tif",
            // Video
            "mp4", "mov", "webm", "mkv", "avi", "m4v", "mpg", "mpeg", "wmv", "flv", "3gp",
            // Audio
            "mp3", "wav", "ogg", "m4a", "aac", "flac", "wma", "aiff", "opus",
            // Documents
            "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf", "csv", "tsv", "txt",
            // Archives
            "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz",
            // Installers & executables
            "exe", "msi", "apk", "dmg", "pkg"
        };

        private static bool IsMediaOrOtherFileExtension(string ext) => _mediaAndFileExtensions.Contains(ext);
    }
}
