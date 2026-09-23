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
        public string Id => Name;
        public string Name { get; set; } = string.Empty;
        public string Role { get; set; } = string.Empty;
        public string Activity { get; set; } = string.Empty;
        public int MessageCount { get; set; }
        public string? PhoneNumber { get; set; }
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

        public bool HasActionItems => ActionItems != null && ActionItems.Count > 0;
        public bool HasPhoneNumbers => PhoneNumbers != null && PhoneNumbers.Count > 0;
        public bool HasMembers => Members != null && Members.Count > 0;
        public bool HasRelatedPrompts => RelatedPrompts != null && RelatedPrompts.Count > 0;
    }
}
