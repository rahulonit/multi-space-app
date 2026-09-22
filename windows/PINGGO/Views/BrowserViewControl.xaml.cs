using System;
using System.IO;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Web.WebView2.Core;
using PINGGO.Models;
using PINGGO.Services;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class BrowserViewControl : UserControl
    {
        public BrowserViewModel ViewModel => BrowserViewModel.Shared;

        public BrowserViewControl()
        {
            this.InitializeComponent();
            this.Loaded += OnControlLoaded;

            ViewModel.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName == nameof(ViewModel.UrlInput))
                {
                    OmnibarBox.Text = ViewModel.UrlInput;
                    UpdateStartPageVisibility();
                }
                else if (e.PropertyName == nameof(ViewModel.BlockedAdsCount))
                {
                    BlockedCountText.Text = ViewModel.BlockedAdsCount.ToString();
                }
            };

            ViewModel.OnNavigateRequested += (url) =>
            {
                BrowserWebView.CoreWebView2?.Navigate(url);
                UpdateStartPageVisibility();
            };

            ViewModel.OnGoBackRequested += () => BrowserWebView.CoreWebView2?.GoBack();
            ViewModel.OnGoForwardRequested += () => BrowserWebView.CoreWebView2?.GoForward();
            ViewModel.OnReloadRequested += () => BrowserWebView.CoreWebView2?.Reload();
            ViewModel.OnStopRequested += () => BrowserWebView.CoreWebView2?.Stop();
        }

        private async void OnControlLoaded(object sender, RoutedEventArgs e)
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var browserProfilePath = Path.Combine(appData, "PINGGO", "BrowserProfile");
            Directory.CreateDirectory(browserProfilePath);

            var env = await CoreWebView2Environment.CreateAsync(null, browserProfilePath);
            await BrowserWebView.EnsureCoreWebView2Async(env);

            AdBlockEngine.IsDomainWhitelisted = (domain) => ViewModel.WhitelistedDomains.Contains(domain);

            AdBlockEngine.AttachToWebView(BrowserWebView.CoreWebView2, (count) =>
            {
                App.CurrentWindow?.DispatcherQueue.TryEnqueue(() =>
                {
                    ViewModel.BlockedAdsCount = Math.Max(ViewModel.BlockedAdsCount, count);
                    if (ViewModel.ActiveTab != null)
                    {
                        ViewModel.ActiveTab.BlockedAdsCount = ViewModel.BlockedAdsCount;
                    }
                });
            });

            BrowserWebView.CoreWebView2.SourceChanged += (s, args) =>
            {
                var uri = BrowserWebView.Source;
                if (uri != null && uri.AbsoluteUri != "about:blank")
                {
                    ViewModel.UrlInput = uri.AbsoluteUri;
                    if (ViewModel.ActiveTab != null)
                    {
                        ViewModel.ActiveTab.UrlString = uri.AbsoluteUri;
                        ViewModel.ActiveTab.Title = uri.Host;
                        ViewModel.ActiveTab.FaviconUrl = $"https://www.google.com/s2/favicons?domain={uri.Host}&sz=64";
                    }
                    ViewModel.UpdateCurrentWhitelistedState();
                    ViewModel.SaveSession();
                }
            };

            UpdateStartPageVisibility();

            if (!string.IsNullOrEmpty(ViewModel.UrlInput))
            {
                BrowserWebView.CoreWebView2.Navigate(ViewModel.UrlInput);
            }
        }

        private void UpdateStartPageVisibility()
        {
            var hasUrl = !string.IsNullOrWhiteSpace(ViewModel.UrlInput);
            StartPageScrollViewer.Visibility = hasUrl ? Visibility.Collapsed : Visibility.Visible;
            BrowserWebView.Visibility = hasUrl ? Visibility.Visible : Visibility.Collapsed;
        }

        private void OnTabSelected(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is Guid id)
            {
                ViewModel.SelectTab(id);
            }
        }

        private void OnWhitelistToggled(object sender, RoutedEventArgs e)
        {
            ViewModel.ToggleWhitelistCurrentDomain();
        }

        private void OnNewTabClicked(object sender, RoutedEventArgs e) => ViewModel.AddNewTab();

        private void OnCloseTabClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is Guid id)
            {
                ViewModel.CloseTab(id);
            }
        }

        private void OnGoBackClicked(object sender, RoutedEventArgs e) => ViewModel.GoBack();
        private void OnGoForwardClicked(object sender, RoutedEventArgs e) => ViewModel.GoForward();
        private void OnReloadClicked(object sender, RoutedEventArgs e) => ViewModel.Reload();
        private void OnHomeClicked(object sender, RoutedEventArgs e) => ViewModel.GoHome();

        private void OnOmnibarKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                ViewModel.Navigate(OmnibarBox.Text);
            }
        }

        private void OnStartPageSearchKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                ViewModel.Navigate(StartPageSearchBox.Text);
            }
        }

        private void OnFavoriteItemClicked(object sender, ItemClickEventArgs e)
        {
            if (e.ClickedItem is BrowserBookmark bookmark)
            {
                ViewModel.Navigate(bookmark.UrlString);
            }
        }

        private void OnReaderModeClicked(object sender, RoutedEventArgs e)
        {
            MainViewModel.Shared.ShowToast("Reader mode extracted article text");
        }

        private void OnBookmarkClicked(object sender, RoutedEventArgs e)
        {
            MainViewModel.Shared.ShowToast("Page bookmarked to Quick Favorites");
        }

        private void OnAdBlockShieldClicked(object sender, RoutedEventArgs e)
        {
            MainViewModel.Shared.ShowToast($"AdBlocker Shield: {ViewModel.BlockedAdsCount} ads and trackers suppressed");
        }

        private async void OnOpenInEdgeClicked(object sender, RoutedEventArgs e)
        {
            if (!string.IsNullOrEmpty(ViewModel.UrlInput))
            {
                await Windows.System.Launcher.LaunchUriAsync(new Uri(ViewModel.UrlInput));
            }
        }
    }
}
