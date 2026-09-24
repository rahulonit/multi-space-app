using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using PINGGO.Models;
using PINGGO.Services;
using PINGGO.ViewModels;

namespace PINGGO.Views
{
    public sealed partial class InboxControl : UserControl
    {
        private List<UnifiedMessageItem> _allMessages = new();
        private List<UnifiedMessageItem> _filteredMessages = new();
        private UnifiedMessageItem? _selectedMessage;

        private string _selectedFolder = "Unread";
        private string? _selectedPlatformId = null;
        private string _selectedPriority = "All";
        private string _searchQuery = "";
        private string _activeTone = "Professional";
        private bool _isSummaryExpanded = true;
        private KeywordSmartSummary? _activeKeywordSummary;
        private Dictionary<string, List<AIChatMessage>> _aiChatHistory = new();
        private readonly Dictionary<string, List<AIChatMessage>> _intelligenceChatHistory = new();
        private readonly Dictionary<string, int> _analyzedMessageCounts = new();
        private ChatIntelligenceAnalysis? _chatIntelligenceAnalysis;
        private List<PlatformMessagePreview> _chatIntelligenceMessages = new();
        private bool _isChatIntelligenceVisible = true;
        private bool _isChatIntelligenceExpanded;

        public InboxControl()
        {
            this.InitializeComponent();

            this.Loaded += (s, e) =>
            {
                PlatformsRepeater.ItemsSource = MainViewModel.Shared.Platforms;
                MainViewModel.Shared.OnInboxDataChanged += OnInboxDataChangedFromViewModel;
                RefreshData();
            };

            this.Unloaded += (s, e) =>
            {
                MainViewModel.Shared.OnInboxDataChanged -= OnInboxDataChangedFromViewModel;
            };
        }

        private void OnInboxDataChangedFromViewModel()
        {
            DispatcherQueue?.TryEnqueue(RefreshData);
        }

        public void RefreshData()
        {
            _allMessages = MainViewModel.Shared.GetAllUnifiedMessages();

            var unreadCount = _allMessages.Count(m => m.IsUnread);
            UnreadCountText.Text = unreadCount.ToString();
            UnreadBadge.Visibility = unreadCount > 0 ? Visibility.Visible : Visibility.Collapsed;

            ApplyFilters();
        }

        private void ApplyFilters()
        {
            var q = _searchQuery.Trim();

            // 1. Source List (Search vs Folder)
            List<UnifiedMessageItem> sourceList;

            if (!string.IsNullOrEmpty(q))
            {
                // Smart Keyword / NL crawler
                _activeKeywordSummary = ConversationSummaryService.Shared.GenerateKeywordSmartSummary(q, _allMessages);
                sourceList = _activeKeywordSummary.MatchingMessages;
                UpdateSmartSummaryCard(_activeKeywordSummary);
                UpdateKeywordDossierPane(_activeKeywordSummary);
            }
            else
            {
                _activeKeywordSummary = null;
                switch (_selectedFolder)
                {
                    case "Unread":
                        sourceList = _allMessages.Where(m => m.IsUnread).ToList();
                        break;
                    case "Alerts":
                        sourceList = _allMessages.Where(m => m.Priority == "Urgent").ToList();
                        break;
                    default:
                        sourceList = _allMessages.ToList();
                        break;
                }

                // Show standard AI executive briefing in summary card
                var briefing = ConversationSummaryService.Shared.GenerateExecutiveBriefing(
                    MainViewModel.Shared.Platforms,
                    MainViewModel.Shared.Accounts,
                    MainViewModel.Shared.PlatformActivity
                );

                SummaryCardTitle.Text = "AI Executive Briefing";
                SummaryMatchBadge.Visibility = Visibility.Collapsed;
                SummaryOverviewText.Text = briefing.SummaryText;
                SummaryActionsRepeater.ItemsSource = briefing.ActionItems;
                SummaryActionsBox.Visibility = briefing.ActionItems.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
                SummaryActionsBadge.Visibility = briefing.ActionItems.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
                SummaryActionsCount.Text = $"{briefing.ActionItems.Count} to-do";
                SummaryHighlightsRepeater.ItemsSource = briefing.KeyTopics.Select(t => $"Active discussion: {t}").ToList();
                SummaryRelatedArea.Visibility = Visibility.Collapsed;
            }

            // 2. Filter by Platform
            if (!string.IsNullOrEmpty(_selectedPlatformId))
            {
                sourceList = sourceList.Where(m => m.Platform.Id == _selectedPlatformId).ToList();
            }

            // 3. Filter by Priority
            if (_selectedPriority != "All")
            {
                sourceList = sourceList.Where(m => m.Priority.Equals(_selectedPriority, StringComparison.OrdinalIgnoreCase)).ToList();
            }

            _filteredMessages = sourceList;
            MessagesListView.ItemsSource = _filteredMessages;

            // Stream counter header
            if (!string.IsNullOrEmpty(q))
            {
                StreamCounterText.Text = $"{_filteredMessages.Count} MATCHING CONVERSATION{(_filteredMessages.Count == 1 ? "" : "S")}";
            }
            else if (_selectedFolder == "Unread")
            {
                StreamCounterText.Text = $"{_filteredMessages.Count} UNREAD CONVERSATION{(_filteredMessages.Count == 1 ? "" : "S")}";
            }
            else
            {
                StreamCounterText.Text = $"{_filteredMessages.Count} CONVERSATION{(_filteredMessages.Count == 1 ? "" : "S")}";
            }

            UpdateReaderPane();
        }

