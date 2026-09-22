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
        public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

        public string ContextSnippet =>
            Messages.Count == 0
                ? (string.IsNullOrEmpty(ContactName) ? "" : $"Active conversation with {ContactName}.")
                : $"Conversation with {ContactName}:\n" + string.Join("\n", Messages.ConvertAll(m => $"{(m.IsFromMe ? "You" : m.Sender)}: {m.Text}"));
    }

    public class CopilotMessage
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Role { get; set; } = "user"; // "user" or "assistant"
        public string Content { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }
}
