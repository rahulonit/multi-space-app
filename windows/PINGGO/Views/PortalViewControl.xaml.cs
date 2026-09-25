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
        private string _activeTone = "Friendly";
        private bool _isGeneratingReply = false;
        private readonly System.Collections.Generic.List<CopilotMessage> _copilotHistory = new();

        public PortalViewControl()
        {
            this.InitializeComponent();
            this.Loaded += OnControlLoaded;

            PortalSessionManager.Shared.OnActiveThreadUpdated += (accountId, ctx) =>
            {
                if (_loadedAccountId == accountId)
                {
                    DispatcherQueue?.TryEnqueue(() =>
                    {
                        if (CopilotDrawer.Visibility == Visibility.Visible)
                        {
                            UpdateCopilotDrawerContent(ctx);
                        }
                    });
                }
            };
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
                    path => DispatcherQueue.TryEnqueue(() => HandleDownloadCompleted(path)));
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

        private void HandleDownloadCompleted(string filePath)
        {
            if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath)) return;
            try
            {
                var ext = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant();
                if (ext == "pdf")
                {
                    // PDF opened in browser
                    try
                    {
                        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("msedge", $"\"{filePath}\"") { UseShellExecute = true });
                    }
                    catch
                    {
                        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(filePath) { UseShellExecute = true });
                    }
                }
                else
                {
                    // Media or other file opened in OS default app
                    System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(filePath) { UseShellExecute = true });
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[PortalViewControl] Failed to open download {filePath}: {ex.Message}");
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

        #region AI Co-Pilot Drawer Logic

        private void OnToggleCopilotDrawer(object sender, RoutedEventArgs e)
        {
            if (CopilotDrawer.Visibility == Visibility.Visible)
            {
                CopilotDrawer.Visibility = Visibility.Collapsed;
            }
            else
            {
                CopilotDrawer.Visibility = Visibility.Visible;
                UpdateCopilotDrawerContent();
            }
        }

        private void OnCloseCopilotDrawer(object sender, RoutedEventArgs e)
        {
            CopilotDrawer.Visibility = Visibility.Collapsed;
        }

        private void UpdateCopilotDrawerContent(ActiveThreadContext? threadCtx = null)
        {
            var ctx = threadCtx ?? (_loadedAccountId.HasValue && MainViewModel.Shared.AccountThreadContexts.TryGetValue(_loadedAccountId.Value, out var c) ? c : null);

            var contact = !string.IsNullOrWhiteSpace(ctx?.ContactName) ? ctx.ContactName : (PlatformTitleText.Text ?? "Active Chat");
            CopilotContactName.Text = contact;

            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            if (prefs.AiProvider == "gemini" && !string.IsNullOrWhiteSpace(prefs.GeminiApiKey))
            {
                ProviderBadgeText.Text = "Gemini";
                ProviderIndicatorDot.Fill = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 34, 197, 94));
            }
            else if (prefs.AiProvider == "chatgpt" && !string.IsNullOrWhiteSpace(prefs.OpenAiApiKey))
            {
                ProviderBadgeText.Text = "ChatGPT";
                ProviderIndicatorDot.Fill = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 34, 197, 94));
            }
            else if (prefs.AiProvider == "ollama")
            {
                ProviderBadgeText.Text = $"Ollama ({prefs.OllamaModel})";
                ProviderIndicatorDot.Fill = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 168, 85, 247));
            }
            else
            {
                ProviderBadgeText.Text = "Smart Engine";
                ProviderIndicatorDot.Fill = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 245, 158, 11));
            }

            RenderCopilotHistory();

            var textForSentiment = ctx?.ContextSnippet ?? "";
            var sentiment = AIService.Shared.AnalyzeSentiment(textForSentiment);

            SentimentClassificationText.Text = $"Sentiment: {sentiment.Classification}";
            SentimentScoreText.Text = $"{(sentiment.Score >= 0 ? "+" : "")}{sentiment.Score:0.0}";
            SentimentGauge.Value = Math.Clamp((sentiment.Score + 1.0) / 2.0 * 100.0, 5, 100);

            if (sentiment.Score <= -0.4)
            {
                UrgencyBadgeText.Text = "Urgent";
                UrgencyBadgeText.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 239, 68, 68));
                UrgencyBadge.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(50, 239, 68, 68));
                SentimentScoreText.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 239, 68, 68));
            }
            else if (sentiment.Score >= 0.3)
            {
                UrgencyBadgeText.Text = "Positive";
                UrgencyBadgeText.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 34, 197, 94));
                UrgencyBadge.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(50, 34, 197, 94));
                SentimentScoreText.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 34, 197, 94));
            }
            else
            {
                UrgencyBadgeText.Text = "Normal";
                UrgencyBadgeText.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 59, 130, 246));
                UrgencyBadge.Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(50, 59, 130, 246));
                SentimentScoreText.Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 59, 130, 246));
            }

            var lastIncoming = ctx?.Messages.LastOrDefault(m => !m.IsFromMe);
            if (lastIncoming != null && !string.IsNullOrWhiteSpace(lastIncoming.Text))
            {
                LatestMessageSnippetContainer.Visibility = Visibility.Visible;
                LatestMessageSnippetText.Text = $"\"{lastIncoming.Text}\"";
            }
            else
            {
                LatestMessageSnippetContainer.Visibility = Visibility.Collapsed;
            }
        }

        private void RenderCopilotHistory()
        {
            if (_copilotHistory.Count == 0)
            {
                CopilotHistoryContainer.Visibility = Visibility.Collapsed;
                CopilotHistoryList.Children.Clear();
                return;
            }

            CopilotHistoryContainer.Visibility = Visibility.Visible;
            CopilotHistoryHeader.Text = $"Conversation · {_copilotHistory.Count}";
            CopilotHistoryList.Children.Clear();

            foreach (var msg in _copilotHistory)
            {
                var isUser = msg.Role == "user";
                var border = new Border
                {
                    Background = isUser
                        ? (Application.Current.Resources["AppAccentBrush"] as Microsoft.UI.Xaml.Media.Brush ?? new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 99, 102, 241)))
                        : new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Colors.Transparent),
                    BorderThickness = new Thickness(0),
                    CornerRadius = new CornerRadius(8),
                    Padding = new Thickness(isUser ? 10 : 0, isUser ? 6 : 4, isUser ? 10 : 0, isUser ? 6 : 4),
                    HorizontalAlignment = isUser ? HorizontalAlignment.Right : HorizontalAlignment.Left,
                    MaxWidth = 294
                };

                var text = new TextBlock
                {
                    Text = msg.Content,
                    FontSize = 11,
                    Foreground = Application.Current.Resources["AppTextBrush"] as Microsoft.UI.Xaml.Media.Brush
                        ?? new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Colors.White),
                    TextWrapping = TextWrapping.Wrap
                };
                border.Child = text;
                CopilotHistoryList.Children.Add(border);
            }
        }

        private void OnResetCopilotHistory(object sender, RoutedEventArgs e)
        {
            _copilotHistory.Clear();
            RenderCopilotHistory();
            MainViewModel.Shared.ShowToast("Conversation memory cleared");
        }

        private async void OnSmartToneClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string tone)
            {
                _activeTone = tone;
                await TriggerGenerateReplyAsync(tone);
            }
        }

        private async Task TriggerGenerateReplyAsync(string tone)
        {
            if (_isGeneratingReply) return;
            _isGeneratingReply = true;

            DraftCard.Visibility = Visibility.Visible;
            DraftToneHeader.Text = $"Reply · {tone}";
            DraftGeneratingRing.IsActive = true;
            DraftContentBox.Text = "";

            var ctx = _loadedAccountId.HasValue && MainViewModel.Shared.AccountThreadContexts.TryGetValue(_loadedAccountId.Value, out var c) ? c : null;
            var contextSnippet = ctx?.ContextSnippet ?? "";
            var contact = !string.IsNullOrWhiteSpace(ctx?.ContactName) ? ctx.ContactName : (PlatformTitleText.Text ?? "user");
            var prompt = $"Draft a {tone} reply to {contact}.";

            _copilotHistory.Add(new CopilotMessage { Role = "user", Content = prompt });
            if (_copilotHistory.Count > 10) _copilotHistory.RemoveRange(0, _copilotHistory.Count - 10);
            RenderCopilotHistory();

            try
            {
                var fullResponse = await AIService.Shared.StreamCoPilotAsync(prompt, contextSnippet, tone, chunk =>
                {
                    DispatcherQueue?.TryEnqueue(() =>
                    {
                        DraftContentBox.Text += chunk;
                    });
                }, _copilotHistory);

                _copilotHistory.Add(new CopilotMessage { Role = "assistant", Content = fullResponse });
                if (_copilotHistory.Count > 10) _copilotHistory.RemoveRange(0, _copilotHistory.Count - 10);
                RenderCopilotHistory();
            }
            catch (Exception ex)
            {
                DraftContentBox.Text = $"[Error generating reply: {ex.Message}]";
            }
            finally
            {
                DraftGeneratingRing.IsActive = false;
                _isGeneratingReply = false;
            }
        }

        private async void OnInsertDraftIntoChat(object sender, RoutedEventArgs e)
        {
            var text = DraftContentBox.Text;
            if (string.IsNullOrWhiteSpace(text) || _portalWebView?.CoreWebView2 == null) return;

            await PortalSessionManager.Shared.InsertTextIntoChatAsync(_portalWebView.CoreWebView2, text);

            InsertBtnIcon.Glyph = "\uE73E"; // Checkmark
            InsertBtnText.Text = "Inserted!";
            MainViewModel.Shared.ShowToast("Reply draft inserted into chat input!");

            await Task.Delay(2000);
            InsertBtnIcon.Glyph = "\uE896"; // Document/Download
            InsertBtnText.Text = "Insert into Chat";
        }

        private async void OnCopyDraft(object sender, RoutedEventArgs e)
        {
            var text = DraftContentBox.Text;
            if (string.IsNullOrWhiteSpace(text)) return;

            var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
            package.SetText(text);
            Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);

            CopyBtnIcon.Glyph = "\uE73E";
            CopyBtnText.Text = "Copied";
            MainViewModel.Shared.ShowToast("Copied draft to clipboard");

            await Task.Delay(2000);
            CopyBtnIcon.Glyph = "\uE8C8";
            CopyBtnText.Text = "Copy";
        }

        private async void OnRegenerateDraft(object sender, RoutedEventArgs e)
        {
            await TriggerGenerateReplyAsync(_activeTone);
        }

        private async void OnCustomPromptKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                await ExecuteCustomPromptAsync();
            }
        }

        private async void OnSendCustomPrompt(object sender, RoutedEventArgs e)
        {
            await ExecuteCustomPromptAsync();
        }

        private async Task ExecuteCustomPromptAsync()
        {
            var prompt = CustomPromptBox.Text?.Trim();
            if (string.IsNullOrWhiteSpace(prompt) || _isGeneratingReply) return;

            CustomPromptBox.Text = "";
            _isGeneratingReply = true;
            DraftCard.Visibility = Visibility.Visible;
            DraftToneHeader.Text = "AI response";
            DraftGeneratingRing.IsActive = true;
            DraftContentBox.Text = "";

            var ctx = _loadedAccountId.HasValue && MainViewModel.Shared.AccountThreadContexts.TryGetValue(_loadedAccountId.Value, out var c) ? c : null;
            var fullTranscript = ctx?.FullTranscript ?? "";
            var isGroup = ctx?.IsGroupChat ?? false;
            var members = ctx?.EffectiveMembers ?? new List<AIChatMemberItem>();
            var memberCount = ctx?.GroupMemberCount ?? members.Count;
            var channelType = isGroup ? $"Group Chat ({memberCount} members)" : $"Direct 1-on-1 Chat with {CopilotContactName.Text}";
            var membersInfo = string.Join("\n", members.Select(m => $"{m.Name}{(string.IsNullOrEmpty(m.PhoneNumber) ? "" : $" ({m.PhoneNumber})")} - {(m.Role.ToLowerInvariant().Contains("admin") ? "👑 " + m.Role : m.Role)} ({m.MessageCount} messages)"));

            _copilotHistory.Add(new CopilotMessage { Role = "user", Content = prompt });
            if (_copilotHistory.Count > 30) _copilotHistory.RemoveRange(0, _copilotHistory.Count - 30);
            RenderCopilotHistory();

            try
            {
                var fullResponse = await AIService.Shared.StreamCoPilotAsync(prompt, fullTranscript, _activeTone, chunk =>
                {
                    DispatcherQueue?.TryEnqueue(() =>
                    {
                        DraftContentBox.Text += chunk;
                    });
                }, _copilotHistory, channelType, membersInfo);

                _copilotHistory.Add(new CopilotMessage { Role = "assistant", Content = fullResponse });
                if (_copilotHistory.Count > 30) _copilotHistory.RemoveRange(0, _copilotHistory.Count - 30);
                RenderCopilotHistory();
            }
            catch (Exception ex)
            {
                DraftContentBox.Text = $"[Error generating response: {ex.Message}]";
            }
            finally
            {
                DraftGeneratingRing.IsActive = false;
                _isGeneratingReply = false;
            }
        }

        #endregion
    }
}