        private void UpdateSmartSummaryCard(KeywordSmartSummary summary)
        {
            SummaryCardTitle.Text = summary.IsTaskOrTodoQuery ? "AI Action Items Summary" : $"Smart Summary: \"{summary.Keyword}\"";
            SummaryMatchBadge.Visibility = Visibility.Visible;
            SummaryMatchCount.Text = $"{summary.MatchCount} match{(summary.MatchCount == 1 ? "" : "es")}";

            SummaryOverviewText.Text = summary.ExecutiveOverview;

            // Actions
            SummaryActionsRepeater.ItemsSource = summary.ActionItems;
            SummaryActionsBox.Visibility = summary.ActionItems.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            SummaryActionsBadge.Visibility = summary.ActionItems.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            SummaryActionsCount.Text = $"{summary.ActionItems.Count} to-do";

            // Highlights
            SummaryHighlightsRepeater.ItemsSource = summary.KeyTakeaways;

            // Related searches
            SummaryRelatedRepeater.ItemsSource = summary.RelatedSearches;
            SummaryRelatedArea.Visibility = summary.RelatedSearches.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        private void UpdateKeywordDossierPane(KeywordSmartSummary summary)
        {
            DossierTitleText.Text = summary.IsTaskOrTodoQuery ? "To-Do & Action Synthesis" : "Smart Summary Dossier";
            DossierKeywordText.Text = $"“{summary.Keyword}”";
            DossierSubheaderText.Text = $"{summary.MatchCount} matching conversation{(summary.MatchCount == 1 ? "" : "s")} across {string.Join(", ", summary.PlatformNames)}";

            DossierHeadlineText.Text = summary.Headline;
            DossierOverviewText.Text = summary.ExecutiveOverview;

            DossierActionsRepeater.ItemsSource = summary.ActionItems;
            DossierActionBox.Visibility = summary.ActionItems.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

            DossierHighlightsRepeater.ItemsSource = summary.KeyTakeaways;
            DossierHighlightsBox.Visibility = summary.KeyTakeaways.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

            DossierRelatedRepeater.ItemsSource = summary.RelatedSearches;
            DossierRelatedBox.Visibility = summary.RelatedSearches.Count > 0 ? Visibility.Visible : Visibility.Collapsed;

            DossierIndexedHeader.Text = $"INDEXED CONVERSATIONS ({summary.MatchingMessages.Count})";
            DossierIndexedRepeater.ItemsSource = summary.MatchingMessages;
        }

        private void UpdateReaderPane()
        {
            var q = _searchQuery.Trim();

            if (_selectedMessage != null)
            {
                ConversationDetailPane.Visibility = Visibility.Visible;
                KeywordDossierPane.Visibility = Visibility.Collapsed;
                EmptyReaderPane.Visibility = Visibility.Collapsed;

                DetailAvatarText.Text = _selectedMessage.DisplaySender.Substring(0, 1).ToUpperInvariant();
                DetailSenderText.Text = _selectedMessage.DisplaySender;
                DetailPlatformText.Text = _selectedMessage.Platform.Name;
                DetailMessageText.Text = _selectedMessage.Message.Text;

                // Back banner
                if (!string.IsNullOrEmpty(q))
                {
                    BackToDossierBanner.Visibility = Visibility.Visible;
                    BackToDossierText.Text = $"Back to Smart Dossier for “{q}”";
                }
                else
                {
                    BackToDossierBanner.Visibility = Visibility.Collapsed;
                }

                // AI Suggested Replies
                UpdateSuggestedReplies();

                UpdateChatIntelligence();
            }
            else if (!string.IsNullOrEmpty(q) && _activeKeywordSummary != null)
            {
                ConversationDetailPane.Visibility = Visibility.Collapsed;
                KeywordDossierPane.Visibility = Visibility.Visible;
                EmptyReaderPane.Visibility = Visibility.Collapsed;
                SetChatIntelligenceVisibility(false);
            }
            else
            {
                ConversationDetailPane.Visibility = Visibility.Collapsed;
                KeywordDossierPane.Visibility = Visibility.Collapsed;
                EmptyReaderPane.Visibility = Visibility.Visible;
                SetChatIntelligenceVisibility(false);
            }
        }

        private void UpdateSuggestedReplies()
        {
            if (_selectedMessage == null) return;

            var baseReplies = _selectedMessage.SuggestedReplies;
            if (baseReplies == null || baseReplies.Count == 0)
            {
                baseReplies = new List<string>
                {
                    "Sounds good, thank you for the update!",
                    "Looking into this now, will follow up shortly.",
                    "Could you share more details?"
                };
            }

            var adjusted = new List<string>();
            foreach (var r in baseReplies)
            {
                if (_activeTone == "Friendly")
                {
                    adjusted.Add(r.EndsWith(".") ? r.Substring(0, r.Length - 1) + "! 😊" : r + " 😊");
                }
                else if (_activeTone == "Direct")
                {
                    adjusted.Add(r.Replace("Sounds great! ", "").Replace("Yes, absolutely. ", ""));
                }
                else
                {
                    adjusted.Add(r);
                }
            }

            DetailRepliesRepeater.ItemsSource = adjusted;
        }

        // MARK: - Event Handlers
        private void OnFolderClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string folder)
            {
                _selectedFolder = folder;
                _selectedMessage = null;
                MessagesListView.SelectedItem = null;

                // Highlight clicked folder
                FolderUnreadBtn.Background = folder == "Unread" ? (Microsoft.UI.Xaml.Media.Brush)Resources["AppCardBrush"] : null;
                FolderAlertsBtn.Background = folder == "Alerts" ? (Microsoft.UI.Xaml.Media.Brush)Resources["AppCardBrush"] : null;
                FolderAllBtn.Background = folder == "All" ? (Microsoft.UI.Xaml.Media.Brush)Resources["AppCardBrush"] : null;

                ApplyFilters();
            }
        }

