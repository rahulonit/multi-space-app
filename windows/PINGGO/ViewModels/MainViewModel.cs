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
                    items.Add(CreateSampleItem(account, platform, "Vikram Mehta", "Are you available for a quick sync today at 3 PM to review the deliverables?", "10:45 AM", true, "Meeting"));
                    items.Add(CreateSampleItem(account, platform, "Anita Roy", "Thanks for sharing the updated schedule. Looks solid!", "Yesterday", false, "Normal"));
                    break;
                case "linkedin":
                    items.Add(CreateSampleItem(account, platform, "Rahul Sharma", "We are reviewing the CPWD guidelines across Maharashtra, Delhi and Gujarat state projects. Can you share the latest compliance sheet?", "11:15 AM", true, "Question"));
                    items.Add(CreateSampleItem(account, platform, "Pooja Verma", "Loved your recent post on enterprise multi-space architecture!", "2d ago", false, "Normal"));
                    break;
                case "instagram":
                    items.Add(CreateSampleItem(account, platform, "Sneha Kapoor", "Love the new UI design! Could you share the deck with the marketing team?", "1:20 PM", true, "Question"));
                    break;
                case "telegram":
                    items.Add(CreateSampleItem(account, platform, "Alex Chen", "Urgent: The staging server build failed. Please check the deployment log ASAP.", "9:30 AM", true, "Urgent"));
                    items.Add(CreateSampleItem(account, platform, "DevOps Bot", "Production cluster health: 100% operational.", "8:00 AM", false, "Normal"));
                    break;
                case "x":
                case "twitter":
                    items.Add(CreateSampleItem(account, platform, "Tech Insider", "What is to do for me today regarding the product launch announcements?", "9:50 AM", true, "Question"));
                    break;
                default:
                    items.Add(CreateSampleItem(account, platform, "Support Team", "Welcome to PINGGO consolidated multi-space inbox!", "Just now", false, "Normal"));
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
    }
}
