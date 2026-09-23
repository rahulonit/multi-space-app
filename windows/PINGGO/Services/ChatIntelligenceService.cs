using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using PINGGO.Models;

namespace PINGGO.Services
{
    public sealed class ChatIntelligenceService
    {
        public const int MaximumMessages = 100;
        public static ChatIntelligenceService Shared { get; } = new();

        private static readonly HashSet<string> StopWords = new(StringComparer.OrdinalIgnoreCase)
        {
            "about", "after", "again", "also", "and", "are", "been", "before", "but", "can", "could",
            "did", "does", "for", "from", "have", "here", "into", "just", "more", "our", "that", "the",
            "their", "them", "then", "there", "they", "this", "today", "was", "were", "what", "when",
            "where", "which", "will", "with", "would", "you", "your"
        };

        private ChatIntelligenceService() { }

        public ChatIntelligenceAnalysis Analyze(string conversationId, IEnumerable<PlatformMessagePreview> messages)
        {
            var scoped = messages.Where(m => !string.IsNullOrWhiteSpace(m.Text)).TakeLast(MaximumMessages).ToList();
            var result = new ChatIntelligenceAnalysis
            {
                ConversationId = conversationId,
                MessageCount = scoped.Count,
                Sources = scoped.Select((m, i) => new ChatIntelligenceSource
                {
                    MessageId = m.Id,
                    Sender = string.IsNullOrWhiteSpace(m.Sender) ? "Unknown sender" : m.Sender,
                    Time = m.Time,
                    MessageNumber = i + 1
                }).ToList()
            };

            var wordCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var message in scoped)
            {
                var text = message.Text.Trim();
                var lower = text.ToLowerInvariant();
                var referenced = $"{Compact(text)} — {SourceLabel(message, scoped)}";

                if (ContainsAny(lower, "decided", "agreed", "approved", "confirmed", "we'll proceed", "will proceed", "final decision")) AddUnique(result.Decisions, referenced);
                if (ContainsAny(lower, "need to", "needs to", "please ", "todo", "to-do", "action item", "must ", "should ", "will send", "will update", "follow up", "deadline")) AddUnique(result.Tasks, referenced);
                if (text.Contains('?')) AddUnique(result.UnresolvedQuestions, referenced);

                AddMatches(result.Dates, text, @"\b(?:today|tomorrow|tonight|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week|this week|eod|\d{1,2}[:.]\d{2}\s?(?:am|pm)?|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?)\b", RegexOptions.IgnoreCase);
                AddMatches(result.PhoneNumbers, text, @"(?<!\w)(?:\+?\d[\d ()-]{8,}\d)(?!\w)", RegexOptions.None, value => value.Count(char.IsDigit) >= 10);
                AddMatches(result.Emails, text, @"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}", RegexOptions.IgnoreCase);
                AddMatches(result.Links, text, @"https?://[^\s<>]+", RegexOptions.IgnoreCase, null, value => value.TrimEnd('.', ',', ')', ';', ']'));
                AddMatches(result.Files, text, @"\b[^\s/\\]+\.(?:pdf|docx?|xlsx?|pptx?|csv|zip|png|jpe?g|fig|txt)\b", RegexOptions.IgnoreCase);

                foreach (var word in Regex.Split(lower, @"[^a-z0-9]+"))
                {
                    if (word.Length < 4 || StopWords.Contains(word)) continue;
                    wordCounts[word] = wordCounts.TryGetValue(word, out var count) ? count + 1 : 1;
                }
            }

            result.People = scoped.Select(m => m.Sender).Where(s => !string.IsNullOrWhiteSpace(s) && !s.Equals("you", StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(s => s).ToList();
            result.Topics = wordCounts.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key).Take(6).Select(pair => char.ToUpperInvariant(pair.Key[0]) + pair.Key[1..]).ToList();

            foreach (var value in result.Decisions.Take(2).Concat(result.Tasks.Take(3))) AddUnique(result.Summary, StripReference(value));
            if (result.Summary.Count == 0)
            {
                foreach (var message in scoped.TakeLast(5).Reverse()) AddUnique(result.Summary, Compact(message.Text));
            }

            if (result.Tasks.Count > 0) result.SuggestedQuestions.Add("What tasks are pending for me?");
            if (result.Decisions.Count > 0) result.SuggestedQuestions.Add("What decisions were made?");
            if (result.Dates.Count > 0) result.SuggestedQuestions.Add("What deadlines or dates were mentioned?");
            if (result.UnresolvedQuestions.Count > 0) result.SuggestedQuestions.Add("Summarize unresolved questions.");
            if (result.Links.Count > 0) result.SuggestedQuestions.Add("Show all links shared in this chat.");
            if (result.PhoneNumbers.Count > 0) result.SuggestedQuestions.Add("List all phone numbers shared in this conversation.");
            if (result.People.Count > 1) result.SuggestedQuestions.Add("List all members in this group.");
            if (result.People.FirstOrDefault() is string person) result.SuggestedQuestions.Add($"What is {person} saying in this conversation?");
            result.SuggestedQuestions = result.SuggestedQuestions.Take(6).ToList();
            return result;
        }

