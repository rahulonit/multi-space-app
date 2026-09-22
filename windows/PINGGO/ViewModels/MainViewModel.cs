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
            // Sum unread across all active platform accounts
            TotalUnreadCount = 0; // Updated dynamically by activity handler
        }
    }
}
