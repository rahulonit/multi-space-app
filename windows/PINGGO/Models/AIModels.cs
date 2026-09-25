using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace PINGGO.Models
{
    public class PlatformActivitySnapshot
    {
        [JsonPropertyName("accountID")]
        public Guid AccountID { get; set; }

        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("unreadMessages")]
        public int UnreadMessages { get; set; }

        [JsonPropertyName("notifications")]
        public int Notifications { get; set; }

        [JsonPropertyName("rawNotifications")]
        public string RawNotifications { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.Now;
    }

    public class PlatformConversationSummary
    {
        [JsonPropertyName("platformID")]
        public string PlatformID { get; set; } = string.Empty;

        [JsonPropertyName("summaryText")]
        public string SummaryText { get; set; } = string.Empty;

        [JsonPropertyName("keyTopics")]
        public List<string> KeyTopics { get; set; } = new();

        [JsonPropertyName("sentiment")]
        public string Sentiment { get; set; } = "Neutral";

        [JsonPropertyName("actionItems")]
        public List<string> ActionItems { get; set; } = new();

        [JsonPropertyName("generatedAt")]
        public DateTime GeneratedAt { get; set; } = DateTime.Now;
    }

    public class SmartReplyOption
    {
        public string Tone { get; set; } = "Professional";
        public string Content { get; set; } = string.Empty;
        public string Icon { get; set; } = "Chat";
    }

    public class SentimentResult
    {
        public double Score { get; set; } // -1.0 to +1.0
        public string Classification { get; set; } = "Neutral";
        public string DetectedLanguage { get; set; } = "English";
    }

    public class ActiveChatMessage
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Sender { get; set; } = string.Empty;
        public string Text { get; set; } = string.Empty;
        public bool IsFromMe { get; set; }
        public string? Time { get; set; }
    }

    public class ActiveThreadContext
    {
        public string ContactName { get; set; } = string.Empty;
        public string PlatformId { get; set; } = string.Empty;
        public List<ActiveChatMessage> Messages { get; set; } = new();
        public int? GroupMemberCount { get; set; }
        public string? GroupSubtitle { get; set; }
        public List<AIChatMemberItem>? GroupMembers { get; set; }
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        public string ContextSnippet =>
            Messages.Count == 0
                ? (string.IsNullOrEmpty(ContactName) ? "" : $"Active conversation with {ContactName}.")
                : $"Conversation with {ContactName}:\n" + string.Join("\n", Messages.ConvertAll(m => $"{(m.IsFromMe ? "You" : m.Sender)}: {m.Text}"));

        public bool IsGroupChat =>
            (GroupMemberCount.HasValue && GroupMemberCount.Value > 2) ||
            (!string.IsNullOrEmpty(GroupSubtitle) && (GroupSubtitle.ToLowerInvariant().Contains("participant") || GroupSubtitle.ToLowerInvariant().Contains("member") || GroupSubtitle.ToLowerInvariant().Contains("subscriber") || (GroupSubtitle.Contains(",") && !GroupSubtitle.ToLowerInvariant().Contains("last seen") && !GroupSubtitle.ToLowerInvariant().Contains("typing") && !GroupSubtitle.ToLowerInvariant().Contains("online")))) ||
            (Messages.Where(m => !string.IsNullOrEmpty(m.Sender) && m.Sender.ToLowerInvariant() != "you" && m.Sender.ToLowerInvariant() != "me" && m.Sender.ToLowerInvariant() != "contact" && !string.Equals(m.Sender, ContactName, StringComparison.OrdinalIgnoreCase)).Select(m => m.Sender).Distinct(StringComparer.OrdinalIgnoreCase).Count() > 1);

        public List<AIChatMemberItem> EffectiveMembers
        {
            get
            {
                if (!IsGroupChat)
                {
                    var trimmed = (ContactName ?? "").Trim();
                    if (string.IsNullOrEmpty(trimmed)) return new List<AIChatMemberItem>();
                    var count = Messages.Count(m => !m.IsFromMe);
                    int digits = trimmed.Count(char.IsDigit);
                    bool isPhone = trimmed.StartsWith("+") || (digits >= 9 && !trimmed.Any(char.IsLetter));
                    return new List<AIChatMemberItem>
                    {
                        new AIChatMemberItem
                        {
                            Name = isPhone ? string.Empty : trimmed,
                            Role = "Contact",
                            Activity = "1-on-1 Direct Chat",
                            MessageCount = count,
                            PhoneNumber = isPhone ? trimmed : null
                        }
                    };
                }

                var merged = new List<AIChatMemberItem>();

                string GetDigits(string? s) => string.Concat((s ?? "").Where(char.IsDigit));

                int? FindIndex(AIChatMemberItem item)
                {
                    var itemPhoneDigits = GetDigits(item.CleanPhone);
                    var itemName = item.CleanName.ToLowerInvariant();

                    for (int i = 0; i < merged.Count; i++)
                    {
                        var ex = merged[i];
                        var exPhoneDigits = GetDigits(ex.CleanPhone);
                        var exName = ex.CleanName.ToLowerInvariant();

                        if (!string.IsNullOrEmpty(itemPhoneDigits) && !string.IsNullOrEmpty(exPhoneDigits) && itemPhoneDigits.Length >= 7 && exPhoneDigits.Length >= 7)
                        {
                            if (itemPhoneDigits == exPhoneDigits || itemPhoneDigits.EndsWith(exPhoneDigits) || exPhoneDigits.EndsWith(itemPhoneDigits))
                                return i;
                        }

                        if (!string.IsNullOrEmpty(itemName) && !string.IsNullOrEmpty(exName) && itemName == exName)
                            return i;

                        var exUser = (ex.Username ?? "").Trim().ToLowerInvariant();
                        var itemUser = (item.Username ?? "").Trim().ToLowerInvariant();
                        if (!string.IsNullOrEmpty(itemUser) && !string.IsNullOrEmpty(exUser) && itemUser == exUser)
                            return i;
                        if (!string.IsNullOrEmpty(itemName) && !string.IsNullOrEmpty(exUser) && itemName == exUser)
                            return i;
                        if (!string.IsNullOrEmpty(itemUser) && !string.IsNullOrEmpty(exName) && itemUser == exName)
                            return i;

                        if (item.IsPhoneInName && !string.IsNullOrEmpty(exPhoneDigits) && GetDigits(item.Name) == exPhoneDigits)
                            return i;

                        if (ex.IsPhoneInName && !string.IsNullOrEmpty(itemPhoneDigits) && GetDigits(ex.Name) == itemPhoneDigits)
                            return i;
                    }
                    return null;
                }

                void MergeItem(AIChatMemberItem incoming)
                {
                    var cleanN = (incoming.Name ?? "").Trim();
                    if (string.IsNullOrEmpty(cleanN) && string.IsNullOrEmpty(incoming.PhoneNumber)) return;
                    if (string.Equals(cleanN, ContactName, StringComparison.OrdinalIgnoreCase) || cleanN.Equals("you", StringComparison.OrdinalIgnoreCase) || cleanN.Equals("me", StringComparison.OrdinalIgnoreCase) || cleanN.Equals("contact", StringComparison.OrdinalIgnoreCase)) return;

                    var idx = FindIndex(incoming);
                    if (idx.HasValue)
                    {
                        var ex = merged[idx.Value];
                        if ((string.IsNullOrEmpty(ex.CleanName) || ex.IsPhoneInName) && !string.IsNullOrEmpty(incoming.CleanName)) ex.Name = incoming.CleanName;
                        if (string.IsNullOrEmpty(ex.PhoneNumber) && !string.IsNullOrEmpty(incoming.CleanPhone)) ex.PhoneNumber = incoming.CleanPhone;
                        if (string.IsNullOrEmpty(ex.Username) && !string.IsNullOrEmpty(incoming.Username)) ex.Username = incoming.Username;
                        if (incoming.NormalizedRole == "Group Admin") ex.Role = "Group Admin";
                        ex.MessageCount = Math.Max(ex.MessageCount, incoming.MessageCount);
                        merged[idx.Value] = ex;
                    }
                    else
                    {
                        merged.Add(incoming);
                    }
                }

                if (GroupMembers != null)
                {
                    foreach (var gm in GroupMembers)
                    {
                        MergeItem(gm);
                    }
                }

                foreach (var msg in Messages)
                {
                    var s = (msg.Sender ?? "").Trim();
                    if (!string.IsNullOrEmpty(s) && !s.Equals("you", StringComparison.OrdinalIgnoreCase) && !s.Equals("me", StringComparison.OrdinalIgnoreCase) && !s.Equals("contact", StringComparison.OrdinalIgnoreCase) && !string.Equals(s, ContactName, StringComparison.OrdinalIgnoreCase))
                    {
                        MergeItem(new AIChatMemberItem
                        {
                            Name = s,
                            Role = "Member",
                            Activity = "Active in chat",
                            MessageCount = 0
                        });
                    }
                }

                for (int i = 0; i < merged.Count; i++)
                {
                    var m = merged[i];
                    var mName = m.CleanName.ToLowerInvariant();
                    var mPhoneDigits = GetDigits(m.CleanPhone);
                    var rawNameDigits = GetDigits(m.Name);

                    int count = Messages.Count(msg =>
                    {
                        if (msg.IsFromMe) return false;
                        var s = (msg.Sender ?? "").Trim().ToLowerInvariant();
                        if (!string.IsNullOrEmpty(mName) && s == mName) return true;
                        var sDigits = GetDigits(s);
                        if (!string.IsNullOrEmpty(sDigits) && sDigits.Length >= 7)
                        {
                            if (!string.IsNullOrEmpty(mPhoneDigits) && (sDigits == mPhoneDigits || sDigits.EndsWith(mPhoneDigits) || mPhoneDigits.EndsWith(sDigits))) return true;
                            if (!string.IsNullOrEmpty(rawNameDigits) && (sDigits == rawNameDigits || sDigits.EndsWith(rawNameDigits) || rawNameDigits.EndsWith(sDigits))) return true;
                        }
                        return false;
                    });

                    merged[i].MessageCount = count;
                    if (count > 0)
                    {
                        merged[i].Activity = $"Active in thread ({count} message{(count == 1 ? "" : "s")})";
                    }
                    else if (merged[i].Activity.ToLowerInvariant().Contains("active in thread"))
                    {
                        merged[i].Activity = "In group roster";
                    }
                }

                merged.Sort((a, b) =>
                {
                    bool aAdmin = a.NormalizedRole == "Group Admin";
                    bool bAdmin = b.NormalizedRole == "Group Admin";
                    if (aAdmin && !bAdmin) return -1;
                    if (!aAdmin && bAdmin) return 1;
                    var aDisplay = string.IsNullOrEmpty(a.CleanName) ? (a.CleanPhone ?? "") : a.CleanName;
                    var bDisplay = string.IsNullOrEmpty(b.CleanName) ? (b.CleanPhone ?? "") : b.CleanName;
                    return string.Compare(aDisplay, bDisplay, StringComparison.OrdinalIgnoreCase);
                });

                return merged;
            }
        }

        public List<AIChatMemberItem> GroupAdmins =>
            IsGroupChat
                ? EffectiveMembers.Where(m => m.NormalizedRole == "Group Admin").ToList()
                : new List<AIChatMemberItem>();

        public string FullTranscript =>
            Messages.Count == 0
                ? (string.IsNullOrEmpty(ContactName) ? "No active messages." : $"Conversation with {ContactName}.")
                : string.Join("\n", Messages.Select((m, i) => $"[#{i + 1} | {(m.IsFromMe ? "You" : m.Sender)}{(!string.IsNullOrEmpty(m.Time) ? $" [{m.Time}]" : "")}]: {m.Text}"));

        public string TopicSummary
        {
            get
            {
                if (Messages.Count == 0) return $"Active conversation with {ContactName}. Awaiting incoming messages.";
                var lastIncoming = Messages.LastOrDefault(m => !m.IsFromMe);
                var text = lastIncoming?.Text ?? Messages.LastOrDefault()?.Text ?? "";
                if (!string.IsNullOrEmpty(text))
                {
                    var truncated = text.Length > 120 ? text.Substring(0, 117) + "..." : text;
                    return $"\"{truncated}\"";
                }
                return $"Conversation with {ContactName} ({Messages.Count} messages exchanged).";
            }
        }

        public string ExportCSV()
        {
            var lines = new List<string> { "Name,Phone Number,Role,Username,Message Count" };
            foreach (var m in EffectiveMembers)
            {
                var cleanN = m.CleanName;
                var nameEscaped = cleanN.Contains(",") ? $"\"{cleanN}\"" : cleanN;
                lines.Add($"{nameEscaped},{m.CleanPhone ?? ""},{m.NormalizedRole},{m.Username ?? ""},{m.MessageCount}");
            }
            return string.Join("\n", lines);
        }

        public string ExportJSON()
        {
            var list = EffectiveMembers.ConvertAll(m => new Dictionary<string, object>
            {
                ["name"] = m.CleanName,
                ["phoneNumber"] = m.CleanPhone ?? "",
                ["role"] = m.NormalizedRole,
                ["username"] = m.Username ?? "",
                ["messageCount"] = m.MessageCount
            });
            return System.Text.Json.JsonSerializer.Serialize(list, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
        }
    }

    public class PlatformMessagePreview
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = Guid.NewGuid().ToString();

        [JsonPropertyName("sender")]
        public string Sender { get; set; } = string.Empty;

        [JsonPropertyName("text")]
        public string Text { get; set; } = string.Empty;

        [JsonPropertyName("time")]
        public string? Time { get; set; }

        [JsonPropertyName("unread")]
        public bool Unread { get; set; }

        [JsonPropertyName("avatarUrl")]
        public string? AvatarUrl { get; set; }
    }

    public class UnifiedMessageItem
    {
        public string Id => $"{AccountId}-{Message.Id}";
        public Guid AccountId { get; set; }
        public string AccountName { get; set; } = string.Empty;
        public SocialPlatform Platform { get; set; } = new();
        public PlatformMessagePreview Message { get; set; } = new();
        public DateTime SnapshotDate { get; set; } = DateTime.UtcNow;
        public bool IsUnread { get; set; }
        public string Priority { get; set; } = "Normal";
        public string? ActionItem { get; set; }
        public string? DetectedQuestion { get; set; }
        public List<string> SuggestedReplies { get; set; } = new();

        public string DisplaySender => string.IsNullOrWhiteSpace(Message.Sender) ? "Contact" : Message.Sender;
        public string DisplayTime => Message.Time ?? "Recent";
        public string PriorityBadge => Priority switch
        {
            "Urgent" => "🔥 Urgent",
            "Meeting" => "📅 Meeting",
            "Question" => "❓ Question",
            "Task" => "📝 Task",
            _ => ""
        };
    }

    public class ConversationMessageSummary
    {
        public string Sender { get; set; } = string.Empty;
        public string ContextSummary { get; set; } = string.Empty;
        public string DetectedIntent { get; set; } = string.Empty;
        public string? DetectedQuestion { get; set; }
        public string? ActionItem { get; set; }
        public List<string> SuggestedReplies { get; set; } = new();
        public string Urgency { get; set; } = "Normal";
    }

    public class KeywordSmartSummary
    {
        public string Keyword { get; set; } = string.Empty;
        public int MatchCount { get; set; }
        public List<string> PlatformNames { get; set; } = new();
        public List<string> SenderNames { get; set; } = new();
        public string Headline { get; set; } = string.Empty;
        public string ExecutiveOverview { get; set; } = string.Empty;
        public List<string> KeyTakeaways { get; set; } = new();
        public List<string> DetectedQuestions { get; set; } = new();
        public List<string> ActionItems { get; set; } = new();
        public List<string> RelatedSearches { get; set; } = new();
        public string Urgency { get; set; } = "Normal";
        public bool IsTaskOrTodoQuery { get; set; }
        public List<UnifiedMessageItem> MatchingMessages { get; set; } = new();
    }

    public class CopilotMessage
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Role { get; set; } = "user"; // "user" or "assistant"
        public string Content { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }

    public class AIChatPhoneNumberItem
    {
        public string Id => $"{Name}-{Number}";
        public string Name { get; set; } = string.Empty;
        public string Number { get; set; } = string.Empty;
        public string Context { get; set; } = string.Empty;
    }

    public class AIChatMemberItem
    {
        public string Id => $"{Name}-{Username ?? ""}-{PhoneNumber ?? ""}";
        public string Name { get; set; } = string.Empty;
        public string Role { get; set; } = string.Empty;
        public string Activity { get; set; } = string.Empty;
        public int MessageCount { get; set; }
        public string? PhoneNumber { get; set; }
        public string? Username { get; set; }

        public bool IsPhoneInName
        {
            get
            {
                var trimmed = (Name ?? "").Trim();
                if (string.IsNullOrEmpty(trimmed)) return false;
                int digitCount = trimmed.Count(char.IsDigit);
                if (trimmed.StartsWith("+") && digitCount >= 7) return true;
                if (digitCount >= 9 && !trimmed.Any(char.IsLetter)) return true;
                return false;
            }
        }

        public string? CleanPhone
        {
            get
            {
                var p = (PhoneNumber ?? "").Trim();
                if (!string.IsNullOrEmpty(p)) return p;
                if (IsPhoneInName) return (Name ?? "").Trim();
                return null;
            }
        }

        public string CleanName
        {
            get
            {
                if (IsPhoneInName)
                {
                    var u = (Username ?? "").Trim();
                    if (!string.IsNullOrEmpty(u)) return u;
                    return string.Empty;
                }
                return (Name ?? "").Trim();
            }
        }

        public string NormalizedRole
        {
            get
            {
                var low = (Role ?? "").ToLowerInvariant();
                if (low.Contains("admin") || low.Contains("owner") || low.Contains("creator")) return "Group Admin";
                return "Member";
            }
        }
    }

    public enum AIResponseSourceType
    {
        ProviderGenerated,
        LocalHeuristic,
        StructuredExtraction,
        CachedAIResponse
    }

    public class AIResponseSource
    {
        public AIResponseSourceType SourceType { get; set; } = AIResponseSourceType.LocalHeuristic;
        public string Provider { get; set; } = string.Empty;
        public string Model { get; set; } = string.Empty;
        public string EngineName { get; set; } = "Pinggo Smart Engine";

        public string BadgeText => SourceType switch
        {
            AIResponseSourceType.ProviderGenerated => $"Powered by {Provider} · {Model}",
            AIResponseSourceType.LocalHeuristic => $"Generated locally · {EngineName}",
            AIResponseSourceType.StructuredExtraction => "Extracted locally · Pinggo Smart Engine",
            AIResponseSourceType.CachedAIResponse => "Cached AI Response",
            _ => "Pinggo AI"
        };
    }

    public class AITaskItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Title { get; set; } = string.Empty;
        public string? Assignee { get; set; }
        public string? CreatedBy { get; set; }
        public string? DueDate { get; set; }
        public string? SourceMessageId { get; set; }
        public bool IsCompleted { get; set; }
    }

    public class ConversationAIState
    {
        public string QuestionDraft { get; set; } = string.Empty;
        public List<AIChatMessage> History { get; set; } = new();
        public ChatIntelligenceAnalysis? Analysis { get; set; }
        public string CustomPromptInput { get; set; } = string.Empty;
        public string? DraftedReplyText { get; set; }
        public bool IsDrafting { get; set; }
        public bool IsResponding { get; set; }
        public string? ErrorMessage { get; set; }
        public AIPanelTab ActiveTab { get; set; } = AIPanelTab.Ask;
        public string? PendingConfirmationAction { get; set; }
    }

    public class AIChatMessage
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public bool IsUser { get; set; }
        public string Text { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
        public List<string>? ActionItems { get; set; }
        public List<AIChatPhoneNumberItem>? PhoneNumbers { get; set; }
        public List<AIChatMemberItem>? Members { get; set; }
        public List<string>? RelatedPrompts { get; set; }
        public AIResponseSource? Source { get; set; }
        public List<AITaskItem>? Tasks { get; set; }
        public string? SourceMessageId { get; set; }

        public bool HasActionItems => ActionItems != null && ActionItems.Count > 0;
        public bool HasPhoneNumbers => PhoneNumbers != null && PhoneNumbers.Count > 0;
        public bool HasMembers => Members != null && Members.Count > 0;
        public bool HasRelatedPrompts => RelatedPrompts != null && RelatedPrompts.Count > 0;
        public bool HasTasks => Tasks != null && Tasks.Count > 0;
    }

    public class ChatIntelligenceSource
    {
        public string MessageId { get; set; } = string.Empty;
        public string Sender { get; set; } = string.Empty;
        public string? Time { get; set; }
        public int MessageNumber { get; set; }
        public string Label => string.IsNullOrWhiteSpace(Time) ? $"{Sender} · Message {MessageNumber}" : $"{Sender} · {Time}";
    }

    public class ChatIntelligenceAnalysis
    {
        public string ConversationId { get; set; } = string.Empty;
        public int MessageCount { get; set; }
        public List<string> Summary { get; set; } = new();
        public List<string> Topics { get; set; } = new();
        public List<string> Decisions { get; set; } = new();
        public List<string> Tasks { get; set; } = new();
        public List<string> Dates { get; set; } = new();
        public List<string> People { get; set; } = new();
        public List<string> PhoneNumbers { get; set; } = new();
        public List<string> Emails { get; set; } = new();
        public List<string> Links { get; set; } = new();
        public List<string> Files { get; set; } = new();
        public List<string> UnresolvedQuestions { get; set; } = new();
        public List<string> SuggestedQuestions { get; set; } = new();
        public List<ChatIntelligenceSource> Sources { get; set; } = new();
        public DateTime GeneratedAt { get; set; } = DateTime.UtcNow;
        public bool HasUsefulContext => MessageCount > 0 && Summary.Count > 0;
    }

    public enum ConversationNavTab
    {
        Summary,
        Messages,
        Files,
        Tasks,
        Links,
        Activity,
        Insights
    }

    public enum AIPanelTab
    {
        Ask,
        Tasks,
        Files,
        Activity,
        Actions
    }

    public enum CertaintyLevel
    {
        Confirmed,
        Tentative,
        AIInferred
    }

    public class ProjectDecisionItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Text { get; set; } = string.Empty;
        public string Status { get; set; } = "Approved";
        public CertaintyLevel Certainty { get; set; } = CertaintyLevel.Confirmed;
        public string Source { get; set; } = "Message #4";
        public string? SourceMessageId { get; set; }
        public string TimeString { get; set; } = "Today";
    }

    public class ProjectTaskItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Title { get; set; } = string.Empty;
        public string Owner { get; set; } = "You";
        public string DueDate { get; set; } = "Tomorrow";
        public CertaintyLevel Certainty { get; set; } = CertaintyLevel.Confirmed;
        public string Status { get; set; } = "In Progress";
        public string Source { get; set; } = "Message #2";
        public string? SourceMessageId { get; set; }
        public bool IsDone { get; set; }
    }

    public class ProjectStatusInfo
    {
        public string Status { get; set; } = "On Track";
        public string UpcomingDeadline { get; set; } = "Tomorrow morning";
        public string LatestActivity { get; set; } = "Design review completed";
        public string Source { get; set; } = "Sprint Deliverables Matrix";
        public string? SourceMessageId { get; set; }
    }

    public class NeedsAttentionItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Title { get; set; } = string.Empty;
        public string Urgency { get; set; } = "High";
        public string Category { get; set; } = "Confirmation";
        public string Source { get; set; } = "Message #4";
        public string? SourceMessageId { get; set; }
    }

    public class ConversationTimelineItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string TimeString { get; set; } = string.Empty;
        public string Role { get; set; } = "Team";
        public string Event { get; set; } = string.Empty;
        public string Source { get; set; } = string.Empty;
        public string DayGroup { get; set; } = "Today";
    }

    public class ConversationChangeItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Text { get; set; } = string.Empty;
        public string Source { get; set; } = "AI Delta";
        public string Timestamp { get; set; } = "Today";
    }

    public class SharedFileItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Filename { get; set; } = string.Empty;
        public string SizeString { get; set; } = string.Empty;
        public string FileType { get; set; } = string.Empty;
        public string SharedTime { get; set; } = string.Empty;
        public string? SourceMessageId { get; set; }
    }

    public class SharedLinkItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Title { get; set; } = string.Empty;
        public string Url { get; set; } = string.Empty;
        public string Domain { get; set; } = string.Empty;
        public string SharedTime { get; set; } = string.Empty;
        public string? SourceMessageId { get; set; }
    }

    public class KeyContributorItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string RoleName { get; set; } = string.Empty;
        public int ContributionCount { get; set; }
        public int DecisionsCount { get; set; }
        public int OpenActionsCount { get; set; }
        public bool IsConfirmedRole { get; set; }
    }

    public class UpcomingDeadlineItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Title { get; set; } = string.Empty;
        public string TimeString { get; set; } = string.Empty;
        public CertaintyLevel Certainty { get; set; } = CertaintyLevel.Confirmed;
        public string Source { get; set; } = "Message #1";
        public string? SourceMessageId { get; set; }
    }

    public class WorkstreamStatusItem
    {
        public string Id { get; set; } = Guid.NewGuid().ToString();
        public string Name { get; set; } = string.Empty;
        public int ProgressPercent { get; set; }
        public string StatusString { get; set; } = string.Empty;
    }

    public class ConversationContext
    {
        public string WorkspaceId { get; set; } = "work-workspace";
        public Guid? AccountId { get; set; }
        public string ConversationId { get; set; } = string.Empty;
        public string ConversationTitle { get; set; } = string.Empty;
        public string PlatformId { get; set; } = "platform";
        public string PlatformName { get; set; } = "Messaging Platform";
        public bool IsPreview { get; set; }

        public List<PlatformMessagePreview> Messages { get; set; } = new();
        public int IndexedMessageCount => Messages.Count;
        public string? LatestMessageId { get; set; }
        public string? LastIndexedMessageId { get; set; }
        public DateTime LastAnalyzedAt { get; set; } = DateTime.UtcNow;
        public bool IsStale { get; set; }

        public string SummaryText { get; set; } = string.Empty;
        public List<string> Topics { get; set; } = new();
        public List<ProjectDecisionItem> Decisions { get; set; } = new();
        public List<ProjectTaskItem> Tasks { get; set; } = new();
        public List<UpcomingDeadlineItem> Deadlines { get; set; } = new();
        public List<SharedFileItem> Files { get; set; } = new();
        public List<SharedLinkItem> Links { get; set; } = new();
        public List<KeyContributorItem> Contributors { get; set; } = new();
        public List<ConversationTimelineItem> Timeline { get; set; } = new();
        public List<ConversationChangeItem> RecentChanges { get; set; } = new();
        public List<NeedsAttentionItem> NeedsAttention { get; set; } = new();
        public List<string> OpenQuestions { get; set; } = new();
        public ProjectStatusInfo StatusInfo { get; set; } = new();

        public int TaskCount => Tasks.Count;
        public int CompletedTaskCount => Tasks.Count(t => t.IsDone);
        public int DeadlineCount => Deadlines.Count;
        public int FileCount => Files.Count;
        public int DecisionCount => Decisions.Count;
        public int TopicCount => Topics.Count;

        public int ProgressPercent => Tasks.Count == 0 ? 0 : (CompletedTaskCount * 100) / Tasks.Count;
    }

    public class BrowserHistoryItem
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("urlString")]
        public string UrlString { get; set; } = string.Empty;

        [JsonPropertyName("visitedAt")]
        public DateTime VisitedAt { get; set; } = DateTime.Now;

        [JsonPropertyName("faviconURLString")]
        public string? FaviconURLString { get; set; }
    }

    public class OllamaModelTag
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("model")]
        public string? Model { get; set; }

        [JsonPropertyName("size")]
        public long? Size { get; set; }
    }

    public class OllamaTagsResponse
    {
        [JsonPropertyName("models")]
        public List<OllamaModelTag>? Models { get; set; }
    }
}
