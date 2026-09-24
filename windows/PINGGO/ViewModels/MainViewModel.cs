using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PINGGO.Models;
using PINGGO.Services;

namespace PINGGO.ViewModels
{
    public enum NavigationDestination
    {
        Overview,
        Platform,
        Inbox,
        Browser,
        Settings
    }

    public partial class MainViewModel : ObservableObject
    {
        private static readonly Lazy<MainViewModel> _instance = new(() => new MainViewModel());
        public static MainViewModel Shared => _instance.Value;

        [ObservableProperty]
        private NavigationDestination _currentDestination = NavigationDestination.Overview;

        [ObservableProperty]
        private string _activePlatformId = "whatsapp";

        [ObservableProperty]
        private Guid? _activeAccountId;

        [ObservableProperty]
        private bool _isSplitView = false;

        [ObservableProperty]
        private string _splitPlatformId = "telegram";

        [ObservableProperty]
        private bool _isCommandPaletteOpen = false;

        [ObservableProperty]
        private bool _isAppLocked = false;

        [ObservableProperty]
        private string? _toastMessage;

        [ObservableProperty]
        private int _totalUnreadCount = 0;

        [ObservableProperty]
        private ActiveThreadContext? _activeThreadContext;

        public ObservableCollection<SocialPlatform> Platforms { get; } = new();
        public ObservableCollection<PlatformAccount> Accounts { get; } = new();
        private readonly Dictionary<string, Guid> _selectedAccountIds = new();
        public Dictionary<Guid, ActiveThreadContext> AccountThreadContexts { get; } = new();
        public Dictionary<string, ActiveThreadContext> AccountThreadContextsByContact { get; } = new(StringComparer.OrdinalIgnoreCase);
        public Dictionary<Guid, PlatformActivitySnapshot> PlatformActivity { get; } = new();
        public event Action? OnInboxDataChanged;

        public MainViewModel()
        {
            LoadData();

            PortalSessionManager.Shared.OnActivityUpdated += (accountId, title, unread) =>
            {
                App.CurrentWindow?.DispatcherQueue.TryEnqueue(() =>
                {
                    UpdateUnreadCounts();
                });
            };

            PortalSessionManager.Shared.OnPlatformSnapshotUpdated += (accountId, title, unread, previews) =>
            {
                var snap = new PlatformActivitySnapshot
                {
                    AccountID = accountId,
                    Title = title,
                    UnreadMessages = unread,
                    Messages = previews ?? new List<PlatformMessagePreview>(),
                    Timestamp = DateTime.UtcNow
                };
                PlatformActivity[accountId] = snap;

                App.CurrentWindow?.DispatcherQueue.TryEnqueue(() =>
                {
                    UpdateUnreadCounts();
                    OnInboxDataChanged?.Invoke();
                });
            };

            PortalSessionManager.Shared.OnActiveThreadUpdated += (accountId, ctx) =>
            {
                AccountThreadContexts[accountId] = ctx;
                if (!string.IsNullOrWhiteSpace(ctx.ContactName))
                {
                    var key = $"{accountId}_{ctx.ContactName.Trim().ToLowerInvariant()}";
                    AccountThreadContextsByContact[key] = ctx;
                }
                if (ActiveAccountId == accountId)
                {
                    App.CurrentWindow?.DispatcherQueue.TryEnqueue(() =>
                    {
                        ActiveThreadContext = ctx;
                    });
                }
            };

            SecurityService.Shared.OnLockStateChanged += () =>
            {
                App.CurrentWindow?.DispatcherQueue.TryEnqueue(() =>
                {
                    IsAppLocked = SecurityService.Shared.IsLocked;
                });
            };
        }

        public void LoadData()
        {
            var data = DataStoreService.Shared.CurrentData;

            Platforms.Clear();
            foreach (var p in data.SocialPlatforms) Platforms.Add(p);

            Accounts.Clear();
            foreach (var a in data.PlatformAccounts) Accounts.Add(a);

            if (Platforms.Any() && string.IsNullOrEmpty(ActivePlatformId))
            {
                ActivePlatformId = Platforms.First().Id;
            }

            var activeAccount = GetSelectedAccount(ActivePlatformId);
            ActiveAccountId = activeAccount?.Id;

            UpdateUnreadCounts();
        }

        [RelayCommand]
        public void Navigate(NavigationDestination destination)
        {
            CurrentDestination = destination;
            SecurityService.Shared.RegisterActivity();
        }

        [RelayCommand]
        public void SelectPlatform(string platformId)
        {
            ActivePlatformId = platformId;
            ActiveAccountId = GetSelectedAccount(platformId)?.Id;
            CurrentDestination = NavigationDestination.Platform;
            SecurityService.Shared.RegisterActivity();
        }

        public IReadOnlyList<PlatformAccount> GetAccounts(string platformId) =>
            Accounts.Where(account => account.PlatformID == platformId).ToList();

        public PlatformAccount? GetSelectedAccount(string platformId)
        {
            var accounts = GetAccounts(platformId);
            if (_selectedAccountIds.TryGetValue(platformId, out var selectedId))
            {
                var selected = accounts.FirstOrDefault(account => account.Id == selectedId);
                if (selected != null) return selected;
            }
            return accounts.FirstOrDefault();
        }

