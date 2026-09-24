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
}