        private void OnPlatformFilterClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn)
            {
                var platformId = btn.Tag as string;
                _selectedPlatformId = string.IsNullOrEmpty(platformId) ? null : platformId;
                _selectedMessage = null;
                MessagesListView.SelectedItem = null;
                ApplyFilters();
            }
        }

        private void OnPriorityFilterClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string priority)
            {
                _selectedPriority = priority;
                _selectedMessage = null;
                MessagesListView.SelectedItem = null;
                ApplyFilters();
            }
        }

        private void OnSearchTextChanged(object sender, TextChangedEventArgs e)
        {
            _searchQuery = SearchBox.Text;
            ClearSearchBtn.Visibility = string.IsNullOrEmpty(_searchQuery) ? Visibility.Collapsed : Visibility.Visible;
            _selectedMessage = null;
            MessagesListView.SelectedItem = null;
            ApplyFilters();
        }

        private void OnClearSearchClicked(object sender, RoutedEventArgs e)
        {
            SearchBox.Text = "";
            _searchQuery = "";
            _selectedMessage = null;
            MessagesListView.SelectedItem = null;
            ApplyFilters();
        }

        private void OnQuickPromptClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string prompt)
            {
                SearchBox.Text = prompt;
            }
        }

        private void OnRelatedSearchChipClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string query)
            {
                SearchBox.Text = query;
            }
        }

        private void OnToggleSummaryExpanded(object sender, RoutedEventArgs e)
        {
            _isSummaryExpanded = !_isSummaryExpanded;
            SummaryExpandedArea.Visibility = _isSummaryExpanded ? Visibility.Visible : Visibility.Collapsed;
            SummaryChevron.Glyph = _isSummaryExpanded ? "\uE70E" : "\uE70D"; // ChevronUp vs ChevronDown
        }

        private void OnMessageSelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (MessagesListView.SelectedItem is UnifiedMessageItem item)
            {
                _selectedMessage = item;
                UpdateReaderPane();
            }
        }

        private void OnBackToDossierClicked(object sender, RoutedEventArgs e)
        {
            _selectedMessage = null;
            MessagesListView.SelectedItem = null;
            UpdateReaderPane();
        }

        private void OnOpenIndexedMessageClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string id)
            {
                var match = _filteredMessages.FirstOrDefault(m => m.Id == id) ?? _allMessages.FirstOrDefault(m => m.Id == id);
                if (match != null)
                {
                    _selectedMessage = match;
                    MessagesListView.SelectedItem = match;
                    UpdateReaderPane();
                }
            }
        }

        private void OnReplyToneChanged(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string tone)
            {
                _activeTone = tone;
                UpdateSuggestedReplies();
            }
        }

        private void OnCopyReplyTextClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string text)
            {
                var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
                package.SetText(text);
                Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
                MainViewModel.Shared.ShowToast("Reply draft copied to clipboard!");
            }
        }

        private async void OnInjectReplyTextClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string text)
            {
                var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
                package.SetText(text);
                Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);

                MainViewModel.Shared.ShowToast("Reply copied & ready to inject into active chat portal!");
            }
        }

        // MARK: - Private, conversation-scoped AI Chat Intelligence
        private List<PlatformMessagePreview> GetChatIntelligenceMessages()
        {
            if (_selectedMessage == null) return new List<PlatformMessagePreview>();
            var context = MainViewModel.Shared.GetActiveThreadContext(_selectedMessage.AccountId, _selectedMessage.DisplaySender);
            if (context != null && context.Messages.Count > 0)
            {
                return context.Messages.TakeLast(ChatIntelligenceService.MaximumMessages).Select(message => new PlatformMessagePreview
                {
                    Id = message.Id,
                    Sender = message.IsFromMe ? "You" : message.Sender,
                    Text = message.Text,
                    Time = message.Time,
                    Unread = false
                }).ToList();
            }

            var previews = _allMessages
                .Where(message => message.AccountId == _selectedMessage.AccountId &&
                                  message.DisplaySender.Equals(_selectedMessage.DisplaySender, StringComparison.OrdinalIgnoreCase))
                .Select(message => message.Message)
                .TakeLast(ChatIntelligenceService.MaximumMessages)
                .ToList();
            return previews.Count == 0 ? new List<PlatformMessagePreview> { _selectedMessage.Message } : previews;
        }

        private List<AIChatMemberItem>? GetChatIntelligenceMetadataMembers()
        {
            if (_selectedMessage == null) return null;
            return MainViewModel.Shared.GetActiveThreadContext(_selectedMessage.AccountId, _selectedMessage.DisplaySender)?.GroupMembers;
        }

        private void SetChatIntelligenceVisibility(bool visible)
        {
            var shouldShow = visible && _selectedMessage != null;
            ChatIntelligencePane.Visibility = shouldShow ? Visibility.Visible : Visibility.Collapsed;
            ChatIntelligenceDivider.Visibility = shouldShow ? Visibility.Visible : Visibility.Collapsed;
            ChatIntelligenceColumn.Width = shouldShow ? new GridLength(390) : new GridLength(0);
            ChatIntelligenceDividerColumn.Width = shouldShow ? new GridLength(1) : new GridLength(0);
        }

        private void UpdateChatIntelligence(bool forceRefresh = false)
        {
            if (_selectedMessage == null)
            {
                SetChatIntelligenceVisibility(false);
                return;
            }

            _chatIntelligenceMessages = GetChatIntelligenceMessages();
            _chatIntelligenceAnalysis = ChatIntelligenceService.Shared.Analyze(_selectedMessage.Id, _chatIntelligenceMessages);
            var previousCount = _analyzedMessageCounts.TryGetValue(_selectedMessage.Id, out var count) ? count : _chatIntelligenceMessages.Count;
            var newCount = Math.Max(0, _chatIntelligenceMessages.Count - previousCount);
            if (forceRefresh || !_analyzedMessageCounts.ContainsKey(_selectedMessage.Id)) _analyzedMessageCounts[_selectedMessage.Id] = _chatIntelligenceMessages.Count;

            var resolution = AIProviderResolver.Resolve(AppPreferences.Shared);
            ChatIntelligenceBadgeText.Text = resolution.DisplayBadge;

            SetChatIntelligenceVisibility(_isChatIntelligenceVisible);
            ChatIntelligenceNewMessagesButton.Visibility = newCount > 0 && !forceRefresh ? Visibility.Visible : Visibility.Collapsed;
            ChatIntelligenceNewMessagesText.Text = $"{newCount} new message{(newCount == 1 ? "" : "s")} available — Refresh analysis";
            ChatIntelligenceMessageCountText.Text = $"Analyzed {_chatIntelligenceAnalysis.MessageCount} message{(_chatIntelligenceAnalysis.MessageCount == 1 ? "" : "s")}";

            PopulateSimpleList(ChatIntelligenceSummaryItems,
                _chatIntelligenceAnalysis.HasUsefulContext ? _chatIntelligenceAnalysis.Summary : new List<string> { "Not enough conversation context yet." });
            PopulateExpandedIntelligenceDetails(_chatIntelligenceAnalysis);
            PopulateIntelligenceQuestions(_chatIntelligenceAnalysis.SuggestedQuestions);
            PopulateIntelligenceChat();

            var members = ChatIntelligenceService.Shared.GroundedMembers(_chatIntelligenceMessages, GetChatIntelligenceMetadataMembers());
            ChatIntelligenceExportActions.Visibility = members.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
        }

        private void PopulateSimpleList(StackPanel panel, IEnumerable<string> values)
        {
            panel.Children.Clear();
            foreach (var value in values)
            {
                panel.Children.Add(new TextBlock
                {
                    Text = $"• {value}",
                    FontSize = 11.5,
                    TextWrapping = TextWrapping.Wrap,
                    Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 226, 232, 240))
                });
            }
        }

        private void PopulateExpandedIntelligenceDetails(ChatIntelligenceAnalysis analysis)
        {
            ChatIntelligenceExpandedDetails.Children.Clear();
            AddIntelligenceSection("MAIN TOPICS", analysis.Topics);
            AddIntelligenceSection("IMPORTANT DECISIONS", analysis.Decisions);
            AddIntelligenceSection("PENDING TASKS", analysis.Tasks);
            AddIntelligenceSection("DATES & DEADLINES", analysis.Dates);
            AddIntelligenceSection("UNRESOLVED QUESTIONS", analysis.UnresolvedQuestions);
            AddIntelligenceSection("LINKS", analysis.Links);
            AddIntelligenceSection("PHONE NUMBERS", analysis.PhoneNumbers);

            if (analysis.Sources.Count > 0)
            {
                var sourceStack = new StackPanel { Spacing = 5 };
                sourceStack.Children.Add(new TextBlock { Text = "SOURCES", FontSize = 9.5, FontWeight = Microsoft.UI.Text.FontWeights.Bold, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppTextMutedBrush"] });
                foreach (var source in analysis.Sources.TakeLast(8))
                {
                    var button = new Button { Content = source.Label, Tag = source.MessageId, FontSize = 9.5, Padding = new Thickness(7, 3, 7, 3), HorizontalAlignment = HorizontalAlignment.Left };
                    button.Click += (_, _) =>
                    {
                        var message = _chatIntelligenceMessages.FirstOrDefault(item => item.Id == source.MessageId);
                        if (message != null) DetailMessageText.Text = message.Text;
                        MainViewModel.Shared.ShowToast($"Source: {source.Label}");
                    };
                    sourceStack.Children.Add(button);
                }
                ChatIntelligenceExpandedDetails.Children.Add(sourceStack);
            }
        }

        private void AddIntelligenceSection(string title, IReadOnlyCollection<string> values)
        {
            if (values.Count == 0) return;
            var stack = new StackPanel { Spacing = 4 };
            stack.Children.Add(new TextBlock { Text = title, FontSize = 9.5, FontWeight = Microsoft.UI.Text.FontWeights.Bold, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppTextMutedBrush"] });
            foreach (var value in values.Take(8))
            {
                stack.Children.Add(new TextBlock { Text = $"• {value}", FontSize = 10.5, TextWrapping = TextWrapping.Wrap, Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 226, 232, 240)) });
            }
            ChatIntelligenceExpandedDetails.Children.Add(stack);
        }

        private void PopulateIntelligenceQuestions(IEnumerable<string> questions)
        {
            ChatIntelligenceQuestionsPanel.Children.Clear();
            foreach (var question in questions)
            {
                var button = new Button
                {
                    Content = question,
                    Tag = question,
                    FontSize = 10.5,
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = HorizontalAlignment.Left,
                    Background = (Microsoft.UI.Xaml.Media.Brush)Resources["AppPanelBrush"],
                    BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Resources["AppBorderBrush"],
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(7),
                    Padding = new Thickness(8, 6, 8, 6)
                };
                button.Click += (_, _) => SendIntelligenceQuestion(question);
                ChatIntelligenceQuestionsPanel.Children.Add(button);
            }
            ChatIntelligenceSuggestionsSection.Visibility = ChatIntelligenceQuestionsPanel.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        private void PopulateIntelligenceChat()
        {
            IntelligenceChatLogContainer.Children.Clear();
            if (_selectedMessage == null || !_intelligenceChatHistory.TryGetValue(_selectedMessage.Id, out var history)) return;
            foreach (var message in history) IntelligenceChatLogContainer.Children.Add(CreateAiChatBubbleControl(message));
        }

        private async void SendIntelligenceQuestion(string question)
        {
            if (_selectedMessage == null || _chatIntelligenceAnalysis == null || string.IsNullOrWhiteSpace(question)) return;
            var clean = question.Trim();
            if (!_intelligenceChatHistory.TryGetValue(_selectedMessage.Id, out var history))
            {
                history = new List<AIChatMessage>();
                _intelligenceChatHistory[_selectedMessage.Id] = history;
            }
            history.Add(new AIChatMessage { IsUser = true, Text = clean, Timestamp = DateTime.UtcNow });
            IntelligenceChatInputBox.Text = string.Empty;
            PopulateIntelligenceChat();

            var prefs = AppPreferences.Shared;
            var aiMsg = await ChatIntelligenceService.Shared.AnswerAsync(clean, _chatIntelligenceAnalysis, _chatIntelligenceMessages, GetChatIntelligenceMetadataMembers(), prefs);
            history.Add(aiMsg);
            PopulateIntelligenceChat();
        }

        private void OnToggleChatIntelligenceClicked(object sender, RoutedEventArgs e)
        {
            _isChatIntelligenceVisible = !_isChatIntelligenceVisible;
            SetChatIntelligenceVisibility(_isChatIntelligenceVisible);
        }

        private void OnRefreshChatIntelligenceClicked(object sender, RoutedEventArgs e)
        {
            if (_selectedMessage != null)
            {
                _analyzedMessageCounts[_selectedMessage.Id] = GetChatIntelligenceMessages().Count;
                _intelligenceChatHistory.Remove(_selectedMessage.Id);
            }
            UpdateChatIntelligence(true);
        }

        private void OnExpandChatIntelligenceClicked(object sender, RoutedEventArgs e)
        {
            _isChatIntelligenceExpanded = !_isChatIntelligenceExpanded;
            ChatIntelligenceExpandedDetails.Visibility = _isChatIntelligenceExpanded ? Visibility.Visible : Visibility.Collapsed;
            ChatIntelligenceExpandButton.Content = _isChatIntelligenceExpanded ? "Collapse" : "Expand";
        }

        private void OnCopyChatSummaryClicked(object sender, RoutedEventArgs e)
        {
            if (_chatIntelligenceAnalysis == null) return;
            CopyText(string.Join(Environment.NewLine, _chatIntelligenceAnalysis.Summary.Select(item => "• " + item)));
            MainViewModel.Shared.ShowToast("AI summary copied");
        }

        private void OnSendIntelligenceChatClicked(object sender, RoutedEventArgs e) => SendIntelligenceQuestion(IntelligenceChatInputBox.Text);

        private void OnIntelligenceChatInputKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter) SendIntelligenceQuestion(IntelligenceChatInputBox.Text);
        }

        private void OnCopyMembersClicked(object sender, RoutedEventArgs e)
        {
            var members = ChatIntelligenceService.Shared.GroundedMembers(_chatIntelligenceMessages, GetChatIntelligenceMetadataMembers());
            CopyText(BuildMembersCsv(members));
            MainViewModel.Shared.ShowToast("Member list copied");
        }

        private void OnExportMembersCsvClicked(object sender, RoutedEventArgs e)
        {
            var members = ChatIntelligenceService.Shared.GroundedMembers(_chatIntelligenceMessages, GetChatIntelligenceMetadataMembers());
            var downloads = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
            Directory.CreateDirectory(downloads);
            var path = Path.Combine(downloads, $"PINGGO-group-members-{DateTime.Now:yyyyMMdd-HHmmss}.csv");
            File.WriteAllText(path, BuildMembersCsv(members), Encoding.UTF8);
            MainViewModel.Shared.ShowToast($"Member CSV exported to Downloads: {Path.GetFileName(path)}");
        }

        private string BuildMembersCsv(IEnumerable<AIChatMemberItem> members)
        {
            static string Csv(string value) => $"\"{value.Replace("\"", "\"\"")}\"";
            var platform = _selectedMessage?.Platform.Name ?? string.Empty;
            var rows = members.Select(member => string.Join(",", new[] { member.Name, member.PhoneNumber ?? string.Empty, string.Empty, platform, member.Role, member.Activity }.Select(Csv)));
            return string.Join(Environment.NewLine, new[] { "Name,Phone Number,Username,Platform,Role,Status" }.Concat(rows));
        }

        private static void CopyText(string text)
        {
            var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
            package.SetText(text);
            Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
        }

        // MARK: - Smart Summary & AI Assistant Chat (Pane 3)
        private void UpdateAiChatAssistant()
        {
            if (_selectedMessage == null) return;
            AiChatLogContainer.Children.Clear();

            var history = GetAiChatHistoryFor(_selectedMessage);
            foreach (var msg in history)
            {
                AiChatLogContainer.Children.Add(CreateAiChatBubbleControl(msg));
            }
        }

        private List<AIChatMessage> GetAiChatHistoryFor(UnifiedMessageItem item)
        {
            if (_aiChatHistory.TryGetValue(item.Id, out var existing) && existing.Count > 0)
            {
                return existing;
            }

            var analysis = ConversationSummaryService.Shared.AnalyzeMessage(item.Message);
            var initText = $"✨ **Executive Summary with {item.DisplaySender}**:\n\n{analysis.ContextSummary}\n\n";
            if (!string.IsNullOrEmpty(analysis.DetectedQuestion))
            {
                initText += $"❓ **Detected Question**: \"{analysis.DetectedQuestion}\"\n";
            }
            if (!string.IsNullOrEmpty(analysis.ActionItem))
            {
                initText += $"📌 **Detected Action**: {analysis.ActionItem}\n";
            }
            initText += $"\n💬 *I'm ready to search this chat and connected groups. You can ask me questions like:* \n• \"What is to-do for me today?\"\n• \"How many states are using CPWD in this group?\"\n• \"What is {item.DisplaySender} saying regarding...\"\n• \"List all members in this group\"\n• \"Find phone numbers for all users\"";

            var initMsg = new AIChatMessage
            {
                Id = $"init-{item.Id}",
                IsUser = false,
                Text = initText,
                Timestamp = DateTime.UtcNow,
                ActionItems = !string.IsNullOrEmpty(analysis.ActionItem) ? new List<string> { analysis.ActionItem } : null,
                RelatedPrompts = new List<string>
                {
                    "⚡ What is to-do for me today?",
                    "🏢 How many states are using CPWD?",
                    "👥 List all members in this group",
                    "📞 Find phone numbers for all users"
                }
            };

            var list = new List<AIChatMessage> { initMsg };
            _aiChatHistory[item.Id] = list;
            return list;
        }

        private UIElement CreateAiChatBubbleControl(AIChatMessage msg)
        {
            if (msg.IsUser)
            {
                var userBorder = new Border
                {
                    Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 99, 102, 241)),
                    CornerRadius = new CornerRadius(10),
                    Padding = new Thickness(12, 8, 12, 8),
                    HorizontalAlignment = HorizontalAlignment.Right,
                    MaxWidth = 480
                };
                userBorder.Child = new TextBlock
                {
                    Text = msg.Text,
                    FontSize = 12.5,
                    FontWeight = Microsoft.UI.Text.FontWeights.Medium,
                    Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 255, 255, 255)),
                    TextWrapping = TextWrapping.Wrap
                };
                return userBorder;
            }
            else
            {
                var aiBorder = new Border
                {
                    Background = (Microsoft.UI.Xaml.Media.Brush)Resources["AppCardBrush"],
                    BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Resources["AppBorderBrush"],
                    BorderThickness = new Thickness(1),
                    CornerRadius = new CornerRadius(10),
                    Padding = new Thickness(14, 12, 14, 12),
                    HorizontalAlignment = HorizontalAlignment.Stretch
                };

                var sp = new StackPanel { Spacing = 8 };

                // Header with AI Icon
                var headerSp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                headerSp.Children.Add(new FontIcon { Glyph = "\uE76E", FontSize = 11, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppAccentBrush"] });
                var badgeText = msg.Source?.BadgeText ?? "PINGGO AI · Grounded in this chat";
                headerSp.Children.Add(new TextBlock { Text = badgeText, FontSize = 10, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppAccentBrush"] });
                sp.Children.Add(headerSp);

                // Body text
                sp.Children.Add(new TextBlock
                {
                    Text = msg.Text,
                    FontSize = 12.5,
                    Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 240, 240, 240)),
                    TextWrapping = TextWrapping.Wrap,
                    LineHeight = 20
                });

                // Action Items
                if (msg.HasActionItems)
                {
                    var actionBox = new Border
                    {
                        Background = (Microsoft.UI.Xaml.Media.Brush)Resources["AppPanelBrush"],
                        CornerRadius = new CornerRadius(8),
                        Padding = new Thickness(10, 8, 10, 8),
                        Margin = new Thickness(0, 4, 0, 0)
                    };
                    var actionSp = new StackPanel { Spacing = 6 };
                    actionSp.Children.Add(new TextBlock { Text = "ACTION ITEMS", FontSize = 9.5, FontWeight = Microsoft.UI.Text.FontWeights.Bold, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppTextMutedBrush"] });
                    foreach (var act in msg.ActionItems!)
                    {
                        var cb = new CheckBox
                        {
                            Content = act,
                            FontSize = 11.5,
                            Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 230, 230, 230)),
                            Margin = new Thickness(0, 2, 0, 2)
                        };
                        actionSp.Children.Add(cb);
                    }
                    actionBox.Child = actionSp;
                    sp.Children.Add(actionBox);
                }

                // Discovered Phone Numbers
                if (msg.HasPhoneNumbers)
                {
                    var phoneBox = new Border
                    {
                        Background = (Microsoft.UI.Xaml.Media.Brush)Resources["AppPanelBrush"],
                        CornerRadius = new CornerRadius(8),
                        Padding = new Thickness(10, 8, 10, 8),
                        Margin = new Thickness(0, 4, 0, 0)
                    };
                    var phoneSp = new StackPanel { Spacing = 6 };
                    phoneSp.Children.Add(new TextBlock { Text = "DISCOVERED PHONE NUMBERS", FontSize = 9.5, FontWeight = Microsoft.UI.Text.FontWeights.Bold, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppTextMutedBrush"] });
                    foreach (var p in msg.PhoneNumbers!)
                    {
                        var rowGrid = new Grid { Margin = new Thickness(0, 2, 0, 2) };
                        rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                        rowGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                        var infoSp = new StackPanel { Spacing = 1 };
                        infoSp.Children.Add(new TextBlock { Text = p.Name, FontSize = 11.5, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 255, 255, 255)) });
                        infoSp.Children.Add(new TextBlock { Text = p.Number, FontSize = 12, FontWeight = Microsoft.UI.Text.FontWeights.Bold, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppAccentBrush"] });
                        infoSp.Children.Add(new TextBlock { Text = p.Context, FontSize = 9.5, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppTextMutedBrush"] });

                        var copyBtn = new Button
                        {
                            Content = "Copy",
                            FontSize = 10,
                            Padding = new Thickness(8, 4, 8, 4),
                            CornerRadius = new CornerRadius(5),
                            Background = (Microsoft.UI.Xaml.Media.Brush)Resources["AppCardBrush"],
                            Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppTextMutedBrush"],
                            BorderThickness = new Thickness(0),
                            VerticalAlignment = VerticalAlignment.Center
                        };
                        copyBtn.Click += (s, e) =>
                        {
                            var dp = new Windows.ApplicationModel.DataTransfer.DataPackage();
                            dp.SetText(p.Number);
                            Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(dp);
                            MainViewModel.Shared.ShowToast($"Copied {p.Number} to clipboard");
                        };

                        Grid.SetColumn(infoSp, 0);
                        Grid.SetColumn(copyBtn, 1);
                        rowGrid.Children.Add(infoSp);
                        rowGrid.Children.Add(copyBtn);
                        phoneSp.Children.Add(rowGrid);
                    }
                    phoneBox.Child = phoneSp;
                    sp.Children.Add(phoneBox);
                }

                // Discovered Members
                if (msg.HasMembers)
                {
                    var memBox = new Border
                    {
                        Background = (Microsoft.UI.Xaml.Media.Brush)Resources["AppPanelBrush"],
                        CornerRadius = new CornerRadius(8),
                        Padding = new Thickness(10, 8, 10, 8),
                        Margin = new Thickness(0, 4, 0, 0)
                    };
                    var memSp = new StackPanel { Spacing = 6 };
                    int displayCount = msg.Members.Count;
                    if (!string.IsNullOrEmpty(msg.Text))
                    {
                        var mMatch = System.Text.RegularExpressions.Regex.Match(msg.Text, @"(\d+)\s*(Total Members|members)", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                        if (mMatch.Success && int.TryParse(mMatch.Groups[1].Value, out int parsed) && parsed > 0)
                        {
                            displayCount = parsed;
                        }
                    }

                    var headerGrid = new Grid();
                    headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                    var headerText = new TextBlock
                    {
                        Text = $"👥 Available Group Members ({displayCount}):",
                        FontSize = 10,
                        FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                        Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppAccentBrush"],
                        VerticalAlignment = VerticalAlignment.Center
                    };
                    Grid.SetColumn(headerText, 0);

                    var badgeBorder = new Border
                    {
                        Background = (Microsoft.UI.Xaml.Media.Brush)Resources["AppCardBrush"],
                        CornerRadius = new CornerRadius(10),
                        Padding = new Thickness(6, 2, 6, 2),
                        BorderThickness = new Thickness(1),
                        BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Resources["AppAccentBrush"],
                        Child = new TextBlock
                        {
                            Text = $"{displayCount} Members",
                            FontSize = 9.5,
                            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                            Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppAccentBrush"]
                        }
                    };
                    Grid.SetColumn(badgeBorder, 1);

                    headerGrid.Children.Add(headerText);
                    headerGrid.Children.Add(badgeBorder);
                    memSp.Children.Add(headerGrid);

                    foreach (var m in msg.Members!)
                    {
                        var rowSp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                        rowSp.Children.Add(new TextBlock { Text = $"• {m.Name}", FontSize = 11.5, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = new Microsoft.UI.Xaml.Media.SolidColorBrush(Windows.UI.Color.FromArgb(255, 255, 255, 255)) });
                        rowSp.Children.Add(new TextBlock { Text = $"— {m.Role}", FontSize = 11, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppTextMutedBrush"] });
                        if (!string.IsNullOrEmpty(m.PhoneNumber))
                        {
                            var phoneBtn = new Button
                            {
                                Content = $"📞 {m.PhoneNumber}",
                                Tag = m.PhoneNumber,
                                FontSize = 9.5,
                                Padding = new Thickness(6, 2, 6, 2),
                                CornerRadius = new CornerRadius(4),
                                Background = (Microsoft.UI.Xaml.Media.Brush)Resources["AppCardBrush"],
                                Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppAccentBrush"],
                                BorderThickness = new Thickness(0.8),
                                BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Resources["AppAccentBrush"]
                            };
                            phoneBtn.Click += (s, e) =>
                            {
                                var dp = new Windows.ApplicationModel.DataTransfer.DataPackage();
                                dp.SetText(m.PhoneNumber);
                                Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(dp);
                                MainViewModel.Shared.ShowToast($"Copied {m.PhoneNumber} to clipboard");
                            };
                            rowSp.Children.Add(phoneBtn);
                        }
                        rowSp.Children.Add(new TextBlock { Text = $"· {m.Activity}", FontSize = 10, Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppTextMutedBrush"] });
                        memSp.Children.Add(rowSp);
                    }
                    memBox.Child = memSp;
                    sp.Children.Add(memBox);
                }

                // Related Prompts
                if (msg.HasRelatedPrompts)
                {
                    var promptSp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Margin = new Thickness(0, 4, 0, 0) };
                    foreach (var prompt in msg.RelatedPrompts!)
                    {
                        var btn = new Button
                        {
                            Content = prompt,
                            Tag = prompt,
                            FontSize = 10,
                            Padding = new Thickness(8, 4, 8, 4),
                            CornerRadius = new CornerRadius(10),
                            Background = (Microsoft.UI.Xaml.Media.Brush)Resources["AppPanelBrush"],
                            Foreground = (Microsoft.UI.Xaml.Media.Brush)Resources["AppAccentBrush"],
                            BorderThickness = new Thickness(1),
                            BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Resources["AppBorderBrush"]
                        };
                        btn.Click += OnAiPromptChipClicked;
                        promptSp.Children.Add(btn);
                    }
                    sp.Children.Add(promptSp);
                }

                aiBorder.Child = sp;
                return aiBorder;
            }
        }

        private void OnSendAiChatClicked(object sender, RoutedEventArgs e)
        {
            var text = AiChatInputBox.Text?.Trim();
            if (!string.IsNullOrEmpty(text))
            {
                SendAiChatQuestion(text);
                AiChatInputBox.Text = "";
            }
        }

        private void OnAiChatInputKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs e)
        {
            if (e.Key == Windows.System.VirtualKey.Enter)
            {
                OnSendAiChatClicked(sender, e);
            }
        }

        private void OnAiPromptChipClicked(object sender, RoutedEventArgs e)
        {
            if (sender is Button btn && btn.Tag is string prompt)
            {
                SendAiChatQuestion(prompt);
            }
        }

        private void OnResetAiChatClicked(object sender, RoutedEventArgs e)
        {
            if (_selectedMessage != null)
            {
                _aiChatHistory.Remove(_selectedMessage.Id);
                UpdateAiChatAssistant();
                MainViewModel.Shared.ShowToast("Reset AI Chat for this conversation");
            }
        }

        private void SendAiChatQuestion(string question)
        {
            if (_selectedMessage == null) return;
            var history = GetAiChatHistoryFor(_selectedMessage);
            var userMsg = new AIChatMessage
            {
                Id = Guid.NewGuid().ToString(),
                IsUser = true,
                Text = question,
                Timestamp = DateTime.UtcNow
            };
            history.Add(userMsg);
            UpdateAiChatAssistant();

            // AI Answer
            ActiveThreadContext? activeCtx = null;
            if (MainViewModel.Shared.AccountThreadContexts.TryGetValue(_selectedMessage.AccountId, out var ctx))
            {
                var clean = (_selectedMessage.DisplaySender ?? _selectedMessage.Message?.Sender ?? "").Trim().ToLowerInvariant();
                var activeClean = (ctx.ContactName ?? "").Trim().ToLowerInvariant();
                if (string.IsNullOrEmpty(clean) || activeClean == clean || activeClean.Contains(clean) || clean.Contains(activeClean))
                {
                    activeCtx = ctx;
                }
                else if (ctx.Messages != null && ctx.Messages.Any(m => (m.Sender ?? "").Trim().Equals(clean, StringComparison.OrdinalIgnoreCase)))
                {
                    activeCtx = ctx;
                }
                else if (ctx.GroupMembers != null && ctx.GroupMembers.Any(gm => (gm.Name ?? "").Trim().Equals(clean, StringComparison.OrdinalIgnoreCase)))
                {
                    activeCtx = ctx;
                }
            }

            var threadMessages = activeCtx?.Messages != null && activeCtx.Messages.Count > 0
                ? activeCtx.Messages
                : new List<PlatformMessagePreview> { _selectedMessage.Message };

            var aiResponse = ConversationSummaryService.Shared.AnswerChatAssistantQuestion(
                question,
                _selectedMessage,
                threadMessages,
                _allMessages,
                activeCtx
            );
            history.Add(aiResponse);
            UpdateAiChatAssistant();
        }
    }
}
