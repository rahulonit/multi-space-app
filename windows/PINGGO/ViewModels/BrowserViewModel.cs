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
        private readonly string _whitelistFilePath;

        public HashSet<string> WhitelistedDomains { get; } = new(StringComparer.OrdinalIgnoreCase);

        [ObservableProperty]
        private bool _isCurrentDomainWhitelisted = false;

        public string? CurrentHost
        {
            get
            {
                if (Uri.TryCreate(UrlInput, UriKind.Absolute, out var uri))
                {
                    return uri.Host.ToLowerInvariant();
                }
                return null;
            }
        }

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
            _whitelistFilePath = Path.Combine(appData, "PINGGO", "whitelisted_domains.json");

            RestoreWhitelist();
            RestoreSessionOrInitDefault();
        }

        private void RestoreWhitelist()
        {
            try
            {
                if (File.Exists(_whitelistFilePath))
                {
                    var json = File.ReadAllText(_whitelistFilePath);
                    var list = JsonSerializer.Deserialize<List<string>>(json);
                    if (list != null)
                    {
                        foreach (var d in list) WhitelistedDomains.Add(d);
                    }
                }
            }
            catch { }
        }

        private void SaveWhitelist()
        {
            try
            {
                var json = JsonSerializer.Serialize(WhitelistedDomains.ToList(), new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(_whitelistFilePath, json);
            }
            catch { }
        }

        public void UpdateCurrentWhitelistedState()
        {
            var host = CurrentHost;
            IsCurrentDomainWhitelisted = !string.IsNullOrEmpty(host) && WhitelistedDomains.Contains(host);
        }

        [RelayCommand]
        public void ToggleWhitelistCurrentDomain()
        {
            var host = CurrentHost;
            if (string.IsNullOrEmpty(host)) return;

            if (WhitelistedDomains.Contains(host))
            {
                WhitelistedDomains.Remove(host);
            }
            else
            {
                WhitelistedDomains.Add(host);
            }

            SaveWhitelist();
            UpdateCurrentWhitelistedState();
            Reload();
        }

        public void ReorderTab(Guid sourceId, Guid targetId)
        {
            if (sourceId == targetId) return;
            var source = Tabs.FirstOrDefault(t => t.Id == sourceId);
            var target = Tabs.FirstOrDefault(t => t.Id == targetId);
            if (source == null || target == null) return;

            var oldIndex = Tabs.IndexOf(source);
            var newIndex = Tabs.IndexOf(target);
            Tabs.Move(oldIndex, newIndex);
            SaveSession();
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
                                IsReaderModeActive = saved.IsReaderModeActive,
                                FaviconUrl = saved.FaviconUrl ?? (!string.IsNullOrEmpty(saved.UrlString) && Uri.TryCreate(saved.UrlString, UriKind.Absolute, out var u) ? $"https://www.google.com/s2/favicons?domain={u.Host}&sz=64" : null)
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
                        IsReaderModeActive = t.IsReaderModeActive,
                        FaviconUrl = t.FaviconUrl
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
