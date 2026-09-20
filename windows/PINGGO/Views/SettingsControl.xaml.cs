using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Services;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class SettingsControl : UserControl
    {
        public SettingsControl()
        {
            this.InitializeComponent();
            this.Loaded += OnControlLoaded;
        }

        private void OnControlLoaded(object sender, RoutedEventArgs e)
        {
            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            GeminiKeyBox.Password = prefs.GeminiApiKey;
            OpenAiKeyBox.Password = prefs.OpenAiApiKey;
            AppLockToggle.IsOn = prefs.AppLockEnabled;
            BlockAdsToggle.IsOn = prefs.AdBlockBlockAds;
            BlockTrackersToggle.IsOn = prefs.AdBlockBlockTrackers;
            BlockCookiesToggle.IsOn = prefs.AdBlockBlockCookieBanners;
        }

        private async void OnTestGeminiClicked(object sender, RoutedEventArgs e)
        {
            var key = GeminiKeyBox.Password.Trim();
            AiStatusText.Visibility = Visibility.Visible;
            AiStatusText.Text = "Testing Google Gemini connection...";

            var (ok, msg) = await AIService.Shared.TestConnectionAsync("gemini", key);
            AiStatusText.Text = msg;

            if (ok)
            {
                DataStoreService.Shared.CurrentData.Preferences.GeminiApiKey = key;
                DataStoreService.Shared.Save();
            }
        }

        private async void OnTestOpenAiClicked(object sender, RoutedEventArgs e)
        {
            var key = OpenAiKeyBox.Password.Trim();
            AiStatusText.Visibility = Visibility.Visible;
            AiStatusText.Text = "Testing OpenAI ChatGPT connection...";

            var (ok, msg) = await AIService.Shared.TestConnectionAsync("chatgpt", key);
            AiStatusText.Text = msg;

            if (ok)
            {
                DataStoreService.Shared.CurrentData.Preferences.OpenAiApiKey = key;
                DataStoreService.Shared.Save();
            }
        }

        private void OnAppLockToggled(object sender, RoutedEventArgs e)
        {
            DataStoreService.Shared.CurrentData.Preferences.AppLockEnabled = AppLockToggle.IsOn;
            DataStoreService.Shared.Save();
        }

        private void OnSavePinClicked(object sender, RoutedEventArgs e)
        {
            var pin = PinBox.Password.Trim();
            if (pin.Length >= 4)
            {
                SecurityService.Shared.SetCustomPin(pin);
                MainViewModel.Shared.ShowToast("Security PIN updated successfully!");
                PinBox.Password = string.Empty;
            }
            else
            {
                MainViewModel.Shared.ShowToast("PIN must be at least 4 digits.");
            }
        }

        private async void OnVerifyWindowsHelloClicked(object sender, RoutedEventArgs e)
        {
            var ok = await SecurityService.Shared.UnlockWithWindowsHelloAsync();
            MainViewModel.Shared.ShowToast(ok ? "Windows Hello verified successfully!" : "Windows Hello verification failed or cancelled.");
        }

        private void OnSavePreferences(object sender, RoutedEventArgs e)
        {
            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            prefs.AdBlockBlockAds = BlockAdsToggle.IsOn;
            prefs.AdBlockBlockTrackers = BlockTrackersToggle.IsOn;
            prefs.AdBlockBlockCookieBanners = BlockCookiesToggle.IsOn;
            DataStoreService.Shared.Save();
        }
    }
}
