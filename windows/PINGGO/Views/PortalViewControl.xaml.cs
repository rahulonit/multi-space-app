using System;
using System.Linq;
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
        private bool _isMuted = false;

        public PortalViewControl()
        {
            this.InitializeComponent();
            this.Loaded += OnControlLoaded;
        }

        public void LoadPlatform(string platformId)
        {
            if (_loadedPlatformId == platformId) return;
            _loadedPlatformId = platformId;
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

            var account = data.PlatformAccounts.FirstOrDefault(a => a.PlatformID == platform.Id)
                          ?? new PlatformAccount { Id = Guid.NewGuid(), PlatformID = platform.Id };

            try
            {
                var env = await PortalSessionManager.Shared.GetOrCreateEnvironmentAsync(account);
                await PortalWebView.EnsureCoreWebView2Async(env);

                PortalSessionManager.Shared.ConfigureSessionWebView(PortalWebView.CoreWebView2, account, platform);
                AdBlockEngine.AttachToWebView(PortalWebView.CoreWebView2);

                PortalWebView.CoreWebView2.Navigate(platform.ResolvedWebsiteURL);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[PortalViewControl] WebView init error: {ex.Message}");
            }
        }

        private void OnGoBack(object sender, RoutedEventArgs e)
        {
            if (PortalWebView.CoreWebView2?.CanGoBack == true) PortalWebView.CoreWebView2.GoBack();
        }

        private void OnGoForward(object sender, RoutedEventArgs e)
        {
            if (PortalWebView.CoreWebView2?.CanGoForward == true) PortalWebView.CoreWebView2.GoForward();
        }

        private void OnReload(object sender, RoutedEventArgs e)
        {
            PortalWebView.CoreWebView2?.Reload();
        }

        private void OnToggleMute(object sender, RoutedEventArgs e)
        {
            if (PortalWebView.CoreWebView2 != null)
            {
                _isMuted = !_isMuted;
                PortalWebView.CoreWebView2.IsMuted = _isMuted;
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
            var url = PortalWebView.Source?.AbsoluteUri;
            if (!string.IsNullOrEmpty(url))
            {
                await Windows.System.Launcher.LaunchUriAsync(new Uri(url));
            }
        }

        private void OnPasskeyChipClicked(object sender, RoutedEventArgs e)
        {
            MainViewModel.Shared.ShowToast("Passkey ready: Click Sign In on the page to authenticate via Windows Hello.");
        }
    }
}
