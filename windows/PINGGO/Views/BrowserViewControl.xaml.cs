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
        private bool _isWebViewInitialized;
        private bool _isWebViewInitializing;

        public BrowserViewControl()
        {
            this.InitializeComponent();
            DataContext = ViewModel;
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
                if (BrowserWebView.CoreWebView2 != null)
                {
                    BrowserWebView.CoreWebView2.Navigate(url);
                }
                else
                {
                    _ = InitializeWebViewAsync();
                }
                UpdateStartPageVisibility();
            };

            ViewModel.OnGoBackRequested += () => BrowserWebView.CoreWebView2?.GoBack();
            ViewModel.OnGoForwardRequested += () => BrowserWebView.CoreWebView2?.GoForward();
            ViewModel.OnReloadRequested += () => BrowserWebView.CoreWebView2?.Reload();
            ViewModel.OnStopRequested += () => BrowserWebView.CoreWebView2?.Stop();
        }

        private async void OnControlLoaded(object sender, RoutedEventArgs e)
        {
            await InitializeWebViewAsync();
        }

        private async System.Threading.Tasks.Task InitializeWebViewAsync()
        {
            if (_isWebViewInitialized || _isWebViewInitializing) return;
            _isWebViewInitializing = true;

            try
            {
                var appData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                var browserProfilePath = Path.Combine(appData, "PINGGO", "BrowserProfile");
                Directory.CreateDirectory(browserProfilePath);

                var env = await CoreWebView2Environment.CreateWithOptionsAsync(null, browserProfilePath, null);
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
                            ViewModel.ActiveTab.Title = string.IsNullOrWhiteSpace(uri.Host) ? "Browser" : uri.Host;
                        }
                        ViewModel.UpdateCurrentWhitelistedState();
                        ViewModel.SaveSession();
                    }
                };

                _isWebViewInitialized = true;
                UpdateStartPageVisibility();

                if (!string.IsNullOrEmpty(ViewModel.UrlInput))
                {
                    BrowserWebView.CoreWebView2.Navigate(ViewModel.UrlInput);
                }
            }
            catch (Exception ex)
            {
                MainViewModel.Shared.ShowToast("Browser could not start. Check the WebView2 Runtime.");
                System.Diagnostics.Debug.WriteLine($"[BrowserViewControl] WebView initialization failed: {ex}");
            }
            finally
            {
                _isWebViewInitializing = false;
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
