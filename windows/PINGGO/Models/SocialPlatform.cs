using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace PINGGO.Models
{
    public class OfficialIdentity
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("symbol")]
        public string Symbol { get; set; } = string.Empty;

        [JsonPropertyName("primaryCategory")]
        public string PrimaryCategory { get; set; } = "Other";

        [JsonPropertyName("color")]
        public string Color { get; set; } = "blue";

        [JsonPropertyName("officialURL")]
        public string OfficialURL { get; set; } = string.Empty;

        [JsonPropertyName("unreadBadgeSelector")]
        public string? UnreadBadgeSelector { get; set; }
    }

    public class SocialPlatform
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("symbol")]
        public string Symbol { get; set; } = "globe";

        [JsonPropertyName("color")]
        public string Color { get; set; } = "blue";

        [JsonPropertyName("websiteURL")]
        public string? WebsiteURL { get; set; }

        [JsonPropertyName("customWebsiteURL")]
        public string? CustomWebsiteURL { get; set; }

        [JsonPropertyName("officialIdentityId")]
        public string? OfficialIdentityId { get; set; }

        [JsonPropertyName("categories")]
        public List<string> Categories { get; set; } = new();

        [JsonPropertyName("customJS")]
        public string CustomJS { get; set; } = string.Empty;

        [JsonPropertyName("customCSS")]
        public string CustomCSS { get; set; } = string.Empty;

        [JsonPropertyName("unreadBadgeSelector")]
        public string? UnreadBadgeSelector { get; set; }

        [JsonPropertyName("customIcon")]
        public bool? CustomIcon { get; set; }

        [JsonIgnore]
        public string ResolvedWebsiteURL =>
            !string.IsNullOrWhiteSpace(CustomWebsiteURL) ? CustomWebsiteURL : (WebsiteURL ?? "https://google.com");

        [JsonIgnore]
        public bool UsesOfficialLogo => !string.IsNullOrEmpty(OfficialIdentityId);

        public static List<SocialPlatform> DefaultPlatforms => new()
        {
            new SocialPlatform { Id = "whatsapp", Name = "WhatsApp", OfficialIdentityId = "whatsapp", Symbol = "message.fill", Color = "green", WebsiteURL = "https://web.whatsapp.com", Categories = new() { "Messaging" }, UnreadBadgeSelector = "span[aria-label*='unread']" },
            new SocialPlatform { Id = "telegram", Name = "Telegram", OfficialIdentityId = "telegram", Symbol = "paperplane.fill", Color = "cyan", WebsiteURL = "https://web.telegram.org/a/", Categories = new() { "Messaging" }, UnreadBadgeSelector = ".chat-badge" },
            new SocialPlatform { Id = "discord", Name = "Discord", OfficialIdentityId = "discord", Symbol = "bubble.left.and.bubble.right.fill", Color = "indigo", WebsiteURL = "https://discord.com/app", Categories = new() { "Community", "Gaming" } },
            new SocialPlatform { Id = "slack", Name = "Slack", OfficialIdentityId = "slack", Symbol = "number", Color = "purple", WebsiteURL = "https://app.slack.com/client", Categories = new() { "Work", "Messaging" } },
            new SocialPlatform { Id = "messenger", Name = "Messenger", OfficialIdentityId = "messenger", Symbol = "bolt.horizontal.fill", Color = "blue", WebsiteURL = "https://www.messenger.com", Categories = new() { "Messaging" } },
            new SocialPlatform { Id = "instagram", Name = "Instagram", OfficialIdentityId = "instagram", Symbol = "camera.fill", Color = "pink", WebsiteURL = "https://www.instagram.com/direct/inbox/", Categories = new() { "Social" } },
            new SocialPlatform { Id = "twitter", Name = "X (Twitter)", OfficialIdentityId = "twitter", Symbol = "bubble.left.fill", Color = "black", WebsiteURL = "https://x.com/messages", Categories = new() { "Social" } },
            new SocialPlatform { Id = "wechat", Name = "WeChat", OfficialIdentityId = "wechat", Symbol = "person.2.fill", Color = "green", WebsiteURL = "https://web.wechat.com", Categories = new() { "Messaging" } },
            new SocialPlatform { Id = "teams", Name = "Microsoft Teams", OfficialIdentityId = "teams", Symbol = "person.3.fill", Color = "indigo", WebsiteURL = "https://teams.microsoft.com", Categories = new() { "Work" } },
            new SocialPlatform { Id = "chatgpt", Name = "ChatGPT", OfficialIdentityId = "chatgpt", Symbol = "sparkles", Color = "emerald", WebsiteURL = "https://chatgpt.com", Categories = new() { "AI Assistant" } },
            new SocialPlatform { Id = "gmail", Name = "Gmail", OfficialIdentityId = "gmail", Symbol = "envelope.fill", Color = "red", WebsiteURL = "https://mail.google.com", Categories = new() { "Email", "Work" } },
            new SocialPlatform { Id = "reddit", Name = "Reddit", OfficialIdentityId = "reddit", Symbol = "bubble.left.and.bubble.right.fill", Color = "orange", WebsiteURL = "https://www.reddit.com/message/inbox", Categories = new() { "Community" } },
            new SocialPlatform { Id = "notion", Name = "Notion", OfficialIdentityId = "notion", Symbol = "note.text", Color = "gray", WebsiteURL = "https://www.notion.so", Categories = new() { "Productivity" } },
            new SocialPlatform { Id = "linkedin", Name = "LinkedIn", OfficialIdentityId = "linkedin", Symbol = "briefcase.fill", Color = "blue", WebsiteURL = "https://www.linkedin.com/messaging/", Categories = new() { "Work", "Professional" } },
            new SocialPlatform { Id = "github", Name = "GitHub", OfficialIdentityId = "github", Symbol = "chevron.left.forwardslash.chevron.right", Color = "slate", WebsiteURL = "https://github.com/notifications", Categories = new() { "Developer" } },
            new SocialPlatform { Id = "youtube", Name = "YouTube", OfficialIdentityId = "youtube", Symbol = "play.rectangle.fill", Color = "red", WebsiteURL = "https://www.youtube.com", Categories = new() { "Media" } }
        };
    }
}
