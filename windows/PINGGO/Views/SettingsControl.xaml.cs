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
            OllamaEndpointBox.Text = string.IsNullOrEmpty(prefs.OllamaEndpoint) ? "http://localhost:11434" : prefs.OllamaEndpoint;
            OllamaModelBox.Text = string.IsNullOrEmpty(prefs.OllamaModel) ? "llama3.2" : prefs.OllamaModel;

            // Set AI Engine index
            AiEngineCombo.SelectedIndex = prefs.AiProvider switch
            {
                "gemini" => 0,
                "chatgpt" => 1,
                "ollama" => 2,
                _ => 3
            };

            // Set Persona style index
            PersonaStyleCombo.SelectedIndex = prefs.PersonaStyle switch
            {
                "Casual & Warm" => 1,
                "Executive & Formal" => 2,
                "Technical & Precise" => 3,
                _ => 0
            };

            AppLockToggle.IsOn = prefs.AppLockEnabled;
            BlockAdsToggle.IsOn = prefs.AdBlockBlockAds;
            BlockTrackersToggle.IsOn = prefs.AdBlockBlockTrackers;
            BlockCookiesToggle.IsOn = prefs.AdBlockBlockCookieBanners;
        }

        private void OnAiEngineChanged(object sender, SelectionChangedEventArgs e)
        {
            if (AiEngineCombo.SelectedItem is ComboBoxItem item && item.Tag is string tag)
            {
                DataStoreService.Shared.CurrentData.Preferences.AiProvider = tag;
                DataStoreService.Shared.Save();
            }
        }

        private void OnPersonaStyleChanged(object sender, SelectionChangedEventArgs e)
        {
            if (PersonaStyleCombo.SelectedItem is ComboBoxItem item && item.Content is string style)
            {
                DataStoreService.Shared.CurrentData.Preferences.PersonaStyle = style;
                DataStoreService.Shared.Save();
            }
        }

        private async void OnTestOllamaClicked(object sender, RoutedEventArgs e)
        {
            var endpoint = OllamaEndpointBox.Text.Trim();
            var model = OllamaModelBox.Text.Trim();
            AiStatusText.Visibility = Visibility.Visible;
            AiStatusText.Text = "Testing Ollama local model server...";

            var (ok, msg) = await AIService.Shared.TestConnectionAsync("ollama", endpoint, model);
            AiStatusText.Text = msg;

            if (ok)
            {
                var prefs = DataStoreService.Shared.CurrentData.Preferences;
                prefs.OllamaEndpoint = endpoint;
                prefs.OllamaModel = model;
                DataStoreService.Shared.Save();
                MainViewModel.Shared.ShowToast("Ollama configuration saved!");
            }
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
                AICredentialStore.Save("gemini", key);
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
                AICredentialStore.Save("openai", key);
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
