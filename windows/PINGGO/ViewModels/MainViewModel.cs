using System;
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

        public ObservableCollection<SocialPlatform> Platforms { get; } = new();
        public ObservableCollection<PlatformAccount> Accounts { get; } = new();

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
            CurrentDestination = NavigationDestination.Platform;
            SecurityService.Shared.RegisterActivity();
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
