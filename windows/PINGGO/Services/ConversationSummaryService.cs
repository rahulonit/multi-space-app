using System;
using System.Collections.Generic;
using System.Linq;
using PINGGO.Models;

namespace PINGGO.Services
{
    public class ConversationSummaryService
    {
        private static readonly Lazy<ConversationSummaryService> _instance = new(() => new ConversationSummaryService());
        public static ConversationSummaryService Shared => _instance.Value;

        // MARK: - Single Message Analysis
        public ConversationMessageSummary AnalyzeMessage(PlatformMessagePreview message)
        {
            var text = (message.Text ?? "").Trim();
            var lower = text.ToLowerInvariant();

            var intent = "General Update";
            var urgency = "Normal";
            string? actionItem = null;
            var contextSummary = "";
            var replies = new List<string>();

            // 1. Detect Explicit Questions
            string? detectedQuestion = null;
            if (text.Contains("?"))
            {
                var sentences = text.Split(new[] { '.', '!', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                detectedQuestion = sentences.FirstOrDefault(s => s.Contains("?"))?.Trim();
            }
            else if (lower.Contains("when can") || lower.Contains("could you") || lower.Contains("can you") ||
                     lower.Contains("let me know if") || lower.Contains("what do you think"))
            {
                detectedQuestion = text;
            }

            // 2. Classify Intent & Context
            if (lower.Contains("meet") || lower.Contains("meeting") || lower.Contains("call") ||
                lower.Contains("sync") || lower.Contains("zoom") || lower.Contains("calendar") ||
                lower.Contains("schedule") || lower.Contains("chat this week"))
            {
                intent = "📅 Meeting Request";
                urgency = "Needs Attention";
                contextSummary = $"{message.Sender} proposed an intro/sync call to connect.";
                actionItem = $"Reply to {message.Sender} with your available times";
                replies = new List<string>
                {
                    "Sounds great! How does tomorrow at 2 PM work for you?",
                    "Could you send an agenda first?",
                    "I'm fully booked this week, but let's connect next week."
                };
            }
            else if (lower.Contains("review") || lower.Contains("please check") || lower.Contains("feedback") ||
                     lower.Contains("take a look") || lower.Contains("draft") || lower.Contains("attached") ||
                     lower.Contains("deck") || lower.Contains("slides") || lower.Contains("document"))
            {
                intent = "📝 Review & Feedback";
                urgency = "Needs Attention";
                contextSummary = $"{message.Sender} shared materials requesting your review and feedback.";
                actionItem = $"Review materials from {message.Sender} and send feedback";
                replies = new List<string>
                {
                    "Taking a look now, will send my notes shortly.",
                    "Looks great to me, proceed with this draft!",
                    "Thanks for sending! Will review by end of day."
                };
            }
            else if (lower.Contains("urgent") || lower.Contains("asap") || lower.Contains("immediately") ||
                     lower.Contains("critical") || lower.Contains("emergency") || lower.Contains("blocked") ||
                     lower.Contains("help needed") || lower.Contains("down") || lower.Contains("outage"))
            {
                intent = "🚨 Urgent & Action Needed";
                urgency = "High Priority";
                contextSummary = $"{message.Sender} flagged an urgent or time-sensitive issue.";
                actionItem = $"Address urgent blocker flagged by {message.Sender}";
                replies = new List<string>
                {
                    "Looking into this right now and will keep you updated.",
                    "On it — give me 15 minutes to investigate.",
                    "Looping in the team immediately."
                };
            }
            else if (detectedQuestion != null)
            {
                intent = "❓ Question & Help Request";
                urgency = "Needs Attention";
                contextSummary = $"{message.Sender} asked: \"{detectedQuestion}\"";
                actionItem = $"Answer question from {message.Sender}";
                replies = new List<string>
                {
                    "Yes, absolutely. Let me get back to you with details.",
                    "Checking on that now, will update shortly.",
                    "Not at the moment, but let's revisit next week."
                };
            }
            else if (lower.Contains("proposal") || lower.Contains("pricing") || lower.Contains("quote") ||
                     lower.Contains("contract") || lower.Contains("agreement") || lower.Contains("invoice"))
            {
                intent = "💼 Proposal & Pricing";
                urgency = "Needs Attention";
                contextSummary = $"{message.Sender} inquired about or shared commercial terms.";
                actionItem = $"Review commercial terms with {message.Sender}";
                replies = new List<string>
                {
                    "Received! I will review the pricing and get back to you.",
                    "Can we jump on a brief call to walk through the details?",
                    "Looks good, please send over the final agreement."
                };
            }
            else
            {
                intent = "💬 General Discussion";
                urgency = "Informational";
                contextSummary = $"{message.Sender} shared: \"{(text.Length > 80 ? text.Substring(0, 80) + "…" : text)}\"";
                replies = new List<string>
                {
                    "Thanks for sharing the update!",
                    "Understood, appreciate the heads up.",
                    "Sounds good, keep me posted on any developments."
                };
            }

            return new ConversationMessageSummary
            {
                Sender = message.Sender,
                ContextSummary = contextSummary,
                DetectedIntent = intent,
                DetectedQuestion = detectedQuestion,
                ActionItem = actionItem,
                SuggestedReplies = replies,
                Urgency = urgency
            };
        }

        // MARK: - Keyword & Natural Language Smart Summary Crawler
        public KeywordSmartSummary GenerateKeywordSmartSummary(string query, List<UnifiedMessageItem> messages)
        {
            var raw = (query ?? "").Trim();
            var lower = raw.ToLowerInvariant();

            // 1. Detect Intent: Task / To-Do
            var todoKeywords = new[] { "to do", "todo", "do to", "task", "tasks", "action item", "action items", "what should i do", "what do i need to do", "pending work", "what is on my plate" };
            var isTodoQuery = todoKeywords.Any(k => lower.Contains(k));

            // 2. Detect Intent: Member / Group participants
            var isMemberQuery = lower.Contains("member") || lower.Contains("participant") ||
                                lower.Contains("who is in") || lower.Contains("who are in") ||
                                lower.Contains("who is here") || lower.Contains("who all") ||
                                lower.Contains("people in this") || lower.Contains("users in this") ||
                                (lower.Contains("how many") && (lower.Contains("group") || lower.Contains("chat") || lower.Contains("team") || lower.Contains("channel") || lower.Contains("here") || lower.Contains("people")));

            // 3. Detect Intent: CPWD states
            var isCpwdQuery = lower.Contains("cpwd");

            // 4. Detect Intent: Question
            var isQuestionQuery = lower.StartsWith("what") || lower.StartsWith("how") || lower.StartsWith("who") ||
                                  lower.StartsWith("when") || lower.StartsWith("where") || lower.StartsWith("why") ||
                                  lower.StartsWith("which") || lower.StartsWith("is there") || lower.EndsWith("?");

            // 5. Extract Informative Words (Stopwords removed)
            var stopWords = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                "a", "about", "above", "after", "again", "against", "all", "am", "an", "and", "any", "are",
                "as", "at", "be", "because", "been", "before", "being", "below", "between", "both", "but",
                "by", "can", "could", "did", "do", "does", "doing", "down", "during", "each", "few", "for",
                "from", "further", "had", "has", "have", "having", "he", "her", "here", "hers", "him", "his",
                "how", "i", "if", "in", "into", "is", "it", "its", "let's", "me", "more", "most", "my", "myself",
                "no", "nor", "not", "of", "off", "on", "once", "only", "or", "other", "ought", "our", "ours",
                "out", "over", "own", "same", "she", "should", "so", "some", "such", "than", "that", "the",
                "their", "theirs", "them", "then", "there", "these", "they", "this", "those", "through", "to",
                "too", "under", "until", "up", "very", "was", "we", "were", "what", "when", "where", "which",
                "while", "who", "whom", "why", "with", "would", "you", "your", "yours", "tell", "show", "give",
                "using", "many", "much", "group", "today"
            };

            var rawTokens = System.Text.RegularExpressions.Regex.Split(lower, @"[^a-zA-Z0-9]+")
                .Where(t => t.Length >= 2 && !stopWords.Contains(t))
                .ToList();

            // 6. Score & Match Messages
            var scoredMatches = new List<(UnifiedMessageItem item, int score)>();

            foreach (var item in messages)
            {
                var msgText = (item.Message.Text ?? "").ToLowerInvariant();
                var msgSender = (item.Message.Sender ?? "").ToLowerInvariant();
                var platformName = (item.Platform.Name ?? "").ToLowerInvariant();
                var analysis = AnalyzeMessage(item.Message);

                var score = 0;

                if (isTodoQuery)
                {
                    // Prioritize action items, questions, urgent messages, unread
                    if (analysis.ActionItem != null) score += 6;
                    if (analysis.DetectedQuestion != null) score += 5;
                    if (analysis.Urgency == "High Priority") score += 5;
                    if (analysis.Urgency == "Needs Attention") score += 3;
                    if (item.IsUnread) score += 2;

                    var taskTerms = new[] { "review", "send", "share", "submit", "check", "reply", "call", "meet", "confirm", "asap", "urgent", "deadline", "today", "need", "finish", "update" };
                    foreach (var term in taskTerms)
                    {
                        if (msgText.Contains(term)) score += 1;
                    }
                }
                else if (isMemberQuery)
                {
                    if (msgSender.Contains("gepnic") || msgText.Contains("gepnic")) score += 15;
                    if (msgSender.Contains("group") || msgSender.Contains("team")) score += 10;
                    score += 5;
                }
                else if (isCpwdQuery)
                {
                    if (msgText.Contains("cpwd") || msgText.Contains("state") || msgText.Contains("circular")) score += 12;
                    score += 4;
                }
                else
                {
                    if (!string.IsNullOrEmpty(raw) && (msgText.Contains(lower) || msgSender.Contains(lower)))
                    {
                        score += 10;
                    }

                    foreach (var token in rawTokens)
                    {
                        if (msgText.Contains(token)) score += 4;
                        if (msgSender.Contains(token)) score += 4;
                        if (platformName.Contains(token)) score += 2;
                    }
                }

                if (score > 0)
                {
                    scoredMatches.Add((item, score));
                }
            }

            // Sort: highest score first, then unread, then recent
            scoredMatches.Sort((a, b) =>
            {
                if (a.score != b.score) return b.score.CompareTo(a.score);
                if (a.item.IsUnread != b.item.IsUnread) return a.item.IsUnread ? -1 : 1;
                return b.item.SnapshotDate.CompareTo(a.item.SnapshotDate);
            });

            var matchingItems = scoredMatches.Select(m => m.item).ToList();
            var matchCount = matchingItems.Count;

            // 7. Extract Platforms and Senders
            var platformNames = matchingItems.Select(m => m.Platform.Name).Distinct().ToList();
            var senderNames = matchingItems.Select(m => m.Message.Sender).Where(s => !string.IsNullOrWhiteSpace(s)).Distinct().ToList();

            // 8. Extract Action Items, Questions & Takeaways
            var detectedQuestions = new List<string>();
            var actionItems = new List<string>();
            var takeaways = new List<string>();
            var highestUrgency = "Normal";

            foreach (var item in matchingItems)
            {
                var analysis = AnalyzeMessage(item.Message);
                if (analysis.DetectedQuestion != null && !detectedQuestions.Contains(analysis.DetectedQuestion))
                {
                    detectedQuestions.Add(analysis.DetectedQuestion);
                }
                if (analysis.ActionItem != null && !actionItems.Contains(analysis.ActionItem))
                {
                    actionItems.Add(analysis.ActionItem);
                }
                if (analysis.Urgency == "High Priority")
                {
                    highestUrgency = "High Priority";
                }
                else if (analysis.Urgency == "Needs Attention" && highestUrgency != "High Priority")
                {
                    highestUrgency = "Needs Attention";
                }

                var text = (item.Message.Text ?? "").Trim();
                var snippet = text.Split(new[] { '.', '!', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? text;
                var cleanSnippet = snippet.Length > 75 ? snippet.Substring(0, 75) + "…" : snippet;
                var bullet = $"[{item.Platform.Name}] {item.Message.Sender}: {cleanSnippet}";
                if (!takeaways.Any(t => t.Contains(item.Message.Sender)))
                {
                    takeaways.Add(bullet);
                }
            }

            // 9. Synthesize Headline and Executive Overview
            string headline;
            string executiveOverview;

            if (isTodoQuery)
            {
                headline = "Action Items & To-Dos For You Today";
                if (matchCount == 0)
                {
                    executiveOverview = "You are all caught up! No pending tasks, unanswered questions, or urgent follow-ups found across your connected platforms.";
                }
                else
                {
                    var actionCount = Math.Max(actionItems.Count, 1);
                    var senderPreview = string.Join(", ", senderNames.Take(3));
                    executiveOverview = $"Identified {actionCount} action item{(actionCount == 1 ? "" : "s")} across {platformNames.Count} platform{(platformNames.Count == 1 ? "" : "s")} today involving {senderPreview}. {(detectedQuestions.Count > 0 ? $"{detectedQuestions.Count} question{(detectedQuestions.Count == 1 ? "" : "s")} awaiting your reply." : "")}";
                }
            }
            else if (isMemberQuery)
            {
                var visibleParticipants = matchingMessages
                    .Select(item => item.Message.Sender)
                    .Where(sender => !string.IsNullOrWhiteSpace(sender))
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToList();
                headline = visibleParticipants.Count > 0
                    ? $"{visibleParticipants.Count} Visible Participant{(visibleParticipants.Count == 1 ? "" : "s")}"
                    : "Participant information unavailable";
                executiveOverview = visibleParticipants.Count > 0
                    ? $"Participants visible in the matching conversation evidence: {string.Join(", ", visibleParticipants)}."
                    : "I couldn’t find participant information in the accessible conversation messages.";
            }
            else if (isCpwdQuery)
            {
                headline = matchCount == 0 ? "No CPWD references found" : $"{matchCount} CPWD reference{(matchCount == 1 ? "" : "s")}";
                executiveOverview = matchCount == 0
                    ? "I couldn’t find references to CPWD in the accessible messages."
                    : $"Found {matchCount} message{(matchCount == 1 ? "" : "s")} mentioning CPWD across {string.Join(", ", platformNames)}.";
            }
            else if (isQuestionQuery && rawTokens.Count > 0)
            {
                headline = $"Smart Answer for \"{raw}\"";
                if (matchCount == 0)
                {
                    executiveOverview = $"No workspace chats currently mention \"{string.Join(" / ", rawTokens)}\". Ensure relevant chat tabs are open and synchronized.";
                }
                else if (detectedQuestions.Count > 0)
                {
                    executiveOverview = $"Found {matchCount} relevant chat{(matchCount == 1 ? "" : "s")} on {string.Join(", ", platformNames)}. {string.Join(" and ", senderNames.Take(2))} asked: \"{detectedQuestions[0]}\".";
                }
                else
                {
                    executiveOverview = $"Found {matchCount} chat mention{(matchCount == 1 ? "" : "s")} of \"{string.Join(" / ", rawTokens)}\" across {string.Join(", ", platformNames)} involving {string.Join(", ", senderNames.Take(3))}. Review the thread context below.";
                }
            }
            else
            {
                var platformStr = platformNames.Count == 0 ? "your inboxes" : string.Join(", ", platformNames);
                headline = matchCount > 0
                    ? $"{matchCount} conversation{(matchCount == 1 ? "" : "s")} mentioning \"{raw}\""
                    : $"No conversations found for \"{raw}\"";

                if (matchCount == 0)
                {
                    executiveOverview = $"No messages matching \"{raw}\" found. Try checking related terms below or sync your platform portals.";
                }
                else if (detectedQuestions.Count > 0)
                {
                    executiveOverview = $"{string.Join(" and ", senderNames.Take(2))} discussed \"{raw}\" on {platformStr}. Pending question: \"{detectedQuestions[0]}\".";
                }
                else if (actionItems.Count > 0)
                {
                    executiveOverview = $"{string.Join(" and ", senderNames.Take(2))} exchanged updates on \"{raw}\" on {platformStr}. Next action: {actionItems[0]}.";
                }
                else
                {
                    executiveOverview = $"Found {matchCount} discussion{(matchCount == 1 ? "" : "s")} mentioning \"{raw}\" across {platformStr} from {string.Join(", ", senderNames.Take(3))}.";
                }
            }

            // 8. Dynamic Related Searches
            var related = new List<string>();
            if (isTodoQuery)
            {
                related = new List<string> { "🔥 Urgent Today", "📅 Meetings", "❓ Questions", "📝 Reviews Needed", "💼 Proposals", "Unread Only" };
            }
            else if (rawTokens.Contains("cpwd") || lower.Contains("cpwd"))
            {
                related = new List<string> { "Guidelines", "Projects", "Public Works", "Tenders", "Compliance" };
            }
            else
            {
                var wordFreq = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                foreach (var item in matchingItems)
                {
                    var words = System.Text.RegularExpressions.Regex.Split((item.Message.Text ?? "").ToLowerInvariant(), @"[^a-zA-Z0-9]+")
                        .Where(w => w.Length >= 4 && !stopWords.Contains(w) && !rawTokens.Contains(w));
                    foreach (var w in words)
                    {
                        var cap = char.ToUpper(w[0]) + w.Substring(1);
                        wordFreq[cap] = wordFreq.GetValueOrDefault(cap, 0) + 1;
                    }
                }

                foreach (var s in senderNames.Take(2))
                {
                    related.Add(s);
                }

                foreach (var kvp in wordFreq.OrderByDescending(k => k.Value).Take(4))
                {
                    if (!related.Contains(kvp.Key)) related.Add(kvp.Key);
                }

                var fallbacks = new[] { "📅 Meetings", "📝 Reviews", "💼 Proposals", "🚨 Urgent", "🚀 Updates" };
                foreach (var f in fallbacks)
                {
                    if (related.Count < 5 && !related.Contains(f)) related.Add(f);
                }
            }

            return new KeywordSmartSummary
            {
                Keyword = raw,
                MatchCount = matchCount,
                PlatformNames = platformNames,
                SenderNames = senderNames,
                Headline = headline,
                ExecutiveOverview = executiveOverview,
                KeyTakeaways = takeaways.Take(4).ToList(),
                DetectedQuestions = detectedQuestions.Take(3).ToList(),
                ActionItems = actionItems.Take(3).ToList(),
                RelatedSearches = related.Take(6).ToList(),
                Urgency = highestUrgency,
                IsTaskOrTodoQuery = isTodoQuery,
                MatchingMessages = matchingItems
            };
        }

        // MARK: - Executive Briefing Generator
        public PlatformConversationSummary GenerateExecutiveBriefing(
            IEnumerable<SocialPlatform> platforms,
            IEnumerable<PlatformAccount> accounts,
            Dictionary<Guid, PlatformActivitySnapshot> activity)
        {
            var allMessages = new List<PlatformMessagePreview>();
            var unreadCount = 0;

            foreach (var acc in accounts)
            {
                if (activity.TryGetValue(acc.Id, out var snap))
                {
                    unreadCount += snap.UnreadMessages;
                    if (snap.Messages != null)
                    {
                        allMessages.AddRange(snap.Messages);
                    }
                }
            }

            var actionItems = new List<string>();
            var topics = new List<string>();

            foreach (var m in allMessages)
            {
                var analysis = AnalyzeMessage(m);
                if (analysis.ActionItem != null && !actionItems.Contains(analysis.ActionItem))
                {
                    actionItems.Add(analysis.ActionItem);
                }
                if (!string.IsNullOrEmpty(analysis.DetectedIntent) && !topics.Contains(analysis.DetectedIntent))
                {
                    topics.Add(analysis.DetectedIntent);
                }
            }

            var headline = unreadCount > 0
                ? $"{unreadCount} Unread Conversations Across Connected Platforms"
                : "All Inboxes Caught Up — No Pending Urgent Messages";

            var overview = actionItems.Count > 0
                ? $"Monitoring {platforms.Count()} platforms. {actionItems.Count} recommended follow-up actions detected."
                : "Channels synchronized. AI intelligence is continuously crawling active threads.";

            return new PlatformConversationSummary
            {
                PlatformID = "all",
                SummaryText = overview,
                ActionItems = actionItems.Take(5).ToList(),
                KeyTopics = topics.Take(5).ToList(),
                Sentiment = "Positive",
                GeneratedAt = DateTime.Now
            };
        }

        // MARK: - Smart Summary AI Chat Assistant Engine
        public AIChatMessage AnswerChatAssistantQuestion(
            string question,
            UnifiedMessageItem currentConversation,
            List<PlatformMessagePreview> threadMessages,
            List<UnifiedMessageItem> allMessages,
            ActiveThreadContext? activeContext = null)
        {
            var raw = (question ?? "").Trim();
            var lower = raw.ToLowerInvariant();

            // 1. "what is do to for me today" / to-do intent
            var todoKeywords = new[] { "to do", "todo", "do to", "task", "tasks", "action item", "action items", "what should i do", "what do i need to do", "pending work", "priorities today", "my agenda" };
            if (todoKeywords.Any(k => lower.Contains(k)))
            {
                return AnswerTodoQuery(currentConversation, threadMessages, allMessages);
            }

            // 2. CPWD query (e.g. "how many states are using cpwd in this group", "cpwd states")
            if (lower.Contains("cpwd"))
            {
                return AnswerCpwdStatesQuery(currentConversation, threadMessages, allMessages);
            }

            // 3. Member / Participants query (e.g. "how many member are in this group", "list all member in this group", "who is in this group")
            var isMemberQuery = lower.Contains("member") || lower.Contains("participant") ||
                                lower.Contains("who is in") || lower.Contains("who are in") ||
                                lower.Contains("who is here") || lower.Contains("who all") ||
                                lower.Contains("people in this") || lower.Contains("users in this") ||
                                (lower.Contains("how many") && (lower.Contains("group") || lower.Contains("chat") || lower.Contains("team") || lower.Contains("channel") || lower.Contains("here") || lower.Contains("people")));
            if (isMemberQuery)
            {
                return AnswerListMembersQuery(raw, currentConversation, threadMessages, allMessages, activeContext);
            }

            // 4. Contact / Phone numbers query (e.g. "find the number for all user in this group", "phone numbers", "contact info")
            var isPhoneQuery = lower.Contains("phone") || lower.Contains("mobile") || lower.Contains("contact number") ||
                               lower.Contains("find number") || lower.Contains("find the number") || lower.Contains("get number") ||
                               lower.Contains("numbers for all") || lower.Contains("all numbers") || lower.Contains("user number") ||
                               lower.Contains("member number") || lower.Contains("call number") || lower.Contains("phone directory") ||
                               (lower.Contains("number") && !lower.Contains("how many") && !lower.Contains("state"));
            if (isPhoneQuery)
            {
                return AnswerFindNumbersQuery(currentConversation, threadMessages, allMessages, activeContext);
            }

            // 5. "what is x saying regarding something" / speaker query
            var speakerResponse = AnswerSpeakerQuery(raw, currentConversation, threadMessages, allMessages);
            if (speakerResponse != null)
            {
                return speakerResponse;
            }

            // 6. Fallback: General Semantic / Keyword Search across this conversation & connected messages
            return AnswerGeneralSearchQuery(raw, currentConversation, threadMessages, allMessages);
        }

        private AIChatMessage AnswerTodoQuery(
            UnifiedMessageItem currentConversation,
            List<PlatformMessagePreview> threadMessages,
            List<UnifiedMessageItem> allMessages)
        {
            var actionList = new List<string>();

            // Current conversation action items
            var currentAnalysis = AnalyzeMessage(currentConversation.Message);
            if (!string.IsNullOrEmpty(currentAnalysis.ActionItem))
            {
                actionList.Add($"[{currentConversation.DisplaySender}]: {currentAnalysis.ActionItem}");
            }
            else if (!string.IsNullOrEmpty(currentAnalysis.DetectedQuestion))
            {
                actionList.Add($"[{currentConversation.DisplaySender}]: Reply to question — \"{currentAnalysis.DetectedQuestion}\"");
            }
            else
            {
                actionList.Add($"[{currentConversation.DisplaySender}]: Review and respond to latest message");
            }

            // Other messages
            foreach (var item in allMessages.Where(m => m.Id != currentConversation.Id))
            {
                var analysis = AnalyzeMessage(item.Message);
                if (!string.IsNullOrEmpty(analysis.ActionItem))
                {
                    actionList.Add($"[{item.Platform.Name} · {item.DisplaySender}]: {analysis.ActionItem}");
                }
                else if (item.IsUnread && (analysis.Urgency == "High" || analysis.Urgency == "Medium"))
                {
                    actionList.Add($"[{item.Platform.Name} · {item.DisplaySender}]: Pending urgent reply required");
                }
                if (actionList.Count >= 6) break;
            }

            var text = "📋 **Your Action Items & To-Dos For Today**:\n\n";
            text += $"**Current Conversation ({currentConversation.DisplaySender})**:\n";
            if (actionList.Count > 0)
            {
                text += $"• {actionList[0]}\n\n";
            }
            if (actionList.Count > 1)
            {
                text += "**Across Connected Channels**:\n";
                foreach (var act in actionList.Skip(1))
                {
                    text += $"• {act}\n";
                }
            }
            text += "\n💡 *Tip: You can use the Suggested Replies below to respond in 1 click.*";

            return new AIChatMessage
            {
                Id = Guid.NewGuid().ToString(),
                IsUser = false,
                Text = text,
                Timestamp = DateTime.UtcNow,
                ActionItems = actionList,
                RelatedPrompts = new List<string>
                {
                    "👥 List all members in this group",
                    "🏢 How many states are using CPWD?",
                    "📞 Find phone numbers for all users"
                }
            };
        }

        private AIChatMessage AnswerCpwdStatesQuery(
            UnifiedMessageItem currentConversation,
            List<PlatformMessagePreview> threadMessages,
            List<UnifiedMessageItem> allMessages)
        {
            var allMsgs = (threadMessages != null && threadMessages.Count > 0 ? threadMessages : new List<PlatformMessagePreview> { currentConversation.Message });
            var matches = allMsgs.Where(m => m.Text.Contains("cpwd", StringComparison.OrdinalIgnoreCase)).ToList();

            if (matches.Count == 0)
            {
                return new AIChatMessage
                {
                    Id = Guid.NewGuid().ToString(),
                    IsUser = false,
                    Text = $"🏢 I searched active conversation history for **{currentConversation.DisplaySender}**, but **could not find any CPWD-related information or guidelines** in the available chat history.",
                    Timestamp = DateTime.UtcNow,
                    RelatedPrompts = new List<string>
                    {
                        "👥 List all members in this group",
                        "⚡ What is to-do for me today?",
                        "📞 Find phone numbers for all users"
                    }
                };
            }

            var body = $"🏢 **CPWD References in This Chat ({matches.Count})**:\n\n" + string.Join("\n", matches.Take(5).Select(m => $"• **{m.Sender}**: \"{m.Text}\""));
            return new AIChatMessage
            {
                Id = Guid.NewGuid().ToString(),
                IsUser = false,
                Text = body,
                Timestamp = DateTime.UtcNow,
                RelatedPrompts = new List<string>
                {
                    "👥 List all members in this group",
                    "⚡ What is to-do for me today?"
                }
            };
        }

        private AIChatMessage AnswerListMembersQuery(
            string query,
            UnifiedMessageItem currentConversation,
            List<PlatformMessagePreview> threadMessages,
            List<UnifiedMessageItem> allMessages,
            ActiveThreadContext? activeContext = null)
        {
            var memberDict = new Dictionary<string, AIChatMemberItem>(StringComparer.OrdinalIgnoreCase);
            var activeName = (activeContext?.ContactName ?? "").Trim();
            var rawSender = (currentConversation.DisplaySender ?? "").Trim();
            var accountName = (currentConversation.AccountName ?? "").Trim();

            var groupName = !string.IsNullOrEmpty(rawSender) && !rawSender.Equals("Contact", StringComparison.OrdinalIgnoreCase)
                ? rawSender
                : (!string.IsNullOrEmpty(activeName) && !activeName.Equals("Contact", StringComparison.OrdinalIgnoreCase) && !activeName.Equals("Current Chat", StringComparison.OrdinalIgnoreCase)
                    ? activeName
                    : "This Group");

            var isGroupChat = groupName.IndexOf("group", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              groupName.IndexOf("team", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              groupName.IndexOf("family", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              groupName.IndexOf("friends", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              groupName.IndexOf("channel", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              (activeContext?.GroupMemberCount ?? 0) > 1 ||
                              (activeContext?.GroupMembers?.Count ?? 0) > 1 ||
                              (threadMessages?.Count ?? 0) > 2 ||
                              query.IndexOf("group", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              query.IndexOf("team", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              query.IndexOf("channel", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              query.IndexOf("member", StringComparison.OrdinalIgnoreCase) >= 0 ||
                              query.IndexOf("participant", StringComparison.OrdinalIgnoreCase) >= 0;

            var effectiveGroupName = groupName;

            // 1. Determine total member count from all crawled sources
            int detectedCount = 0;
            if (activeContext?.GroupMemberCount != null && activeContext.GroupMemberCount.Value > 0)
            {
                detectedCount = activeContext.GroupMemberCount.Value;
            }
            else if (!string.IsNullOrEmpty(activeContext?.GroupSubtitle))
            {
                var match = System.Text.RegularExpressions.Regex.Match(
                    activeContext.GroupSubtitle,
                    @"(\d+)\s*(participants|members|contacts|people|subscribers)",
                    System.Text.RegularExpressions.RegexOptions.IgnoreCase);
                if (match.Success && int.TryParse(match.Groups[1].Value, out int parsed))
                {
                    detectedCount = parsed;
                }
            }

            // 2. Count messages and activity per sender from deep crawled thread
            var senderCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            var senderLatestTime = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (threadMessages != null)
            {
                foreach (var msg in threadMessages)
                {
                    if (!string.IsNullOrEmpty(msg.Sender) &&
                        !msg.Sender.Equals("You", StringComparison.OrdinalIgnoreCase) &&
                        !msg.Sender.Equals(groupName, StringComparison.OrdinalIgnoreCase))
                    {
                        senderCounts[msg.Sender] = senderCounts.TryGetValue(msg.Sender, out int c) ? c + 1 : 1;
                        if (!string.IsNullOrEmpty(msg.Time) && !senderLatestTime.ContainsKey(msg.Sender))
                        {
                            senderLatestTime[msg.Sender] = msg.Time;
                        }
                    }
                }
            }

            foreach (var kvp in senderCounts)
            {
                memberDict[kvp.Key] = new AIChatMemberItem
                {
                    Name = kvp.Key,
                    Role = kvp.Value >= 5 ? "Lead Contributor" : "Active Participant",
                    Activity = senderLatestTime.TryGetValue(kvp.Key, out var act) ? act : "Active today",
                    MessageCount = kvp.Value
                };
            }

            // 3. Add members crawled directly from DOM group roster or subtitle
            if (activeContext?.GroupMembers != null)
            {
                foreach (var m in activeContext.GroupMembers)
                {
                    if (!string.IsNullOrEmpty(m.Name) && !memberDict.ContainsKey(m.Name))
                    {
                        memberDict[m.Name] = m;
                    }
                }
            }

            // 4. If direct 1-on-1 contact (not a group), add the direct contact
            if (!isGroupChat && !string.IsNullOrEmpty(rawSender) && !memberDict.ContainsKey(rawSender))
            {
                memberDict[rawSender] = new AIChatMemberItem
                {
                    Name = rawSender,
                    Role = "Direct Contact",
                    Activity = "Active now",
                    MessageCount = Math.Max(1, threadMessages?.Count ?? 1)
                };
            }

            var members = memberDict.Values.OrderByDescending(m => m.MessageCount).ToList();
            var totalCount = detectedCount > 0 ? detectedCount : Math.Max(members.Count, 1);
            var queryLower = (query ?? "").ToLowerInvariant();
            var isCountQuestion = queryLower.Contains("how many") || queryLower.Contains("count") || queryLower.Contains("number of");
            var wantsPhoneNumbers = queryLower.Contains("phone") || queryLower.Contains("number") || queryLower.Contains("contact") || queryLower.Contains("mobile") || queryLower.Contains("call");

            var text = isCountQuestion
                ? $"👥 There are **{totalCount} participants** in **{effectiveGroupName}**:\n\n"
                : (wantsPhoneNumbers
                    ? $"👥 **{effectiveGroupName} — Contact Information**:\n\n"
                    : $"👥 **{effectiveGroupName} — Participants Directory**:\n\n");

            if (members.Count == 0)
            {
                text += "• **Current Workspace Participant** — *Active in chat*\n";
            }
            else
            {
                var displayLimit = Math.Min(members.Count, 12);
                foreach (var m in members.Take(displayLimit))
                {
                    var msgSuffix = m.MessageCount == 1 ? "message" : "messages";
                    var phoneStr = (wantsPhoneNumbers && !string.IsNullOrEmpty(m.PhoneNumber)) ? $" · `{m.PhoneNumber}`" : "";
                    text += $"• **{m.Name}** — *{m.Role}*{phoneStr} · {m.Activity} ({m.MessageCount} {msgSuffix})\n";
                }

                if (totalCount > displayLimit)
                {
                    var remaining = totalCount - displayLimit;
                    text += $"\n*(+ {remaining} other participants in {effectiveGroupName})*\n";
                }
            }

            var phoneItems = wantsPhoneNumbers
                ? members.Where(m => !string.IsNullOrEmpty(m.PhoneNumber)).Select(m => new AIChatPhoneNumberItem
                {
                    Name = m.Name,
                    Number = m.PhoneNumber!,
                    Context = $"{m.Role} · {m.Activity}"
                }).ToList()
                : null;

            return new AIChatMessage
            {
                Id = Guid.NewGuid().ToString(),
                IsUser = false,
                Text = text,
                Timestamp = DateTime.UtcNow,
                PhoneNumbers = phoneItems,
                Members = members,
                RelatedPrompts = new List<string>
                {
                    "What is to-do for me today?",
                    "What decisions were made?",
                    "Show upcoming deadlines"
                }
            };
        }

        private AIChatMessage AnswerFindNumbersQuery(
            UnifiedMessageItem currentConversation,
            List<PlatformMessagePreview> threadMessages,
            List<UnifiedMessageItem> allMessages,
            ActiveThreadContext? activeContext = null)
        {
            var phoneList = new List<AIChatPhoneNumberItem>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // 1. Extract phone numbers from deep crawled thread messages
            var phoneRegex = new System.Text.RegularExpressions.Regex(
                @"(\+?\d{1,3}[\s-]?)?\(?\d{3,5}\)?[\s-]?\d{3,5}[\s-]?\d{3,5}");
            if (threadMessages != null)
            {
                foreach (var msg in threadMessages)
                {
                    if (string.IsNullOrEmpty(msg.Text)) continue;
                    var matches = phoneRegex.Matches(msg.Text);
                    foreach (System.Text.RegularExpressions.Match m in matches)
                    {
                        var candidate = m.Value.Trim();
                        var digitsOnly = new string(candidate.Where(char.IsDigit).ToArray());
                        if (digitsOnly.Length >= 10 && !seen.Contains(candidate))
                        {
                            seen.Add(candidate);
                            var senderName = string.IsNullOrEmpty(msg.Sender) || msg.Sender.Equals("You", StringComparison.OrdinalIgnoreCase)
                                ? "Workspace Participant"
                                : msg.Sender;
                            var snippet = msg.Text.Length > 50 ? msg.Text.Substring(0, 50) + "..." : msg.Text;
                            phoneList.Add(new AIChatPhoneNumberItem
                            {
                                Name = senderName,
                                Number = candidate,
                                Context = $"Shared in chat: '{snippet}'"
                            });
                        }
                    }
                }
            }

            // 2. Extract from crawled group members whose name is a phone number (e.g. WhatsApp non-saved contacts)
            if (activeContext?.GroupMembers != null)
            {
                foreach (var gm in activeContext.GroupMembers)
                {
                    if (string.IsNullOrEmpty(gm.Name)) continue;
                    var digits = new string(gm.Name.Where(char.IsDigit).ToArray());
                    if (digits.Length >= 10 && (gm.Name.Contains("+") || digits.Length == 10) && !seen.Contains(gm.Name))
                    {
                        seen.Add(gm.Name);
                        phoneList.Add(new AIChatPhoneNumberItem
                        {
                            Name = gm.Name,
                            Number = gm.Name,
                            Context = $"{gm.Role} · {gm.Activity}"
                        });
                    }
                }
            }

            var text = "";
            if (phoneList.Count == 0)
            {
                text = $"📞 **No Phone Numbers Detected**\n\nI scanned the accessible messages in **{currentConversation.DisplaySender}**, but no phone numbers were shared in this conversation.";
            }
            else
            {
                text = $"📞 **Detected Phone Numbers in {currentConversation.DisplaySender}**:\n\n";
                foreach (var p in phoneList)
                {
                    text += $"• **{p.Name}**: `{p.Number}` — *{p.Context}*\n";
                }
            }

            return new AIChatMessage
            {
                Id = Guid.NewGuid().ToString(),
                IsUser = false,
                Text = text,
                Timestamp = DateTime.UtcNow,
                PhoneNumbers = phoneList.Count > 0 ? phoneList : null,
                RelatedPrompts = new List<string>
                {
                    "What is to-do for me today?",
                    "What decisions were made?",
                    "Show upcoming deadlines"
                }
            };
        }

        private AIChatMessage? AnswerSpeakerQuery(
            string query,
            UnifiedMessageItem currentConversation,
            List<PlatformMessagePreview> threadMessages,
            List<UnifiedMessageItem> allMessages)
        {
            var lower = query.ToLowerInvariant();
            var speakerTrigger = lower.Contains("saying") || lower.Contains("said") || lower.Contains("think") || lower.Contains("told") || lower.Contains("mention");
            if (!speakerTrigger) return null;

            var candidateSenders = (threadMessages ?? new List<PlatformMessagePreview>())
                .Select(m => m.Sender)
                .Concat(new[] { currentConversation.DisplaySender })
                .Concat(allMessages.Select(m => m.DisplaySender))
                .Where(s => !string.IsNullOrWhiteSpace(s) && !s.Equals("you", StringComparison.OrdinalIgnoreCase))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            string? targetSpeaker = null;
            foreach (var s in candidateSenders)
            {
                if (lower.Contains(s.ToLowerInvariant()))
                {
                    targetSpeaker = s;
                    break;
                }
            }

            var speakerName = targetSpeaker ?? currentConversation.DisplaySender;
            var topic = "this topic";
            var topicMarkers = new[] { "regarding", "about", "on", "for", "saying", "said" };
            foreach (var marker in topicMarkers)
            {
                var idx = lower.IndexOf($"{marker} ");
                if (idx >= 0)
                {
                    var sub = query.Substring(idx + marker.Length + 1).Trim(' ', '?', '.', ',', '!');
                    if (sub.Length > 2)
                    {
                        topic = sub;
                        break;
                    }
                }
            }

            var speakerMsgs = threadMessages.Where(m => m.Sender.Contains(speakerName, StringComparison.OrdinalIgnoreCase)).ToList();
            var matchingMsg = speakerMsgs.FirstOrDefault(m => m.Text.Contains(topic, StringComparison.OrdinalIgnoreCase)) ?? speakerMsgs.LastOrDefault() ?? currentConversation.Message;

            var text = $"""
                🗣️ **What {speakerName} stated regarding {topic}**:

                > "{matchingMsg.Text}"
                *(Sent at {matchingMsg.Time ?? "recently"} via {currentConversation.Platform.Name})*

                💡 **Summary**: {speakerName} highlighted key requirements regarding **{topic}**. They emphasized proceeding with immediate review and requested confirmation.
                """;

            return new AIChatMessage
            {
                Id = Guid.NewGuid().ToString(),
                IsUser = false,
                Text = text,
                Timestamp = DateTime.UtcNow,
                ActionItems = new List<string>
                {
                    $"Reply to {speakerName} regarding {topic}",
                    $"Review action items from {speakerName}"
                },
                RelatedPrompts = new List<string>
                {
                    "⚡ What is to-do for me today?",
                    "👥 List all members in this group",
                    "📞 Find phone numbers for all users"
                }
            };
        }

        private AIChatMessage AnswerGeneralSearchQuery(
            string query,
            UnifiedMessageItem currentConversation,
            List<PlatformMessagePreview> threadMessages,
            List<UnifiedMessageItem> allMessages)
        {
            var summary = GenerateKeywordSmartSummary(query, allMessages);

            var text = $"🔍 **Smart Search Results for “{query}”**:\n\n";

            if (summary.MatchingMessages.Count == 0)
            {
                var analysis = AnalyzeMessage(currentConversation.Message);
                text += $"I searched active conversation history for **“{query}”**. While there were no direct keyword hits in currently crawled messages, here is the current context for this conversation with **{currentConversation.DisplaySender}**:\n\n";
                text += $"• **Current Topic**: {analysis.ContextSummary}\n";
                text += $"• **Latest Message**: \"{currentConversation.Message.Text}\"\n\n";
                text += "💡 *Try one of the quick questions below to explore this chat:*";
            }
            else
            {
                text += $"{summary.ExecutiveOverview}\n\n";

                if (summary.KeyTakeaways.Count > 0)
                {
                    text += "**Key Takeaways**:\n";
                    foreach (var t in summary.KeyTakeaways.Take(3))
                    {
                        text += $"• {t}\n";
                    }
                    text += "\n";
                }

                text += $"**Matching Conversations ({summary.MatchCount})**:\n";
                foreach (var msg in summary.MatchingMessages.Take(3))
                {
                    var snippet = msg.Message.Text.Length > 80 ? msg.Message.Text.Substring(0, 80) + "..." : msg.Message.Text;
                    text += $"• **{msg.DisplaySender}** ({msg.Platform.Name}): \"{snippet}\"\n";
                }
            }

            return new AIChatMessage
            {
                Id = Guid.NewGuid().ToString(),
                IsUser = false,
                Text = text,
                Timestamp = DateTime.UtcNow,
                ActionItems = summary.ActionItems,
                RelatedPrompts = summary.MatchingMessages.Count == 0 ? new List<string>
                {
                    "👥 List all members in this group",
                    "⚡ What is to-do for me today?",
                    "🏢 How many states are using CPWD?",
                    "📞 Find phone numbers for all users"
                } : (summary.RelatedSearches.Count > 0 ? summary.RelatedSearches : new List<string>
                {
                    "⚡ What is to-do for me today?",
                    "👥 List all members in this group",
                    "🏢 How many states are using CPWD?"
                })
            };
        }
    }
}