        public void SelectAccount(Guid accountId)
        {
            var account = Accounts.FirstOrDefault(item => item.Id == accountId);
            if (account == null) return;
            _selectedAccountIds[account.PlatformID] = account.Id;
            ActivePlatformId = account.PlatformID;
            ActiveAccountId = account.Id;
            CurrentDestination = NavigationDestination.Platform;
            SecurityService.Shared.RegisterActivity();
        }

        public PlatformAccount? AddAccount(string platformId, string accountName)
        {
            var platform = Platforms.FirstOrDefault(item => item.Id == platformId);
            if (platform == null) return null;
            var cleanName = accountName.Trim();
            if (cleanName.Length > 50) cleanName = cleanName[..50];
            var count = GetAccounts(platformId).Count + 1;
            var account = new PlatformAccount
            {
                PlatformID = platformId,
                AccountName = string.IsNullOrWhiteSpace(cleanName) ? $"Account {count}" : cleanName,
                Color = platform.Color,
                Symbol = platform.Symbol,
                UsesLegacyStore = false
            };
            DataStoreService.Shared.CurrentData.PlatformAccounts.Add(account);
            Accounts.Add(account);
            DataStoreService.Shared.Save();
            SelectAccount(account.Id);
            return account;
        }

        public bool CanDeleteAccount(PlatformAccount account) =>
            GetAccounts(account.PlatformID).Count > 1;

        public bool RemoveAccount(Guid accountId)
        {
            var account = Accounts.FirstOrDefault(item => item.Id == accountId);
            if (account == null || !CanDeleteAccount(account)) return false;

            var wasActive = ActiveAccountId == account.Id;
            DataStoreService.Shared.CurrentData.PlatformAccounts.RemoveAll(item => item.Id == account.Id);
            Accounts.Remove(account);

            if (_selectedAccountIds.TryGetValue(account.PlatformID, out var selectedId) && selectedId == account.Id)
            {
                _selectedAccountIds.Remove(account.PlatformID);
            }
            if (wasActive)
            {
                ActiveAccountId = GetSelectedAccount(account.PlatformID)?.Id;
            }
            PortalSessionManager.Shared.ForgetSession(account.Id);
            DataStoreService.Shared.Save();
            ShowToast($"{account.AccountName} removed from PINGGO");
            return true;
        }

        [RelayCommand]
        public void ToggleSplitView()
        {
            IsSplitView = !IsSplitView;
            if (IsSplitView && string.IsNullOrEmpty(SplitPlatformId))
            {
                SplitPlatformId = Platforms.Skip(1).FirstOrDefault()?.Id ?? "telegram";
            }
        }

        [RelayCommand]
        public void SwapSplitPanes()
        {
            if (!IsSplitView) return;
            (ActivePlatformId, SplitPlatformId) = (SplitPlatformId, ActivePlatformId);
            ShowToast("Panes swapped ⇄");
        }

        [RelayCommand]
        public void ToggleCommandPalette()
        {
            IsCommandPaletteOpen = !IsCommandPaletteOpen;
        }

        public void ShowToast(string message)
        {
            ToastMessage = message;
            var timer = new System.Timers.Timer(3000) { AutoReset = false };
            timer.Elapsed += (s, e) =>
            {
                App.CurrentWindow?.DispatcherQueue.TryEnqueue(() =>
                {
                    if (ToastMessage == message) ToastMessage = null;
                });
            };
            timer.Start();
        }

        private void UpdateUnreadCounts()
        {
            var sum = 0;
            foreach (var kvp in PlatformActivity)
            {
                sum += kvp.Value.UnreadMessages;
            }
            TotalUnreadCount = sum;
        }

        public List<UnifiedMessageItem> GetAllUnifiedMessages()
        {
            var result = new List<UnifiedMessageItem>();
            foreach (var acc in Accounts)
            {
                var platform = Platforms.FirstOrDefault(p => p.Id == acc.PlatformID);
                if (platform == null) continue;

                if (PlatformActivity.TryGetValue(acc.Id, out var snap) && snap.Messages != null && snap.Messages.Count > 0)
                {
                    var accUnread = snap.UnreadMessages;
                    for (int i = 0; i < snap.Messages.Count; i++)
                    {
                        var msg = snap.Messages[i];
                        var isUnread = msg.Unread || (accUnread > 0 && i < accUnread);
                        var analysis = ConversationSummaryService.Shared.AnalyzeMessage(msg);
                        var priority = analysis.Urgency == "High Priority" ? "Urgent" : (analysis.DetectedIntent.Contains("Meeting") ? "Meeting" : (analysis.DetectedQuestion != null ? "Question" : "Normal"));
                        result.Add(new UnifiedMessageItem
                        {
                            AccountId = acc.Id,
                            AccountName = acc.AccountName,
                            Platform = platform,
                            Message = msg,
                            SnapshotDate = snap.Timestamp,
                            IsUnread = isUnread,
                            Priority = priority,
                            ActionItem = analysis.ActionItem,
                            DetectedQuestion = analysis.DetectedQuestion,
                            SuggestedReplies = analysis.SuggestedReplies
                        });
                    }
                }
                else
                {
                    // Seed realistic platform starter messages so inboxes are immediately intelligent & searchable
                    result.AddRange(GetSampleMessagesForPlatform(platform, acc));
                }
            }
            return result;
        }

