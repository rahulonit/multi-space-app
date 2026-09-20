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
}
