using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PINGGO.Models;

namespace PINGGO.ViewModels
{
    public partial class BrowserViewModel : ObservableObject
    {
        private static readonly Lazy<BrowserViewModel> _instance = new(() => new BrowserViewModel());
        public static BrowserViewModel Shared => _instance.Value;

        private readonly string _sessionFilePath;

        public ObservableCollection<BrowserTabItem> Tabs { get; } = new();

        [ObservableProperty]
        private Guid _activeTabId;

        [ObservableProperty]
        private BrowserTabItem? _activeTab;

        [ObservableProperty]
        private string _urlInput = string.Empty;

        [ObservableProperty]
        private bool _isLoading = false;

        [ObservableProperty]
        private double _estimatedProgress = 0.0;

        [ObservableProperty]
        private bool _canGoBack = false;

        [ObservableProperty]
        private bool _canGoForward = false;

        [ObservableProperty]
        private int _blockedAdsCount = 0;

        [ObservableProperty]
        private bool _isAdBlockerActive = true;

        [ObservableProperty]
        private bool _isReaderModeActive = false;

        [ObservableProperty]
        private string? _readerContent;

        [ObservableProperty]
        private string _searchEngine = "DuckDuckGo"; // DuckDuckGo, Google, Bing

        public event Action<string>? OnNavigateRequested;
        public event Action? OnGoBackRequested;
        public event Action? OnGoForwardRequested;
        public event Action? OnReloadRequested;
        public event Action? OnStopRequested;

        public BrowserViewModel()
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            _sessionFilePath = Path.Combine(appData, "PINGGO", "browser_session.json");

            RestoreSessionOrInitDefault();
        }

        private void RestoreSessionOrInitDefault()
        {
            try
            {
                if (File.Exists(_sessionFilePath))
                {
                    var json = File.ReadAllText(_sessionFilePath);
                    var session = JsonSerializer.Deserialize<SavedBrowserSession>(json);
                    if (session != null && session.Tabs.Any())
                    {
                        foreach (var saved in session.Tabs)
                        {
                            Tabs.Add(new BrowserTabItem
                            {
                                Id = saved.Id,
                                Title = saved.Title,
                                UrlString = saved.UrlString,
                                PageTitle = saved.PageTitle,
                                BlockedAdsCount = saved.BlockedAdsCount,
                                IsReaderModeActive = saved.IsReaderModeActive
                            });
                        }

                        var target = Tabs.FirstOrDefault(t => t.Id == session.ActiveTabID) ?? Tabs.First();
                        SelectTab(target.Id);
                        return;
                    }
                }
            }
            catch { }

            // Default initial tab
            var initialTab = new BrowserTabItem
            {
                Id = Guid.NewGuid(),
                Title = "New Tab",
                UrlString = string.Empty
            };
            Tabs.Add(initialTab);
            SelectTab(initialTab.Id);
        }

        public void SaveSession()
        {
            try
            {
                var session = new SavedBrowserSession
                {
                    ActiveTabID = ActiveTabId,
                    Tabs = Tabs.Select(t => new SavedBrowserTab
                    {
                        Id = t.Id,
                        Title = t.Title,
                        UrlString = t.UrlString,
                        PageTitle = t.PageTitle,
                        BlockedAdsCount = t.BlockedAdsCount,
                        IsReaderModeActive = t.IsReaderModeActive
                    }).ToList()
                };

                var json = JsonSerializer.Serialize(session, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(_sessionFilePath, json);
            }
            catch { }
        }

        [RelayCommand]
        public void AddNewTab(string url = "")
        {
            var newTab = new BrowserTabItem
            {
                Id = Guid.NewGuid(),
                Title = string.IsNullOrEmpty(url) ? "New Tab" : url,
                UrlString = url
            };
            Tabs.Add(newTab);
            SelectTab(newTab.Id);
            SaveSession();

            if (!string.IsNullOrEmpty(url))
            {
                Navigate(url);
            }
        }

        [RelayCommand]
        public void SelectTab(Guid tabId)
        {
            var target = Tabs.FirstOrDefault(t => t.Id == tabId);
            if (target == null) return;

            ActiveTabId = tabId;
            ActiveTab = target;
            UrlInput = target.UrlString;
            BlockedAdsCount = target.BlockedAdsCount;
            CanGoBack = target.CanGoBack;
            CanGoForward = target.CanGoForward;
            IsLoading = target.IsLoading;
            IsReaderModeActive = target.IsReaderModeActive;
            ReaderContent = target.ReaderContent;

            SaveSession();
        }

        [RelayCommand]
        public void CloseTab(Guid tabId)
        {
            var tab = Tabs.FirstOrDefault(t => t.Id == tabId);
            if (tab == null) return;

            var idx = Tabs.IndexOf(tab);
            Tabs.Remove(tab);

            if (!Tabs.Any())
            {
                AddNewTab();
            }
            else if (ActiveTabId == tabId)
            {
                var nextIndex = Math.Min(idx, Tabs.Count - 1);
                SelectTab(Tabs[nextIndex].Id);
            }
            SaveSession();
        }

        [RelayCommand]
        public void Navigate(string? input = null)
        {
            var query = (input ?? UrlInput).Trim();
            if (string.IsNullOrWhiteSpace(query)) return;

            string targetUrl;
            if (query.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                query.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                targetUrl = query;
            }
            else if (query.Contains('.') && !query.Contains(' '))
            {
                targetUrl = $"https://{query}";
            }
            else
            {
                var encoded = Uri.EscapeDataString(query);
                targetUrl = SearchEngine switch
                {
                    "Google" => $"https://www.google.com/search?q={encoded}",
                    "Bing" => $"https://www.bing.com/search?q={encoded}",
                    _ => $"https://duckduckgo.com/?q={encoded}"
                };
            }

            UrlInput = targetUrl;
            if (ActiveTab != null)
            {
                ActiveTab.UrlString = targetUrl;
            }

            OnNavigateRequested?.Invoke(targetUrl);
            SaveSession();
        }

        [RelayCommand]
        public void GoBack() => OnGoBackRequested?.Invoke();

        [RelayCommand]
        public void GoForward() => OnGoForwardRequested?.Invoke();

        [RelayCommand]
        public void Reload() => OnReloadRequested?.Invoke();

        [RelayCommand]
        public void Stop() => OnStopRequested?.Invoke();

        [RelayCommand]
        public void GoHome()
        {
            UrlInput = string.Empty;
            if (ActiveTab != null)
            {
                ActiveTab.UrlString = string.Empty;
                ActiveTab.Title = "New Tab";
            }
            SaveSession();
        }
    }
}
