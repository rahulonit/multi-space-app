using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Models;
using PINGGO.Services;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class PortalViewControl : UserControl
    {
        private string? _loadedPlatformId;
        private Guid? _loadedAccountId;
        private bool _isMuted = false;
        private WebView2? _portalWebView;
        private int _loadGeneration;

        public PortalViewControl()
        {
            this.InitializeComponent();
            this.Loaded += OnControlLoaded;
        }

        public void LoadPlatform(string platformId)
        {
            var selectedAccountId = MainViewModel.Shared.GetSelectedAccount(platformId)?.Id;
            if (_loadedPlatformId == platformId && _loadedAccountId == selectedAccountId && _portalWebView != null) return;
            _loadedPlatformId = platformId;
            _loadedAccountId = selectedAccountId;
            InitWebViewAsync(platformId);
        }

        private async void OnControlLoaded(object sender, RoutedEventArgs e)
        {
            var platformId = MainViewModel.Shared.ActivePlatformId;
            if (!string.IsNullOrEmpty(platformId))
            {
                LoadPlatform(platformId);
            }
        }

        private async void InitWebViewAsync(string platformId)
        {
            var data = DataStoreService.Shared.CurrentData;
            var platform = data.SocialPlatforms.FirstOrDefault(p => p.Id == platformId)
                           ?? SocialPlatform.DefaultPlatforms.First();

            PlatformTitleText.Text = platform.Name;

            var account = MainViewModel.Shared.GetSelectedAccount(platform.Id)
                          ?? new PlatformAccount { Id = Guid.NewGuid(), PlatformID = platform.Id };
            _loadedAccountId = account.Id;
            AccountNameText.Text = account.AccountName;
            DisposeCurrentWebView();
            var generation = ++_loadGeneration;
            var webView = new WebView2
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch
            };
            _portalWebView = webView;
            WebViewHost.Children.Add(webView);

            try
            {
                var env = await PortalSessionManager.Shared.GetOrCreateEnvironmentAsync(account);
                if (generation != _loadGeneration) return;
                await webView.EnsureCoreWebView2Async(env);
                if (generation != _loadGeneration) return;

                PortalSessionManager.Shared.ConfigureSessionWebView(
                    webView.CoreWebView2,
                    account,
                    platform,
                    path => DispatcherQueue.TryEnqueue(async () => await ShowDocumentOptionsAsync(path)));
                AdBlockEngine.AttachToWebView(webView.CoreWebView2);

                webView.CoreWebView2.Navigate(platform.ResolvedWebsiteURL);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[PortalViewControl] WebView init error: {ex.Message}");
            }
        }

        private void OnGoBack(object sender, RoutedEventArgs e)
        {
            if (_portalWebView?.CoreWebView2?.CanGoBack == true) _portalWebView.CoreWebView2.GoBack();
        }

        private void OnGoForward(object sender, RoutedEventArgs e)
        {
            if (_portalWebView?.CoreWebView2?.CanGoForward == true) _portalWebView.CoreWebView2.GoForward();
        }

        private void OnReload(object sender, RoutedEventArgs e)
        {
            _portalWebView?.CoreWebView2?.Reload();
        }

        private void OnToggleMute(object sender, RoutedEventArgs e)
        {
            if (_portalWebView?.CoreWebView2 != null)
            {
                _isMuted = !_isMuted;
                _portalWebView.CoreWebView2.IsMuted = _isMuted;
                MuteIcon.Glyph = _isMuted ? "\uE74F" : "\uE767"; // Mute vs sound glyph
                MainViewModel.Shared.ShowToast(_isMuted ? "Tab audio muted" : "Tab audio unmuted");
            }
        }

        private void OnSplitViewClicked(object sender, RoutedEventArgs e)
        {
            MainViewModel.Shared.ToggleSplitView();
        }

        private async void OnOpenInEdge(object sender, RoutedEventArgs e)
        {
            var url = _portalWebView?.Source?.AbsoluteUri;
            if (!string.IsNullOrEmpty(url))
            {
                await Windows.System.Launcher.LaunchUriAsync(new Uri(url));
            }
        }

        private void OnPasskeyChipClicked(object sender, RoutedEventArgs e)
        {
            MainViewModel.Shared.ShowToast("Passkey ready: Click Sign In on the page to authenticate via Windows Hello.");
        }

        private void OnAccountMenuClicked(object sender, RoutedEventArgs e)
        {
            if (_loadedPlatformId == null) return;
            var flyout = new MenuFlyout();
            var accounts = MainViewModel.Shared.GetAccounts(_loadedPlatformId);
            foreach (var account in accounts)
            {
                var item = new MenuFlyoutItem
                {
                    Text = account.AccountName,
                    Icon = account.Id == _loadedAccountId ? new SymbolIcon(Symbol.Accept) : new SymbolIcon(Symbol.Contact)
                };
                item.Click += (_, _) => MainViewModel.Shared.SelectAccount(account.Id);
                flyout.Items.Add(item);
            }
            flyout.Items.Add(new MenuFlyoutSeparator());

            var addItem = new MenuFlyoutItem { Text = "Add account…", Icon = new SymbolIcon(Symbol.Add) };
            addItem.Click += async (_, _) => await ShowAddAccountDialogAsync();
            flyout.Items.Add(addItem);

            var activeAccount = accounts.FirstOrDefault(account => account.Id == _loadedAccountId);
            if (activeAccount != null && MainViewModel.Shared.CanDeleteAccount(activeAccount))
            {
                var deleteItem = new MenuFlyoutItem { Text = "Delete this account…", Icon = new SymbolIcon(Symbol.Delete) };
                deleteItem.Click += async (_, _) => await ConfirmDeleteAccountAsync(activeAccount);
                flyout.Items.Add(deleteItem);
            }
            flyout.ShowAt(AccountMenuButton);
        }

        private async Task ShowAddAccountDialogAsync()
        {
            if (_loadedPlatformId == null) return;
            var accountNumber = MainViewModel.Shared.GetAccounts(_loadedPlatformId).Count + 1;
            var nameBox = new TextBox { Text = $"Account {accountNumber}", PlaceholderText = "Account name" };
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "Add account",
                Content = nameBox,
                PrimaryButtonText = "Add",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Primary
            };
            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                MainViewModel.Shared.AddAccount(_loadedPlatformId, nameBox.Text);
            }
        }

        private async Task ConfirmDeleteAccountAsync(PlatformAccount account)
        {
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = $"Delete {account.AccountName}?",
                Content = $"This removes {account.AccountName} from PINGGO and clears its separate website session. Your account on the social platform is not deleted.",
                PrimaryButtonText = "Delete account",
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Close
            };
            if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            {
                if (_loadedAccountId == account.Id) DisposeCurrentWebView();
                MainViewModel.Shared.RemoveAccount(account.Id);
                if (_loadedPlatformId != null) LoadPlatform(_loadedPlatformId);
            }
        }

        private async Task ShowDocumentOptionsAsync(string filePath)
        {
            var explorerButton = new Button
            {
                Content = "Show in File Explorer",
                HorizontalAlignment = HorizontalAlignment.Left
            };
            var content = new StackPanel { Spacing = 12 };
            content.Children.Add(new TextBlock
            {
                Text = $"{Path.GetFileName(filePath)} is ready. Choose where you want to open it.",
                TextWrapping = TextWrapping.Wrap
            });
            content.Children.Add(explorerButton);

            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "Document downloaded",
                Content = content,
                PrimaryButtonText = "Open in Pinggo",
                SecondaryButtonText = "Open with Default App",
                CloseButtonText = "Not now",
                DefaultButton = ContentDialogButton.Primary
            };
            explorerButton.Click += (_, _) =>
            {
                ShowInFileExplorer(filePath);
                dialog.Hide();
            };

            var result = await dialog.ShowAsync();
            if (result == ContentDialogResult.Primary)
            {
                await ShowPinggoDocumentPreviewAsync(filePath);
            }
            else if (result == ContentDialogResult.Secondary)
            {
                OpenWithDefaultApp(filePath);
            }
        }

        private async Task ShowPinggoDocumentPreviewAsync(string filePath)
        {
            var preview = new WebView2
            {
                Source = new Uri(filePath),
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch,
                MinWidth = 760,
                MinHeight = 520
            };
            var dialog = new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = Path.GetFileName(filePath),
                Content = preview,
                PrimaryButtonText = "Open with Default App",
                SecondaryButtonText = "Show in File Explorer",
                CloseButtonText = "Done",
                DefaultButton = ContentDialogButton.Close,
                MinWidth = 820,
                MaxWidth = 1000
            };
            var result = await dialog.ShowAsync();
            preview.Close();
            if (result == ContentDialogResult.Primary) OpenWithDefaultApp(filePath);
            if (result == ContentDialogResult.Secondary) ShowInFileExplorer(filePath);
        }

        private static void OpenWithDefaultApp(string filePath)
        {
            Process.Start(new ProcessStartInfo(filePath) { UseShellExecute = true });
        }

        private static void ShowInFileExplorer(string filePath)
        {
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{filePath}\"") { UseShellExecute = true });
        }

        private void DisposeCurrentWebView()
        {
            _loadGeneration++;
            _portalWebView?.Close();
            WebViewHost.Children.Clear();
            _portalWebView = null;
        }
    }
}
