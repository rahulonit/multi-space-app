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
        public const int MaximumMessages = 250;
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

            var primarySender = result.People.FirstOrDefault() ?? "this chat";
            result.SuggestedQuestions = GenerateDynamicPrompts(
                scoped,
                primarySender,
                result.Tasks,
                result.Decisions,
                result.Dates,
                result.Links,
                result.Files,
                result.PhoneNumbers,
                result.Topics,
                result.People);
            return result;
        }

        public async Task<AIChatMessage> AnswerAsync(
            string question,
            ChatIntelligenceAnalysis analysis,
            IEnumerable<PlatformMessagePreview> messages,
            IEnumerable<AIChatMemberItem>? metadataMembers,
            AppPreferences? preferences = null,
            string? priorContext = null,
            string? conversationTitle = null,
            int? groupMemberCount = null,
            string? groupSubtitle = null)
        {
            var scoped = messages.Where(m => !string.IsNullOrWhiteSpace(m.Text)).TakeLast(MaximumMessages).ToList();
            var clean = question.Trim();
            if (string.IsNullOrWhiteSpace(clean))
            {
                return new AIChatMessage { IsUser = false, Text = "Please enter a question to analyze." };
            }

            var resolution = preferences != null ? AIProviderResolver.Resolve(preferences) : null;

            // =============================================================
            // PATH A: Connected Generative AI Provider (Deep Grounded Analysis)
            // =============================================================
            if (preferences != null && resolution != null && resolution.CanPerformGenerativeAI)
            {
                var fullTranscript = string.Join("\n", scoped.Select((m, i) => $"[#{i + 1} | {(string.IsNullOrWhiteSpace(m.Sender) ? "Unknown" : m.Sender)} [{(m.Time ?? "")}]]: {m.Text}"));
                var availableMembers = GroundedMembers(scoped, metadataMembers);
                var uniqueSenders = scoped.Select(m => m.Sender).Where(s => !string.IsNullOrWhiteSpace(s) && !s.Equals("you", StringComparison.OrdinalIgnoreCase)).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(s => s).ToList();
                var title = !string.IsNullOrWhiteSpace(conversationTitle) ? conversationTitle : (analysis.People.FirstOrDefault() ?? "Current Thread");

                var isExplicitGroup = (groupMemberCount ?? 0) > 2 || !string.IsNullOrWhiteSpace(groupSubtitle) || availableMembers.Count > 1 || uniqueSenders.Count > 1;
                var totalCount = groupMemberCount ?? Math.Max(availableMembers.Count, Math.Max(1, uniqueSenders.Count));
                var channelType = isExplicitGroup ? $"Group Chat ({totalCount} members)" : "Direct 1-on-1 / Service Notification Channel";

                var membersList = availableMembers.Count == 0
                    ? (uniqueSenders.Count == 0 ? title : string.Join(", ", uniqueSenders))
                    : string.Join("; ", availableMembers.Select(m => $"{m.Name} ({(string.IsNullOrEmpty(m.PhoneNumber) ? "No phone" : m.PhoneNumber)}) - {m.Role}"));

                var userPrompt = $@"=== CONVERSATION SCOPE & COMPOSITION ===
• Thread Title: {title}
• Channel Type: {channelType}
• Total Messages Indexed: {scoped.Count}
• Member Count: {(isExplicitGroup ? $"{totalCount} members" : "1 participant (Direct 1-on-1 Channel)")}
• Group Subtitle / Description: {groupSubtitle ?? "None"}
• Identified Participants: {membersList}
• Active Message Senders: {(uniqueSenders.Count == 0 ? title : string.Join(", ", uniqueSenders))}

=== CONVERSATION METADATA ===
Detected Decisions: {(analysis.Decisions.Count == 0 ? "None" : string.Join(" | ", analysis.Decisions))}
Detected Action Items: {(analysis.Tasks.Count == 0 ? "None" : string.Join(" | ", analysis.Tasks))}
Mentioned Dates/Deadlines: {(analysis.Dates.Count == 0 ? "None" : string.Join(" | ", analysis.Dates))}
Referenced Files: {(analysis.Files.Count == 0 ? "None" : string.Join(", ", analysis.Files))}
Shared Links: {(analysis.Links.Count == 0 ? "None" : string.Join(", ", analysis.Links))}
Shared Contact Numbers: {(analysis.PhoneNumbers.Count == 0 ? "None" : string.Join(", ", analysis.PhoneNumbers))}

=== FULL CONVERSATION TRANSCRIPT ({scoped.Count} messages) ===
{fullTranscript}

=== PREVIOUS PINGGO AI CONTEXT ===
{(!string.IsNullOrWhiteSpace(priorContext) ? priorContext : "No prior AI turns.")}

=== USER QUESTION ===
{clean}";

                try
                {
                    var answer = await AIService.Shared.AskCoPilotAsync(userPrompt, context: null, tone: "Professional");
                    if (!string.IsNullOrWhiteSpace(answer))
                    {
                        var lower = clean.ToLowerInvariant();
                        return new AIChatMessage
                        {
                            IsUser = false,
                            Text = answer,
                            ActionItems = ContainsAny(lower, "task", "todo", "to-do", "action item") ? analysis.Tasks.Select(StripReference).ToList() : new(),
                            PhoneNumbers = ContainsAny(lower, "phone", "mobile", "contact") ? analysis.PhoneNumbers.Select(num =>
                            {
                                var owner = scoped.FirstOrDefault(m => m.Text.Contains(num))?.Sender ?? "Shared contact";
                                return new AIChatPhoneNumberItem { Name = owner, Number = num, Context = "Found in selected conversation" };
                            }).ToList() : null,
                            RelatedPrompts = analysis.SuggestedQuestions,
                            Source = new AIResponseSource
                            {
                                SourceType = AIResponseSourceType.ProviderGenerated,
                                Provider = resolution.Provider.ToString(),
                                Model = resolution.Model
                            }
                        };
                    }
                }
                catch (Exception ex)
                {
                    var localFallback = PerformDeterministicExtraction(clean, analysis, scoped, metadataMembers, title, groupMemberCount, groupSubtitle);
                    var fallbackText = localFallback != null ? localFallback.Text : SearchEvidenceFallback(clean, scoped);

                    return new AIChatMessage
                    {
                        IsUser = false,
                        Text = $"⚠️ **{resolution.DisplayBadge} could not complete the request** ({ex.Message}).\n*Falling back to local extraction:*\n\n{fallbackText}",
                        ActionItems = localFallback?.ActionItems ?? new(),
                        PhoneNumbers = localFallback?.PhoneNumbers,
                        Members = localFallback?.Members,
                        RelatedPrompts = new List<string> { "Retry Question", "Check Settings > AI" }.Concat(analysis.SuggestedQuestions.Take(2)).ToList(),
                        Source = new AIResponseSource { SourceType = AIResponseSourceType.LocalHeuristic }
                    };
                }
            }

            // =============================================================
            // PATH B: Offline / Unconfigured AI Provider (Local Heuristics)
            // =============================================================
            var deterministicResult = PerformDeterministicExtraction(clean, analysis, scoped, metadataMembers, conversationTitle, groupMemberCount, groupSubtitle);
            if (deterministicResult != null)
            {
                return deterministicResult;
            }

            return new AIChatMessage
            {
                IsUser = false,
                Text = $"💡 **AI provider is not connected for generative reasoning.**\n\nTo ask deep, freeform questions across this conversation (e.g. *“{clean}”*), connect **Google Gemini**, **OpenAI ChatGPT**, or **Ollama** in **Settings > AI**.\n\nLocal extraction is currently active for: *tasks*, *decisions*, *deadlines*, *members*, *phone numbers*, *files*, and *links*.",
                RelatedPrompts = analysis.SuggestedQuestions,
                Source = new AIResponseSource { SourceType = AIResponseSourceType.LocalHeuristic }
            };
        }

        private AIChatMessage? PerformDeterministicExtraction(
            string question,
            ChatIntelligenceAnalysis analysis,
            IList<PlatformMessagePreview> scoped,
            IEnumerable<AIChatMemberItem>? metadataMembers,
            string? conversationTitle = null,
            int? groupMemberCount = null,
            string? groupSubtitle = null)
        {
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
            if (ContainsAny(lower, "member", "participant", "who is in", "who are in", "people in this group", "list all member", "how many member"))
            {
                var available = GroundedMembers(scoped, metadataMembers);
                if (available.Count == 0)
                {
                    response.Text = "I couldn't find member details for this conversation.";
                    return response;
                }
                response.Members = available;
                var title = !string.IsNullOrWhiteSpace(conversationTitle) ? conversationTitle : (analysis.People.FirstOrDefault() ?? "Current Thread");
                if (available.Count == 1)
                {
                    var single = available[0];
                    response.Text = $"💬 **Direct 1-on-1 Channel ({title})**\n\nThis conversation is a direct 1-on-1 thread with **{single.Name}** (not a multi-member group).\n\n• **Participant**: **{single.Name}** — {single.Role}";
                }
                else
                {
                    var countStr = groupMemberCount.HasValue ? groupMemberCount.Value.ToString() : available.Count.ToString();
                    response.Text = $"👥 **Group Members — {title} ({countStr})**\n\n" + string.Join("\n", available.Select(m =>
                        $"• **{m.Name}** — {(string.IsNullOrEmpty(m.PhoneNumber) ? "Phone unavailable" : m.PhoneNumber)} ({m.Role})"));
                }
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

            // 11. Keyword Evidence Search Fallback
            var tokens = SearchTokens(clean);
            var evidence = scoped.Where(m => tokens.Count > 0 && tokens.Any(t => m.Text.Contains(t, StringComparison.OrdinalIgnoreCase) || m.Sender.Contains(t, StringComparison.OrdinalIgnoreCase))).ToList();
            if (evidence.Count > 0)
            {
                response.Text = FormatMessages("Relevant conversation evidence", evidence);
                response.Source = new AIResponseSource { SourceType = AIResponseSourceType.LocalHeuristic };
                return response;
            }

            return null;
        }

        private static string SearchEvidenceFallback(string question, IList<PlatformMessagePreview> scoped)
        {
            var tokens = SearchTokens(question);
            var evidence = scoped.Where(m => tokens.Count > 0 && tokens.Any(t => m.Text.Contains(t, StringComparison.OrdinalIgnoreCase) || m.Sender.Contains(t, StringComparison.OrdinalIgnoreCase))).ToList();
            return evidence.Count == 0 ? "I couldn’t find that information in this conversation." : FormatMessages("Relevant conversation evidence", evidence);
        }

        public AIChatMessage Answer(
            string question,
            ChatIntelligenceAnalysis analysis,
            IEnumerable<PlatformMessagePreview> messages,
            IEnumerable<AIChatMemberItem>? metadataMembers,
            AppPreferences? preferences = null,
            string? priorContext = null,
            string? conversationTitle = null,
            int? groupMemberCount = null,
            string? groupSubtitle = null)
        {
            return AnswerAsync(question, analysis, messages, metadataMembers, preferences, priorContext, conversationTitle, groupMemberCount, groupSubtitle).GetAwaiter().GetResult();
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

        public List<string> GenerateDynamicPrompts(
            IList<PlatformMessagePreview> messages,
            string conversationTitle,
            IList<string>? tasks = null,
            IList<string>? decisions = null,
            IList<string>? dates = null,
            IList<string>? links = null,
            IList<string>? files = null,
            IList<string>? phones = null,
            IList<string>? topics = null,
            IList<string>? people = null)
        {
            var title = (conversationTitle ?? "").Trim();
            var displayTitle = string.IsNullOrWhiteSpace(title) ? "this sender" : title;
            var prompts = new List<string>();

            var combinedText = string.Join("\n", messages.Select(m => m.Text)).ToLowerInvariant();

            // 1. Verification codes / OTP / Security PIN
            if (combinedText.Contains("otp") || combinedText.Contains("verification code") || combinedText.Contains("security code") || combinedText.Contains("one time password") || combinedText.Contains("login code") || combinedText.Contains("pin ") || combinedText.Contains(" pin"))
            {
                prompts.Add("What is the verification code / OTP?");
                prompts.Add("When does this code or link expire?");
            }

            // 2. Financial / Payments / Invoices / Billing
            if (combinedText.Contains("$") || combinedText.Contains("₹") || combinedText.Contains("rs.") || combinedText.Contains("inr") || combinedText.Contains("usd") || combinedText.Contains("eur") || combinedText.Contains("payment") || combinedText.Contains("invoice") || combinedText.Contains("paid") || combinedText.Contains("bill") || combinedText.Contains("refund") || combinedText.Contains("due date"))
            {
                prompts.Add("What is the payment amount or bill status?");
                prompts.Add("What payment instructions were given?");
            }

            // 3. Deadlines & Dates
            if (dates != null && dates.Count > 0)
            {
                prompts.Add($"What is scheduled for {dates[0]}?");
            }

            // 4. Questions from sender
            var questionsFromSender = messages.Where(m => !m.Sender.Equals("you", StringComparison.OrdinalIgnoreCase) && m.Text.Contains('?')).ToList();
            if (questionsFromSender.Count > 0)
            {
                prompts.Add($"What did {displayTitle} ask?");
                prompts.Add($"Draft a reply to {displayTitle}");
            }

            // 5. Action items & Tasks
            if (tasks != null && tasks.Count > 0)
            {
                prompts.Add("What action items are required from me?");
            }

            // 6. Tender / Notice keywords
            if (combinedText.Contains("tender") || combinedText.Contains("bid") || combinedText.Contains("eproc") || combinedText.Contains("notice") || combinedText.Contains("cpwd"))
            {
                prompts.Add("What are the tender / notice requirements?");
            }

            // 7. Delivery / Orders / Tracking
            if (combinedText.Contains("order") || combinedText.Contains("tracking") || combinedText.Contains("deliver") || combinedText.Contains("shipment") || combinedText.Contains("courier"))
            {
                prompts.Add("What is the order or delivery status?");
                prompts.Add("What is the tracking number?");
            }

            // 8. Shared Links
            if (links != null && links.Count > 0)
            {
                prompts.Add("Show all links shared in this chat");
            }

            // 9. Shared Files
            if (files != null && files.Count > 0)
            {
                prompts.Add("List files or attachments referenced");
            }

            // 10. Decisions
            if (decisions != null && decisions.Count > 0)
            {
                prompts.Add("What was decided in this conversation?");
            }

            // 11. Phone numbers
            if (phones != null && phones.Count > 0)
            {
                prompts.Add("List phone numbers shared here");
            }

            // 12. Topics
            if (topics != null)
            {
                foreach (var topic in topics.Take(2))
                {
                    var q = $"What was discussed regarding {topic}?";
                    if (!prompts.Contains(q)) prompts.Add(q);
                }
            }

            // 13. Sender fallbacks
            if (prompts.Count == 0)
            {
                if (messages.Count <= 1)
                {
                    prompts.Add($"Summarize this message from {displayTitle}");
                    prompts.Add($"What action does {displayTitle} expect?");
                }
                else
                {
                    prompts.Add($"Summarize recent messages from {displayTitle}");
                    prompts.Add("What are the key points in this chat?");
                }
            }
            else if (prompts.Count < 3)
            {
                prompts.Add($"Summarize recent messages from {displayTitle}");
            }

            var unique = new List<string>();
            foreach (var p in prompts)
            {
                if (!unique.Contains(p, StringComparer.OrdinalIgnoreCase))
                {
                    unique.Add(p);
                }
            }
            return unique.Take(6).ToList();
        }

        public async Task<List<string>> GenerateContextualPromptsAsync(
            IList<PlatformMessagePreview> messages,
            string conversationTitle,
            AppPreferences? preferences = null)
        {
            var scoped = messages.Where(m => !string.IsNullOrWhiteSpace(m.Text)).TakeLast(25).ToList();
            if (scoped.Count == 0)
            {
                return GenerateDynamicPrompts(scoped, conversationTitle);
            }

            var prefs = preferences ?? AppPreferences.Shared;
            var resolution = AIProviderResolver.Resolve(prefs);
            if (!resolution.CanPerformGenerativeAI)
            {
                return GenerateDynamicPrompts(scoped, conversationTitle);
            }

            var transcript = string.Join("\n", scoped.Select(m => $"{(string.IsNullOrWhiteSpace(m.Sender) ? "Unknown" : m.Sender)}{(string.IsNullOrWhiteSpace(m.Time) ? "" : $" [{m.Time}]")}: {m.Text}"));
            var prompt = $@"You are Pinggo AI's conversation suggestion assistant.
Analyze the provided chat transcript and generate 3 to 5 concise, highly relevant suggested questions that the user might want to ask about this specific chat.

RULES:
1. Every question MUST directly relate to the specific content, entities, requests, codes, or actions in this conversation.
2. NEVER suggest generic template questions like 'What is the project status?', 'What do I need to do today?', 'What decisions were made?', or 'What changed since yesterday?' unless they are explicitly discussed in the chat.
3. If the chat is a single alert, notification, or OTP, ask specifically about that notification or code.
4. Keep each question brief (under 50 characters).
5. Format: Output ONLY the questions, each on a new line starting with a dash (- ). No introductory text, no conversational commentary.

Conversation with: {conversationTitle}
Transcript ({scoped.Count} messages):
{transcript}

Suggested questions:";

            try
            {
                var rawText = await AIService.Shared.AskCoPilotAsync(prompt, context: null, tone: "Direct");
                if (!string.IsNullOrWhiteSpace(rawText))
                {
                    var lines = rawText.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                        .Select(line =>
                        {
                            var trimmed = line.Trim();
                            if (trimmed.StartsWith("-") || trimmed.StartsWith("•") || trimmed.StartsWith("*"))
                                trimmed = trimmed[1..].Trim();
                            var dotIdx = trimmed.IndexOf('.');
                            if (dotIdx > 0 && dotIdx < 4 && int.TryParse(trimmed[..dotIdx], out _))
                                trimmed = trimmed[(dotIdx + 1)..].Trim();
                            return trimmed;
                        })
                        .Where(line => line.Length > 5 && line.Length < 90 && !line.StartsWith("here are", StringComparison.OrdinalIgnoreCase) && !line.StartsWith("suggested", StringComparison.OrdinalIgnoreCase))
                        .ToList();

                    if (lines.Count >= 2)
                    {
                        return lines.Take(6).ToList();
                    }
                }
            }
            catch
            {
                // Fall through to dynamic heuristics
            }

            return GenerateDynamicPrompts(scoped, conversationTitle);
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