        public AIChatMessage Answer(string question, ChatIntelligenceAnalysis analysis, IEnumerable<PlatformMessagePreview> messages, IEnumerable<AIChatMemberItem>? metadataMembers)
        {
            var scoped = messages.TakeLast(MaximumMessages).ToList();
            var lower = question.ToLowerInvariant();
            var response = new AIChatMessage { IsUser = false, RelatedPrompts = analysis.SuggestedQuestions };

            if (ContainsAny(lower, "task", "to-do", "todo", "need to do", "pending for me", "action item"))
            {
                response.Text = FormatList("Pending tasks", analysis.Tasks);
                response.ActionItems = analysis.Tasks.Select(StripReference).ToList();
            }
            else if (lower.Contains("decision")) response.Text = FormatList("Decisions found", analysis.Decisions);
            else if (ContainsAny(lower, "deadline", "date", "when")) response.Text = FormatList("Dates and deadlines mentioned", analysis.Dates);
            else if (ContainsAny(lower, "unresolved", "open question", "questions pending")) response.Text = FormatList("Unresolved questions", analysis.UnresolvedQuestions);
            else if (ContainsAny(lower, "link", "url")) response.Text = FormatList("Links shared", analysis.Links);
            else if (ContainsAny(lower, "file", "document", "attachment")) response.Text = FormatList("Files mentioned", analysis.Files);
            else if (ContainsAny(lower, "phone", "mobile", "contact number"))
            {
                response.Text = FormatList("Phone numbers shared in this conversation", analysis.PhoneNumbers);
                response.PhoneNumbers = analysis.PhoneNumbers.Select(number => new AIChatPhoneNumberItem
                {
                    Name = scoped.FirstOrDefault(m => m.Text.Contains(number, StringComparison.Ordinal))?.Sender ?? "Shared contact",
                    Number = number,
                    Context = "Found in selected conversation"
                }).ToList();
            }
            else if (ContainsAny(lower, "member", "participant", "who is in", "people in this group"))
            {
                response.Members = GroundedMembers(scoped, metadataMembers);
                response.Text = response.Members.Count == 0
                    ? Unavailable
                    : "Group Members\n\n" + string.Join("\n", response.Members.Select(m => $"• {m.Name} — {(string.IsNullOrWhiteSpace(m.PhoneNumber) ? "Phone number unavailable" : m.PhoneNumber)}"));
            }
            else if (analysis.People.FirstOrDefault(person => lower.Contains(person.ToLowerInvariant())) is string speaker)
            {
                response.Text = FormatMessages($"What {speaker} said", scoped.Where(m => m.Sender.Equals(speaker, StringComparison.OrdinalIgnoreCase)).ToList());
            }
            else
            {
                var tokens = Regex.Split(lower, @"[^a-z0-9]+").Where(t => t.Length >= 3 && !StopWords.Contains(t)).ToList();
                var matches = scoped.Where(m => tokens.Any(token => m.Text.Contains(token, StringComparison.OrdinalIgnoreCase) || m.Sender.Contains(token, StringComparison.OrdinalIgnoreCase))).ToList();
                response.Text = FormatMessages("Relevant conversation evidence", matches);
            }
            return response;
        }

        public List<AIChatMemberItem> GroundedMembers(IEnumerable<PlatformMessagePreview> messages, IEnumerable<AIChatMemberItem>? metadataMembers)
        {
            var members = new Dictionary<string, AIChatMemberItem>(StringComparer.OrdinalIgnoreCase);
            foreach (var member in metadataMembers ?? Enumerable.Empty<AIChatMemberItem>()) if (!string.IsNullOrWhiteSpace(member.Name)) members[member.Name] = member;
            foreach (var group in messages.Where(m => !string.IsNullOrWhiteSpace(m.Sender) && !m.Sender.Equals("you", StringComparison.OrdinalIgnoreCase)).GroupBy(m => m.Sender, StringComparer.OrdinalIgnoreCase))
            {
                if (!members.ContainsKey(group.Key)) members[group.Key] = new AIChatMemberItem { Name = group.Key, Role = "Conversation participant", Activity = "Visible in selected chat", MessageCount = group.Count() };
            }
            return members.Values.OrderBy(m => m.Name).ToList();
        }

        private const string Unavailable = "I couldn’t find that information in this conversation.";
        private static bool ContainsAny(string text, params string[] terms) => terms.Any(text.Contains);
        private static string Compact(string text, int limit = 150) { var clean = Regex.Replace(text, @"\s+", " ").Trim(); return clean.Length > limit ? clean[..limit] + "…" : clean; }
        private static string StripReference(string value) => value.Split(" — ")[0];
        private static void AddUnique(List<string> values, string value) { if (!string.IsNullOrWhiteSpace(value) && !values.Contains(value, StringComparer.OrdinalIgnoreCase)) values.Add(value); }
        private static string SourceLabel(PlatformMessagePreview message, List<PlatformMessagePreview> messages) => !string.IsNullOrWhiteSpace(message.Time) ? $"{message.Sender} · {message.Time}" : $"{message.Sender} · Message {Math.Max(1, messages.FindIndex(m => m.Id == message.Id) + 1)}";
        private static string FormatList(string title, List<string> values) => values.Count == 0 ? Unavailable : title + "\n\n" + string.Join("\n", values.Take(20).Select(v => "• " + v));
        private static string FormatMessages(string title, List<PlatformMessagePreview> messages) => messages.Count == 0 ? Unavailable : title + "\n\n" + string.Join("\n", messages.TakeLast(8).Select((m, i) => $"• {Compact(m.Text)}\n  Source: {(!string.IsNullOrWhiteSpace(m.Time) ? $"{m.Sender} · {m.Time}" : $"{m.Sender} · Message {i + 1}")}"));

        private static void AddMatches(List<string> target, string text, string pattern, RegexOptions options, Func<string, bool>? predicate = null, Func<string, string>? transform = null)
        {
            foreach (Match match in Regex.Matches(text, pattern, options))
            {
                var value = transform?.Invoke(match.Value) ?? match.Value;
                if (predicate == null || predicate(value)) AddUnique(target, value);
            }
        }
    }
}