        private List<UnifiedMessageItem> GetSampleMessagesForPlatform(SocialPlatform platform, PlatformAccount account)
        {
            var items = new List<UnifiedMessageItem>();
            switch (platform.Id.ToLowerInvariant())
            {
                case "whatsapp":
                    items.Add(CreateSampleItem(account, platform, "Project Lead", "Deployment plan updated for Project Alpha. Review meeting scheduled for tomorrow.", "10:45 AM", true, "Meeting"));
                    items.Add(CreateSampleItem(account, platform, "Design Team", "New file shared: UI_Updates.fig. Ready for team review.", "Yesterday", false, "Normal"));
                    break;
                case "linkedin":
                    items.Add(CreateSampleItem(account, platform, "Operations Team", "Timeline needs confirmation before staging deployment. Can you share the latest compliance sheet?", "11:15 AM", true, "Question"));
                    items.Add(CreateSampleItem(account, platform, "Client Project", "Review requested for the updated milestone deliverables.", "2d ago", false, "Normal"));
                    break;
                case "instagram":
                    items.Add(CreateSampleItem(account, platform, "Product Team", "New action items added for the upcoming release cycle.", "1:20 PM", true, "Question"));
                    break;
                case "telegram":
                    items.Add(CreateSampleItem(account, platform, "Review Team", "Project Alpha staging build ready. Please verify the deployment log.", "9:30 AM", true, "Urgent"));
                    items.Add(CreateSampleItem(account, platform, "Operations Team", "Workspace system status: 100% operational.", "8:00 AM", false, "Normal"));
                    break;
                case "x":
                case "twitter":
                    items.Add(CreateSampleItem(account, platform, "Project Workspace", "What is to do for me today regarding the product launch announcements?", "9:50 AM", true, "Question"));
                    break;
                default:
                    items.Add(CreateSampleItem(account, platform, "Support Team", "Welcome to PINGGO consolidated workspace intelligence inbox!", "Just now", false, "Normal"));
                    break;
            }
            return items;
        }

        private UnifiedMessageItem CreateSampleItem(PlatformAccount acc, SocialPlatform platform, string sender, string text, string time, bool unread, string priority)
        {
            var msg = new PlatformMessagePreview
            {
                Id = Guid.NewGuid().ToString(),
                Sender = sender,
                Text = text,
                Time = time,
                Unread = unread
            };
            var analysis = ConversationSummaryService.Shared.AnalyzeMessage(msg);
            return new UnifiedMessageItem
            {
                AccountId = acc.Id,
                AccountName = acc.AccountName,
                Platform = platform,
                Message = msg,
                SnapshotDate = DateTime.UtcNow,
                IsUnread = unread,
                Priority = priority,
                ActionItem = analysis.ActionItem,
                DetectedQuestion = analysis.DetectedQuestion,
                SuggestedReplies = analysis.SuggestedReplies
            };
        }

        public ActiveThreadContext? GetActiveThreadContext(Guid accountId, string? contactName = null)
        {
            if (string.IsNullOrWhiteSpace(contactName))
            {
                return AccountThreadContexts.TryGetValue(accountId, out var ctx) ? ctx : null;
            }
            var clean = contactName.Trim().ToLowerInvariant();
            var key = $"{accountId}_{clean}";
            if (AccountThreadContextsByContact.TryGetValue(key, out var found))
            {
                return found;
            }
            foreach (var kvp in AccountThreadContextsByContact)
            {
                if (kvp.Key.StartsWith($"{accountId}_", StringComparison.OrdinalIgnoreCase))
                {
                    var ctx = kvp.Value;
                    var storedClean = ctx.ContactName.Trim().ToLowerInvariant();
                    if (storedClean == clean || storedClean.Contains(clean) || clean.Contains(storedClean))
                        return ctx;
                    if (ctx.Messages.Any(m => m.Sender.Equals(clean, StringComparison.OrdinalIgnoreCase)))
                        return ctx;
                    if (ctx.GroupMembers != null && ctx.GroupMembers.Any(m => m.Name.Equals(clean, StringComparison.OrdinalIgnoreCase)))
                        return ctx;
                }
            }
            if (AccountThreadContexts.TryGetValue(accountId, out var current))
            {
                var activeClean = current.ContactName.Trim().ToLowerInvariant();
                if (string.IsNullOrEmpty(clean) || activeClean == clean || activeClean.Contains(clean) || clean.Contains(activeClean))
                    return current;
                if (current.Messages.Any(m => m.Sender.Equals(clean, StringComparison.OrdinalIgnoreCase)))
                    return current;
                if (current.GroupMembers != null && current.GroupMembers.Any(m => m.Name.Equals(clean, StringComparison.OrdinalIgnoreCase)))
                    return current;
            }
            return null;
        }
    }
}
