using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
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

            var otherSenders = scoped.Select(m => m.Sender).Where(s => !string.IsNullOrWhiteSpace(s) && !s.Equals("you", StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
            var primaryRecipient = otherSenders.FirstOrDefault() ?? "team member";

            var wordCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var message in scoped)
            {
                var text = message.Text.Trim();
                var lower = text.ToLowerInvariant();
                var referenced = $"{Compact(text)} — {SourceLabel(message, scoped)}";

                if (ContainsAny(lower, "decided", "agreed", "approved", "confirmed", "we'll proceed", "will proceed", "final decision"))
                    AddUnique(result.Decisions, referenced);

                if (ContainsAny(lower, "need to", "needs to", "please ", "todo", "to-do", "action item", "must ", "should ", "will send", "will update", "follow up", "deadline"))
                {
                    string resolvedTaskText;
                    if (message.Sender.Equals("you", StringComparison.OrdinalIgnoreCase))
                    {
                        if (lower.Contains("will send") || lower.Contains("will update"))
                            resolvedTaskText = $"Send update to {primaryRecipient} — {SourceLabel(message, scoped)}";
                        else if (lower.Contains("let me know") || lower.Contains("when can you"))
                            resolvedTaskText = $"Wait for {primaryRecipient} to confirm — {SourceLabel(message, scoped)}";
                        else
                            resolvedTaskText = $"Follow up with {primaryRecipient} — {SourceLabel(message, scoped)}";
                    }
                    else
                    {
                        resolvedTaskText = $"{message.Sender}: {Compact(text)} — {SourceLabel(message, scoped)}";
                    }
                    AddUnique(result.Tasks, resolvedTaskText);
                }

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

        public async Task<AIChatMessage> AnswerAsync(
            string question,
            ChatIntelligenceAnalysis analysis,
            IEnumerable<PlatformMessagePreview> messages,
            IEnumerable<AIChatMemberItem>? metadataMembers,
            AppPreferences? preferences = null)
        {
            var scoped = messages.TakeLast(MaximumMessages).ToList();
            var clean = question.Trim();
            var lower = clean.ToLowerInvariant();
            var response = new AIChatMessage
            {
                IsUser = false,
                RelatedPrompts = analysis.SuggestedQuestions,
                Source = new AIResponseSource { SourceType = AIResponseSourceType.StructuredExtraction }
            };

            // 1. Tasks
            if (ContainsAny(lower, "task", "to-do", "todo", "need to do", "pending for me", "action item"))
            {
                response.Text = FormatList("📋 Pending Tasks & Action Items", analysis.Tasks);
                response.ActionItems = analysis.Tasks.Select(StripReference).ToList();
                return response;
            }

            // 2. Decisions
            if (lower.Contains("decision"))
            {
                response.Text = FormatList("⚖️ Decisions Confirmed in This Chat", analysis.Decisions);
                return response;
            }

            // 3. Dates & Deadlines
            if (ContainsAny(lower, "deadline", "date", "when", "schedule"))
            {
                response.Text = FormatList("📅 Dates & Deadlines Mentioned", analysis.Dates);
                return response;
            }

            // 4. Questions
            if (ContainsAny(lower, "unresolved", "open question", "questions pending"))
            {
                response.Text = FormatList("❓ Unresolved Questions", analysis.UnresolvedQuestions);
                return response;
            }

            // 5. Links
            if (ContainsAny(lower, "link", "url", "website"))
            {
                response.Text = FormatList("🔗 Links Shared in This Conversation", analysis.Links);
                return response;
            }

            // 6. Files
            if (ContainsAny(lower, "file", "document", "attachment"))
            {
                response.Text = FormatList("📁 Files & Attachments Referenced", analysis.Files);
                return response;
            }

            // 7. Phone Numbers
            if (ContainsAny(lower, "phone", "mobile", "contact number", "call number"))
            {
                response.Text = FormatList("📞 Phone Numbers Shared", analysis.PhoneNumbers);
                response.PhoneNumbers = analysis.PhoneNumbers.Select(number =>
                {
                    var owner = scoped.FirstOrDefault(m => m.Text.Contains(number))?.Sender ?? "Shared contact";
                    return new AIChatPhoneNumberItem { Name = owner, Number = number, Context = "Found in selected conversation" };
                }).ToList();
                return response;
            }

            // 8. Members
            if (ContainsAny(lower, "member", "participant", "who is in", "people in this group", "list all member"))
            {
                var available = GroundedMembers(scoped, metadataMembers);
                if (available.Count == 0)
                {
                    response.Text = "I couldn't find member details for this conversation.";
                    return response;
                }
                response.Members = available;
                response.Text = $"👥 **Group Members ({available.Count})**\n\n" + string.Join("\n", available.Select(m =>
                    $"• **{m.Name}** — {(string.IsNullOrEmpty(m.PhoneNumber) ? "Phone unavailable" : m.PhoneNumber)} ({m.Role})"));
                return response;
            }

            // 9. Zero-Hallucination CPWD
            if (lower.Contains("cpwd"))
            {
                var cpwdMatches = scoped.Where(m => m.Text.Contains("cpwd", StringComparison.OrdinalIgnoreCase)).ToList();
                if (cpwdMatches.Count == 0)
                {
                    response.Text = "🏢 I searched this conversation, but **could not find any CPWD-related information or guidelines** in the available chat history.";
                }
                else
                {
                    response.Text = FormatMessages("🏢 CPWD References in This Chat", cpwdMatches);
                }
                return response;
            }

            // 10. Dynamic Speaker Query
            var allCandidateNames = scoped.Select(m => m.Sender).Concat(metadataMembers?.Select(m => m.Name) ?? Enumerable.Empty<string>())
                .Concat(analysis.People).Where(s => !string.IsNullOrWhiteSpace(s) && !s.Equals("you", StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();

            var targetSpeaker = allCandidateNames.FirstOrDefault(name => lower.Contains(name.ToLowerInvariant()));
            if (!string.IsNullOrEmpty(targetSpeaker))
            {
                var matches = scoped.Where(m => m.Sender.Equals(targetSpeaker, StringComparison.OrdinalIgnoreCase)).ToList();
                response.Text = matches.Count == 0
                    ? $"I couldn't find messages from **{targetSpeaker}** in this conversation."
                    : FormatMessages($"💬 What {targetSpeaker} said in this conversation", matches);
                return response;
            }

            // STEP 2: Freeform / Semantic AI Reasoning
            if (preferences != null)
            {
                var resolution = AIProviderResolver.Resolve(preferences);
                if (resolution.CanPerformGenerativeAI)
                {
                    var recentMessages = string.Join("\n", scoped.TakeLast(25).Select((m, i) => $"({i + 1}) {m.Sender} [{(m.Time ?? "")}]: {m.Text}"));
                    var userPrompt = $"Conversation Summary:\n{string.Join("\n", analysis.Summary.Select(s => "• " + s))}\n\nParticipants: {string.Join(", ", analysis.People)}\n\nRecent Transcript:\n{recentMessages}\n\nQuestion: {clean}";

                    try
                    {
                        var answer = await AIService.Shared.GenerateResponseAsync(userPrompt);
                        response.Text = answer;
                        response.Source = new AIResponseSource
                        {
                            SourceType = AIResponseSourceType.ProviderGenerated,
                            Provider = resolution.Provider.ToString(),
                            Model = resolution.Model
                        };
                        return response;
                    }
                    catch (Exception ex)
                    {
                        response.Text = $"⚠️ **{resolution.DisplayBadge} could not complete the request**:\n{ex.Message}";
                        response.Source = new AIResponseSource { SourceType = AIResponseSourceType.LocalHeuristic };
                        return response;
                    }
                }
                else
                {
                    response.Text = $"💡 **AI provider is not configured for generative reasoning.**\n\nTo ask freeform questions like *“{clean}”*, please configure **Google Gemini**, **OpenAI ChatGPT**, or **Ollama** in **Settings > AI**.";
                    response.Source = new AIResponseSource { SourceType = AIResponseSourceType.LocalHeuristic };
                    return response;
                }
            }

            // Fallback: keyword search
            var tokens = SearchTokens(question);
            var evidence = scoped.Where(m => tokens.Count > 0 && tokens.Any(t => m.Text.Contains(t, StringComparison.OrdinalIgnoreCase) || m.Sender.Contains(t, StringComparison.OrdinalIgnoreCase))).ToList();
            response.Text = evidence.Count == 0 ? "I couldn’t find that information in this conversation." : FormatMessages("Relevant conversation evidence", evidence);
            response.Source = new AIResponseSource { SourceType = AIResponseSourceType.LocalHeuristic };
            return response;
        }

        public AIChatMessage Answer(string question, ChatIntelligenceAnalysis analysis, IEnumerable<PlatformMessagePreview> messages, IEnumerable<AIChatMemberItem>? metadataMembers)
        {
            return AnswerAsync(question, analysis, messages, metadataMembers).GetAwaiter().GetResult();
        }

        public List<AIChatMemberItem> GroundedMembers(IEnumerable<PlatformMessagePreview> messages, IEnumerable<AIChatMemberItem>? metadataMembers)
        {
            var result = new Dictionary<string, AIChatMemberItem>(StringComparer.OrdinalIgnoreCase);
            foreach (var member in metadataMembers ?? Enumerable.Empty<AIChatMemberItem>())
            {
                if (!string.IsNullOrWhiteSpace(member.Name)) result[member.Name] = member;
            }
            foreach (var sender in messages.Select(m => m.Sender).Where(s => !string.IsNullOrWhiteSpace(s) && !s.Equals("you", StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                if (!result.ContainsKey(sender))
                {
                    var count = messages.Count(m => m.Sender.Equals(sender, StringComparison.OrdinalIgnoreCase));
                    result[sender] = new AIChatMemberItem { Name = sender, Role = "Conversation participant", Activity = "Visible in selected chat", MessageCount = count };
                }
            }
            return result.Values.OrderBy(m => m.Name, StringComparer.OrdinalIgnoreCase).ToList();
        }

        private static string FormatList(string title, IEnumerable<string> values)
        {
            var list = values.Take(20).ToList();
            return list.Count == 0 ? "I couldn’t find that information in this conversation." : $"{title}\n\n" + string.Join("\n", list.Select(v => $"• {v}"));
        }

        private static string FormatMessages(string title, IEnumerable<PlatformMessagePreview> messages)
        {
            var list = messages.TakeLast(8).ToList();
            if (list.Count == 0) return "I couldn’t find that information in this conversation.";
            return $"{title}\n\n" + string.Join("\n", list.Select(m => $"• {Compact(m.Text)}\n  Source: {SourceLabel(m, list)}"));
        }

        private static string SourceLabel(PlatformMessagePreview message, IList<PlatformMessagePreview> messages)
        {
            if (!string.IsNullOrWhiteSpace(message.Time)) return $"{message.Sender} · {message.Time}";
            var idx = messages.IndexOf(message);
            return $"{message.Sender} · Message {(idx >= 0 ? idx + 1 : 1)}";
        }

        private static string Compact(string text, int limit = 150)
        {
            var clean = Regex.Replace(text.Trim(), @"\s+", " ");
            return clean.Length > limit ? clean[..limit] + "…" : clean;
        }

        private static string StripReference(string value) => value.Split(" — ")[0];

        private static bool ContainsAny(string text, params string[] terms) => terms.Any(text.Contains);

        private static void AddUnique(List<string> values, string value)
        {
            if (!string.IsNullOrWhiteSpace(value) && !values.Any(v => v.Equals(value, StringComparison.OrdinalIgnoreCase)))
            {
                values.Add(value);
            }
        }

        private static void AddMatches(List<string> values, string text, string pattern, RegexOptions options, Func<string, bool>? predicate = null, Func<string, string>? transform = null)
        {
            foreach (Match match in Regex.Matches(text, pattern, options))
            {
                var val = match.Value;
                if (predicate != null && !predicate(val)) continue;
                if (transform != null) val = transform(val);
                AddUnique(values, val);
            }
        }

        private static List<string> SearchTokens(string query) =>
            Regex.Split(query.ToLowerInvariant(), @"[^a-z0-9]+")
                .Where(t => t.Length >= 3 && !StopWords.Contains(t)).ToList();
    }
}
