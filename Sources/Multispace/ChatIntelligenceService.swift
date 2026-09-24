import Foundation

struct ChatIntelligenceSource: Identifiable, Equatable, Codable {
    let id: String
    let messageID: String
    let sender: String
    let time: String?
    let messageNumber: Int

    var label: String {
        if let time, !time.isEmpty { return "\(sender) · \(time)" }
        return "\(sender) · Message \(messageNumber)"
    }
}

struct ChatIntelligenceAnalysis: Equatable, Codable {
    let conversationID: String
    let messageCount: Int
    let summary: [String]
    let topics: [String]
    let decisions: [String]
    let tasks: [String]
    let structuredTasks: [AITaskItem]
    let dates: [String]
    let people: [String]
    let phoneNumbers: [String]
    let emails: [String]
    let links: [String]
    let files: [String]
    let unresolvedQuestions: [String]
    let suggestedQuestions: [String]
    let sources: [ChatIntelligenceSource]
    let generatedAt: Date

    var hasUsefulContext: Bool { messageCount > 0 && !summary.isEmpty }
}

@MainActor
final class ChatIntelligenceService {
    static let shared = ChatIntelligenceService()
    static let maximumMessages = 250

    private let stopWords: Set<String> = [
        "about", "after", "again", "also", "and", "are", "been", "before", "but", "can", "could",
        "did", "does", "for", "from", "have", "here", "into", "just", "more", "our", "that", "the",
        "their", "them", "then", "there", "they", "this", "today", "was", "were", "what", "when",
        "where", "which", "will", "with", "would", "you", "your"
    ]

    private init() {}

    func analyze(conversationID: String, messages: [PlatformMessagePreview]) -> ChatIntelligenceAnalysis {
        let scoped = Array(messages.suffix(Self.maximumMessages)).filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let sources = scoped.enumerated().map { index, message in
            ChatIntelligenceSource(
                id: "\(message.id)-\(index)",
                messageID: message.id,
                sender: message.sender.isEmpty ? "Unknown sender" : message.sender,
                time: message.time,
                messageNumber: index + 1
            )
        }

        var decisions: [String] = []
        var tasks: [String] = []
        var structuredTasks: [AITaskItem] = []
        var dates: [String] = []
        var questions: [String] = []
        var phones: [String] = []
        var emails: [String] = []
        var links: [String] = []
        var files: [String] = []
        var wordCounts: [String: Int] = [:]

        let otherSenders = scoped.map(\.sender).filter { !$0.isEmpty && $0.lowercased() != "you" }
        let primaryRecipient = otherSenders.first ?? "team member"

        for message in scoped {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()
            let referenced = "\(compact(text)) — \(sourceLabel(for: message, in: scoped))"

            if containsAny(lower, ["decided", "agreed", "approved", "confirmed", "we'll proceed", "will proceed", "final decision"]) {
                appendUnique(referenced, to: &decisions)
            }
            if containsAny(lower, ["need to", "needs to", "please ", "todo", "to-do", "action item", "must ", "should ", "will send", "will update", "follow up", "deadline"]) {
                let resolvedTaskText: String
                let assignee: String?
                if message.sender.lowercased() == "you" {
                    if lower.contains("will send") || lower.contains("will update") {
                        resolvedTaskText = "Send update to \(primaryRecipient) — \(sourceLabel(for: message, in: scoped))"
                        assignee = "You"
                    } else if lower.contains("let me know") || lower.contains("when can you") {
                        resolvedTaskText = "Wait for \(primaryRecipient) to confirm — \(sourceLabel(for: message, in: scoped))"
                        assignee = primaryRecipient
                    } else {
                        resolvedTaskText = "Follow up with \(primaryRecipient) — \(sourceLabel(for: message, in: scoped))"
                        assignee = "You"
                    }
                } else {
                    resolvedTaskText = "\(message.sender): \(compact(text)) — \(sourceLabel(for: message, in: scoped))"
                    assignee = message.sender
                }
                appendUnique(resolvedTaskText, to: &tasks)

                let taskItem = AITaskItem(
                    id: "\(message.id)-task",
                    title: stripReference(resolvedTaskText),
                    assignee: assignee,
                    createdBy: message.sender,
                    dueDate: nil,
                    sourceMessageId: message.id,
                    isCompleted: false
                )
                structuredTasks.append(taskItem)
            }
            if text.contains("?") {
                appendUnique(referenced, to: &questions)
            }

            extractMatches(in: text, pattern: #"(?i)\b(?:today|tomorrow|tonight|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next week|this week|eod|e\.o\.d\.|\d{1,2}[:.]\d{2}\s?(?:am|pm)?|\d{1,2}[/-]\d{1,2}(?:[/-]\d{2,4})?|\d{1,2}\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?))\b"#)
                .forEach { appendUnique($0, to: &dates) }
            extractMatches(in: text, pattern: #"(?<!\w)(?:\+?\d[\d ()-]{8,}\d)(?!\w)"#)
                .filter { $0.filter(\.isNumber).count >= 10 }
                .forEach { appendUnique($0, to: &phones) }
            extractMatches(in: text, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: .caseInsensitive)
                .forEach { appendUnique($0, to: &emails) }
            extractMatches(in: text, pattern: #"https?://[^\s<>]+"#, options: .caseInsensitive)
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,);]")) }
                .forEach { appendUnique($0, to: &links) }
            extractMatches(in: text, pattern: #"(?i)\b[^\s/\\]+\.(?:pdf|docx?|xlsx?|pptx?|csv|zip|png|jpe?g|fig|txt)\b"#)
                .forEach { appendUnique($0, to: &files) }

            for word in lower.components(separatedBy: CharacterSet.alphanumerics.inverted) where word.count >= 4 && !stopWords.contains(word) {
                wordCounts[word, default: 0] += 1
            }
        }

        let people = Array(Set(scoped.map(\.sender).filter { !$0.isEmpty && $0.lowercased() != "you" })).sorted()
        let topics = wordCounts.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }.prefix(6).map { $0.key.capitalized }

        var summary: [String] = []
        decisions.prefix(2).forEach { appendUnique(stripReference($0), to: &summary) }
        tasks.prefix(3).forEach { appendUnique(stripReference($0), to: &summary) }
        if summary.isEmpty {
            scoped.suffix(5).reversed().forEach { message in
                if summary.count < 5 { appendUnique(compact(message.text), to: &summary) }
            }
        }

        let primarySender = people.first ?? "this chat"
        let suggestions = generateDynamicPrompts(
            messages: scoped,
            conversationTitle: primarySender,
            tasks: tasks,
            decisions: decisions,
            dates: dates,
            links: links,
            files: files,
            phones: phones,
            topics: topics,
            people: people
        )

        return ChatIntelligenceAnalysis(
            conversationID: conversationID,
            messageCount: scoped.count,
            summary: Array(summary.prefix(5)),
            topics: Array(topics),
            decisions: Array(decisions.prefix(8)),
            tasks: Array(tasks.prefix(12)),
            structuredTasks: structuredTasks,
            dates: Array(dates.prefix(12)),
            people: people,
            phoneNumbers: Array(phones.prefix(30)),
            emails: Array(emails.prefix(30)),
            links: Array(links.prefix(30)),
            files: Array(files.prefix(30)),
            unresolvedQuestions: Array(questions.prefix(10)),
            suggestedQuestions: Array(suggestions.prefix(6)),
            sources: sources,
            generatedAt: .now
        )
    }

    func answer(
        question: String,
        analysis: ChatIntelligenceAnalysis,
        messages: [PlatformMessagePreview],
        members: [AIChatMemberItem]?,
        preferences: AppPreferences? = nil,
        priorContext: String? = nil,
        conversationTitle: String? = nil,
        groupMemberCount: Int? = nil,
        groupSubtitle: String? = nil
    ) async -> AIChatMessage {
        let scoped = Array(messages.suffix(Self.maximumMessages))
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return AIChatMessage(id: UUID().uuidString, isUser: false, text: "Please enter a question to analyze.", timestamp: .now)
        }

        let resolution = preferences.map { AIProviderResolver.resolve(preferences: $0) }
        let canPerformGenerative = resolution?.canPerformGenerativeAI ?? false

        // =============================================================
        // PATH A: Connected Generative AI Provider (Deep Grounded Analysis)
        // =============================================================
        if let prefs = preferences, let res = resolution, canPerformGenerative {
            // Build rich grounded transcript from the entire scoped conversation
            let fullTranscript = scoped.enumerated().map { index, msg in
                let timeStr = (msg.time?.isEmpty == false) ? " [\(msg.time!)]" : ""
                let senderStr = msg.sender.isEmpty ? "Unknown" : msg.sender
                return "[#\(index + 1) | \(senderStr)\(timeStr)]: \(msg.text)"
            }.joined(separator: "\n")

            let availableMembers = groundedMembers(messages: scoped, metadataMembers: members)
            let uniqueSenders = Array(Set(scoped.map(\.sender).filter { !$0.isEmpty && $0.lowercased() != "you" })).sorted()
            let title = conversationTitle?.isEmpty == false ? conversationTitle! : (analysis.people.first ?? "Current Thread")

            let isExplicitGroup = (groupMemberCount ?? 0) > 2 || (groupSubtitle?.isEmpty == false) || availableMembers.count > 1 || uniqueSenders.count > 1
            let totalCount = groupMemberCount ?? max(availableMembers.count, max(1, uniqueSenders.count))
            let channelType = isExplicitGroup ? "Group Chat (\(totalCount) members)" : "Direct 1-on-1 / Service Notification Channel"

            let membersList = availableMembers.isEmpty
                ? (uniqueSenders.isEmpty ? title : uniqueSenders.joined(separator: ", "))
                : availableMembers.map { m in
                    let phone = (m.phoneNumber?.isEmpty == false) ? " (\(m.phoneNumber!))" : ""
                    return "\(m.name)\(phone) - \(m.role)"
                }.joined(separator: "; ")

            let sysPrompt = """
            You are Pinggo AI, an expert workplace intelligence analyst embedded in the Pinggo communication app.
            You have full, direct access to the entire selected conversation history and verified conversation metadata provided below.

            YOUR CORE MANDATE:
            Provide a deep, thorough, exact, and actionable answer to the user's question. Read and analyze the entire conversation history from beginning to end.

            ANALYSIS GUIDELINES:
            1. Member Count & Group Composition:
               - When the user asks "how many members are in this group", "who is in this group", "list members", or asks about participants:
                 a) Always inspect the "CONVERSATION SCOPE & COMPOSITION" section in the metadata.
                 b) If Channel Type indicates a Direct 1-on-1 or Service Notification Channel (such as \(title) with 1 participant):
                    Directly clarify:
                    "This conversation is a **direct 1-on-1 notification channel with \(title)** (not a multi-member group). There is **1 participant** (**\(title)**) active in this thread."
                    Then briefly summarize what the channel communicates if relevant.
                 c) If Channel Type indicates a Group Chat:
                    Directly state the exact member count (e.g. "There are **X members** in this group") and list the identified participants with their roles/contact info.
                 d) NEVER say "the transcript does not specify the number of members in the group" when the conversation scope and participants are clearly provided in the metadata. Always synthesize the composition directly.

            2. Thoroughness & Depth:
               - Do not give lazy, generic, one-line answers. Dive deep into the conversation specifics.
               - Cross-correlate statements, timestamps, speakers, decisions, deliverables, blockers, dates, files, links, and contact information.
               - When the user asks about tasks or to-dos: identify assignees, deadlines, context, status, and related discussion.
               - When the user asks about decisions: explain what was decided, who confirmed it, when, and any contingencies.
               - When the user asks about people: analyze what they contributed, their stances, questions, commitments, and contact info.
               - When the user asks about files, links, or technical specs: detail exact names, URLs, and contextual mentions.

            3. Grounding & Zero Hallucination:
               - Strictly ground your answer in the provided conversation history and metadata.
               - Never fabricate details, dates, attendees, or requirements.
               - Quote or cite exact messages using `[Sender · Timestamp]` (or message index `[#N]`) so the user can easily verify your source.
               - If an item or detail is genuinely not mentioned in the chat, state clearly what was found in the chat and what specific requested detail is absent.

            4. Structure & Tone:
               - Professional, direct, insightful, and well-structured.
               - Use markdown bolding, headers, and bulleted lists for clarity.
               - Avoid boilerplate introductions or apologies; get straight to the high-value analysis.
            """

            let userPrompt = """
            === CONVERSATION SCOPE & COMPOSITION ===
            • Thread Title: \(title)
            • Channel Type: \(channelType)
            • Total Messages Indexed: \(scoped.count)
            • Member Count: \(isExplicitGroup ? "\(totalCount) members" : "1 participant (Direct 1-on-1 Channel)")
            • Group Subtitle / Description: \(groupSubtitle ?? "None")
            • Identified Participants: \(membersList)
            • Active Message Senders: \(uniqueSenders.isEmpty ? title : uniqueSenders.joined(separator: ", "))

            === CONVERSATION METADATA ===
            Detected Decisions: \(analysis.decisions.isEmpty ? "None" : analysis.decisions.joined(separator: " | "))
            Detected Action Items: \(analysis.tasks.isEmpty ? "None" : analysis.tasks.joined(separator: " | "))
            Mentioned Dates/Deadlines: \(analysis.dates.isEmpty ? "None" : analysis.dates.joined(separator: " | "))
            Referenced Files: \(analysis.files.isEmpty ? "None" : analysis.files.joined(separator: ", "))
            Shared Links: \(analysis.links.isEmpty ? "None" : analysis.links.joined(separator: ", "))
            Shared Contact Numbers: \(analysis.phoneNumbers.isEmpty ? "None" : analysis.phoneNumbers.joined(separator: ", "))

            === FULL CONVERSATION TRANSCRIPT (\(scoped.count) messages) ===
            \(fullTranscript)

            === PREVIOUS PINGGO AI CONTEXT ===
            \(priorContext?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? priorContext! : "No prior AI turns.")

            === USER QUESTION ===
            \(clean)
            """

            do {
                let answerText: String
                switch res.provider {
                case .gemini:
                    answerText = try await AIService.shared.callGeminiAPI(apiKey: prefs.geminiApiKey, model: res.model, prompt: userPrompt, systemInstruction: sysPrompt)
                case .chatgpt:
                    answerText = try await AIService.shared.callOpenAIAPI(apiKey: prefs.openAiApiKey, model: res.model, prompt: userPrompt, systemInstruction: sysPrompt)
                case .ollama:
                    answerText = try await AIService.shared.callOllamaAPI(endpoint: prefs.ollamaEndpoint, model: res.model, prompt: userPrompt, systemInstruction: sysPrompt)
                default:
                    answerText = "AI Provider unavailable."
                }

                let lower = clean.lowercased()
                let phoneItems: [AIChatPhoneNumberItem]? = containsAny(lower, ["phone", "mobile", "contact"]) ? analysis.phoneNumbers.map { number in
                    let owner = scoped.first(where: { $0.text.contains(number) })?.sender ?? "Shared contact"
                    return AIChatPhoneNumberItem(name: owner, number: number, context: "Found in selected conversation")
                } : nil

                let taskItems = containsAny(lower, ["task", "todo", "to-do", "action item"]) ? analysis.structuredTasks : []
                let actionItems = containsAny(lower, ["task", "todo", "to-do", "action item"]) ? analysis.tasks.map(stripReference) : []

                return AIChatMessage(
                    id: UUID().uuidString,
                    isUser: false,
                    text: answerText,
                    timestamp: .now,
                    actionItems: actionItems,
                    phoneNumbers: phoneItems,
                    relatedPrompts: analysis.suggestedQuestions,
                    source: .providerGenerated(provider: res.provider.title, model: res.model),
                    tasks: taskItems
                )
            } catch {
                // If generative API call fails (network, quota, bad key), gracefully fall back to local extraction with explicit notice
                let localFallback = performDeterministicExtraction(question: clean, analysis: analysis, scoped: scoped, members: members, conversationTitle: title, groupMemberCount: groupMemberCount, groupSubtitle: groupSubtitle)
                let fallbackText = localFallback?.text ?? searchEvidenceFallback(question: clean, scoped: scoped)

                let notice = "⚠️ **\(res.provider.title) could not complete the request** (\(error.localizedDescription)).\n*Falling back to local extraction:*\n\n\(fallbackText)"

                return AIChatMessage(
                    id: UUID().uuidString,
                    isUser: false,
                    text: notice,
                    timestamp: .now,
                    actionItems: localFallback?.actionItems ?? [],
                    phoneNumbers: localFallback?.phoneNumbers,
                    members: localFallback?.members,
                    relatedPrompts: ["Retry Question", "Check Settings > AI"] + Array(analysis.suggestedQuestions.prefix(2)),
                    source: .localHeuristic(engineName: "\(res.provider.title) Fallback"),
                    tasks: localFallback?.tasks ?? []
                )
            }
        }

        // =============================================================
        // PATH B: Offline / Unconfigured AI Provider (Local Heuristics)
        // =============================================================
        if let localResult = performDeterministicExtraction(question: clean, analysis: analysis, scoped: scoped, members: members, conversationTitle: conversationTitle, groupMemberCount: groupMemberCount, groupSubtitle: groupSubtitle) {
            return localResult
        }

        // Freeform question with no connected generative AI:
        return AIChatMessage(
            id: UUID().uuidString,
            isUser: false,
            text: "💡 **AI provider is not connected for generative reasoning.**\n\nTo ask deep, freeform questions across this conversation (e.g. *“\(clean)”*), connect **Google Gemini**, **OpenAI ChatGPT**, or **Ollama** in **Settings > AI**.\n\nLocal extraction is currently active for: *tasks*, *decisions*, *deadlines*, *members*, *phone numbers*, *files*, and *links*.",
            timestamp: .now,
            relatedPrompts: analysis.suggestedQuestions,
            source: .localHeuristic(engineName: "Pinggo Smart Engine")
        )
    }

    private func performDeterministicExtraction(
        question: String,
        analysis: ChatIntelligenceAnalysis,
        scoped: [PlatformMessagePreview],
        members: [AIChatMemberItem]?,
        conversationTitle: String? = nil,
        groupMemberCount: Int? = nil,
        groupSubtitle: String? = nil
    ) -> AIChatMessage? {
        let clean = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()

        // 1. Tasks / To-Dos
        if containsAny(lower, ["task", "to-do", "todo", "need to do", "pending for me", "action item"]) {
            let actions = analysis.tasks.map(stripReference)
            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: formattedList(title: "📋 Pending Tasks & Action Items", values: analysis.tasks),
                timestamp: .now,
                actionItems: actions,
                relatedPrompts: analysis.suggestedQuestions,
                source: .structuredExtraction,
                tasks: analysis.structuredTasks
            )
        }

        // 2. Decisions
        if lower.contains("decision") {
            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: formattedList(title: "⚖️ Decisions Confirmed in This Chat", values: analysis.decisions),
                timestamp: .now,
                relatedPrompts: analysis.suggestedQuestions,
                source: .structuredExtraction
            )
        }

        // 3. Dates & Deadlines
        if containsAny(lower, ["deadline", "date", "when", "schedule"]) {
            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: formattedList(title: "📅 Dates & Deadlines Mentioned", values: analysis.dates),
                timestamp: .now,
                relatedPrompts: analysis.suggestedQuestions,
                source: .structuredExtraction
            )
        }

        // 4. Unresolved Questions
        if containsAny(lower, ["unresolved", "open question", "questions pending", "waiting for response"]) {
            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: formattedList(title: "❓ Unresolved Questions", values: analysis.unresolvedQuestions),
                timestamp: .now,
                relatedPrompts: analysis.suggestedQuestions,
                source: .structuredExtraction
            )
        }

        // 5. Links
        if containsAny(lower, ["link", "url", "website"]) {
            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: formattedList(title: "🔗 Links Shared in This Conversation", values: analysis.links),
                timestamp: .now,
                relatedPrompts: analysis.suggestedQuestions,
                source: .structuredExtraction
            )
        }

        // 6. Files
        if containsAny(lower, ["file", "document", "attachment", "pdf", "figma", "deck"]) {
            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: formattedList(title: "📁 Files & Attachments Referenced", values: analysis.files),
                timestamp: .now,
                relatedPrompts: analysis.suggestedQuestions,
                source: .structuredExtraction
            )
        }

        // 7. Phone Numbers
        if containsAny(lower, ["phone", "mobile", "contact number", "call number"]) {
            let phoneItems: [AIChatPhoneNumberItem] = analysis.phoneNumbers.map { number in
                let owner = scoped.first(where: { $0.text.contains(number) })?.sender ?? "Shared contact"
                return AIChatPhoneNumberItem(name: owner, number: number, context: "Found in selected conversation")
            }
            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: formattedList(title: "📞 Phone Numbers Shared", values: analysis.phoneNumbers),
                timestamp: .now,
                phoneNumbers: phoneItems,
                relatedPrompts: analysis.suggestedQuestions,
                source: .structuredExtraction
            )
        }

        // 8. Group Members
        if containsAny(lower, ["member", "participant", "who is in", "who are in", "people in this group", "list all member", "how many member"]) {
            let available = groundedMembers(messages: scoped, metadataMembers: members)
            guard !available.isEmpty else {
                return unavailableAnswer()
            }
            let title = conversationTitle?.isEmpty == false ? conversationTitle! : (analysis.people.first ?? "Current Thread")
            let text: String
            if available.count == 1, let single = available.first {
                text = "💬 **Direct 1-on-1 Channel (\(title))**\n\nThis conversation is a direct 1-on-1 thread with **\(single.name)** (not a multi-member group).\n\n• **Participant**: **\(single.name)** — \(single.role)"
            } else {
                let countStr = groupMemberCount != nil ? "\(groupMemberCount!)" : "\(available.count)"
                text = "👥 **Group Members — \(title) (\(countStr))**\n\n" + available.map { member in
                    let phone = member.phoneNumber?.isEmpty == false ? member.phoneNumber! : "Phone unavailable"
                    return "• **\(member.name)** — \(phone) (\(member.role))"
                }.joined(separator: "\n")
            }
            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: text,
                timestamp: .now,
                members: available,
                relatedPrompts: analysis.suggestedQuestions,
                source: .structuredExtraction
            )
        }

        // 9. Zero-Hallucination CPWD Search
        if lower.contains("cpwd") {
            let cpwdMatches = scoped.filter { $0.text.localizedCaseInsensitiveContains("cpwd") }
            if cpwdMatches.isEmpty {
                return AIChatMessage(
                    id: UUID().uuidString,
                    isUser: false,
                    text: "🏢 I searched this conversation, but **could not find any CPWD-related information or guidelines** in the available chat history.",
                    timestamp: .now,
                    relatedPrompts: analysis.suggestedQuestions,
                    source: .structuredExtraction
                )
            } else {
                return AIChatMessage(
                    id: UUID().uuidString,
                    isUser: false,
                    text: formattedMessages(title: "🏢 CPWD References in This Chat", messages: cpwdMatches),
                    timestamp: .now,
                    relatedPrompts: analysis.suggestedQuestions,
                    source: .structuredExtraction
                )
            }
        }

        // 10. Dynamic Speaker Query
        let allCandidateNames = Set(scoped.map(\.sender) + (members?.map(\.name) ?? []) + analysis.people)
            .filter { !$0.isEmpty && $0.lowercased() != "you" }

        if let speaker = allCandidateNames.first(where: {
            let sLower = $0.lowercased()
            return lower.contains(sLower) || lower.contains("@\(sLower)")
        }) {
            let matches = scoped.filter { $0.sender.localizedCaseInsensitiveCompare(speaker) == .orderedSame }
            let text = matches.isEmpty
                ? "I couldn’t find messages from **\(speaker)** in this conversation."
                : formattedMessages(title: "💬 What \(speaker) said in this conversation", messages: matches)

            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: text,
                timestamp: .now,
                relatedPrompts: analysis.suggestedQuestions,
                source: .structuredExtraction
            )
        }

        // 11. Keyword Evidence Search Fallback
        let tokens = searchTokens(from: clean)
        let matches = scoped.filter { message in
            tokens.isEmpty ? false : tokens.contains { message.text.localizedCaseInsensitiveContains($0) || message.sender.localizedCaseInsensitiveContains($0) }
        }
        if !matches.isEmpty {
            return AIChatMessage(
                id: UUID().uuidString,
                isUser: false,
                text: formattedMessages(title: "Relevant conversation evidence", messages: matches),
                timestamp: .now,
                relatedPrompts: analysis.suggestedQuestions,
                source: .localHeuristic(engineName: "Pinggo Smart Engine")
            )
        }

        return nil
    }

    private func searchEvidenceFallback(question: String, scoped: [PlatformMessagePreview]) -> String {
        let tokens = searchTokens(from: question)
        let matches = scoped.filter { message in
            tokens.isEmpty ? false : tokens.contains { message.text.localizedCaseInsensitiveContains($0) || message.sender.localizedCaseInsensitiveContains($0) }
        }
        return matches.isEmpty ? unavailableText : formattedMessages(title: "Relevant conversation evidence", messages: matches)
    }

    private var unavailableText: String { "I couldn’t find that information in this conversation." }

    private func unavailableAnswer() -> AIChatMessage {
        AIChatMessage(id: UUID().uuidString, isUser: false, text: unavailableText, timestamp: .now, source: .structuredExtraction)
    }

    func groundedMembers(messages: [PlatformMessagePreview], metadataMembers: [AIChatMemberItem]?) -> [AIChatMemberItem] {
        var result: [String: AIChatMemberItem] = [:]
        for member in metadataMembers ?? [] where !member.name.isEmpty {
            result[member.name.lowercased()] = member
        }
        for sender in Set(messages.map(\.sender)) where !sender.isEmpty && sender.lowercased() != "you" {
            if result[sender.lowercased()] == nil {
                let count = messages.filter { $0.sender.localizedCaseInsensitiveCompare(sender) == .orderedSame }.count
                result[sender.lowercased()] = AIChatMemberItem(name: sender, role: "Conversation participant", activity: "Visible in selected chat", messageCount: count)
            }
        }
        return result.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func generateDynamicPrompts(
        messages: [PlatformMessagePreview],
        conversationTitle: String,
        tasks: [String] = [],
        decisions: [String] = [],
        dates: [String] = [],
        links: [String] = [],
        files: [String] = [],
        phones: [String] = [],
        topics: [String] = [],
        people: [String] = []
    ) -> [String] {
        let title = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? "this sender" : title
        var prompts: [String] = []

        let combinedText = messages.map(\.text).joined(separator: "\n").lowercased()

        // 1. Verification codes / OTP / Security PIN
        if combinedText.contains("otp") || combinedText.contains("verification code") || combinedText.contains("security code") || combinedText.contains("one time password") || combinedText.contains("login code") || combinedText.contains("pin ") || combinedText.contains(" pin") {
            prompts.append("What is the verification code / OTP?")
            prompts.append("When does this code or link expire?")
        }

        // 2. Financial / Payments / Invoices / Billing
        if combinedText.contains("$") || combinedText.contains("₹") || combinedText.contains("rs.") || combinedText.contains("inr") || combinedText.contains("usd") || combinedText.contains("eur") || combinedText.contains("payment") || combinedText.contains("invoice") || combinedText.contains("paid") || combinedText.contains("bill") || combinedText.contains("refund") || combinedText.contains("due date") {
            prompts.append("What is the payment amount or bill status?")
            prompts.append("What payment instructions were given?")
        }

        // 3. Deadlines & Dates
        if !dates.isEmpty {
            if let firstDate = dates.first {
                prompts.append("What is scheduled for \(firstDate)?")
            } else {
                prompts.append("What deadlines or dates were mentioned?")
            }
        }

        // 4. Questions / Inquiries asked by the sender
        let questionsFromSender = messages.filter { $0.sender.lowercased() != "you" && $0.text.contains("?") }
        if !questionsFromSender.isEmpty {
            prompts.append("What did \(displayTitle) ask?")
            prompts.append("Draft a reply to \(displayTitle)")
        }

        // 5. Action items & Tasks
        if !tasks.isEmpty {
            prompts.append("What action items are required from me?")
        }

        // 6. Tender / Government / Notice keywords (like eProc)
        if combinedText.contains("tender") || combinedText.contains("bid") || combinedText.contains("eproc") || combinedText.contains("notice") || combinedText.contains("cpwd") {
            prompts.append("What are the tender / notice requirements?")
        }

        // 7. Delivery / Orders / Tracking
        if combinedText.contains("order") || combinedText.contains("tracking") || combinedText.contains("deliver") || combinedText.contains("shipment") || combinedText.contains("courier") {
            prompts.append("What is the order or delivery status?")
            prompts.append("What is the tracking number?")
        }

        // 8. Shared Links
        if !links.isEmpty {
            prompts.append("Show all links shared in this chat")
        }

        // 9. Shared Files
        if !files.isEmpty {
            prompts.append("List files or attachments referenced")
        }

        // 10. Decisions
        if !decisions.isEmpty {
            prompts.append("What was decided in this conversation?")
        }

        // 11. Phone Numbers
        if !phones.isEmpty {
            prompts.append("List phone numbers shared here")
        }

        // 12. Topics from conversation
        for topic in topics.prefix(2) {
            let q = "What was discussed regarding \(topic)?"
            if !prompts.contains(q) {
                prompts.append(q)
            }
        }

        // 13. Sender-specific fallbacks (when messages are short or simple notifications)
        if prompts.isEmpty {
            if messages.count <= 1 {
                prompts.append("Summarize this message from \(displayTitle)")
                prompts.append("What action does \(displayTitle) expect?")
            } else {
                prompts.append("Summarize recent messages from \(displayTitle)")
                prompts.append("What are the key points in this chat?")
            }
        } else if prompts.count < 3 {
            prompts.append("Summarize recent messages from \(displayTitle)")
        }

        var unique: [String] = []
        for p in prompts {
            if !unique.contains(p) {
                unique.append(p)
            }
        }
        return Array(unique.prefix(6))
    }

    func generateContextualPrompts(
        messages: [PlatformMessagePreview],
        conversationTitle: String,
        preferences: AppPreferences? = nil
    ) async -> [String] {
        let scoped = Array(messages.suffix(25))
        guard !scoped.isEmpty else {
            return generateDynamicPrompts(messages: scoped, conversationTitle: conversationTitle)
        }

        let prefs = preferences ?? AppPreferences()
        let res = AIProviderResolver.resolve(preferences: prefs)

        guard res.canPerformGenerativeAI else {
            return generateDynamicPrompts(messages: scoped, conversationTitle: conversationTitle)
        }

        let transcript = scoped.map { msg in
            let sender = msg.sender.isEmpty ? "Unknown" : msg.sender
            let time = msg.time?.isEmpty == false ? " [\(msg.time!)]" : ""
            return "\(sender)\(time): \(msg.text)"
        }.joined(separator: "\n")

        let sysPrompt = """
        You are Pinggo AI's conversation suggestion assistant.
        Analyze the provided chat transcript and generate 3 to 5 concise, highly relevant suggested questions that the user might want to ask about this specific chat.

        CRITICAL RULES:
        1. Every question MUST directly relate to the specific content, entities, requests, codes, or actions in this conversation.
        2. NEVER suggest generic template questions like "What is the project status?", "What do I need to do today?", "What decisions were made?", "Which files need review?", or "What changed since yesterday?" unless they are explicitly discussed in the chat.
        3. If the chat is a single alert, notification, or OTP (e.g. from a service or bank), ask specifically about that notification or code (e.g., "What is the verification code?", "When does this expire?", "What action is required?").
        4. If a person asked a question, suggest how to reply or what was asked.
        5. Keep each question brief (under 50 characters).
        6. Format: Output ONLY the questions, each on a new line starting with a dash (- ). No introductory text, no explanations, no conversational commentary.
        """

        let userPrompt = """
        Conversation with: \(conversationTitle)
        Transcript (\(scoped.count) messages):
        \(transcript)

        Suggested questions:
        """

        do {
            let rawText: String
            switch res.provider {
            case .gemini:
                rawText = try await AIService.shared.callGeminiAPI(apiKey: prefs.geminiApiKey, model: res.model, prompt: userPrompt, systemInstruction: sysPrompt)
            case .chatgpt:
                rawText = try await AIService.shared.callOpenAIAPI(apiKey: prefs.openAiApiKey, model: res.model, prompt: userPrompt, systemInstruction: sysPrompt)
            case .ollama:
                rawText = try await AIService.shared.callOllamaAPI(endpoint: prefs.ollamaEndpoint, model: res.model, prompt: userPrompt, systemInstruction: sysPrompt)
            default:
                rawText = ""
            }

            let lines = rawText.components(separatedBy: .newlines)
                .map { line -> String in
                    var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.hasPrefix("-") || cleaned.hasPrefix("•") || cleaned.hasPrefix("*") {
                        cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if let firstDot = cleaned.firstIndex(of: "."), cleaned.prefix(upTo: firstDot).allSatisfy({ $0.isNumber }) {
                        cleaned = String(cleaned[cleaned.index(after: firstDot)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return cleaned
                }
                .filter { line in
                    !line.isEmpty && line.count > 5 && line.count < 90 && !line.lowercased().starts(with: "here are") && !line.lowercased().starts(with: "suggested")
                }

            if lines.count >= 2 {
                return Array(lines.prefix(6))
            }
        } catch {
            // Generative call failed; fall through to dynamic heuristics
        }

        return generateDynamicPrompts(messages: scoped, conversationTitle: conversationTitle)
    }

    private func formattedList(title: String, values: [String]) -> String {
        guard !values.isEmpty else { return unavailableText }
        return "\(title)\n\n" + values.prefix(20).map { "• \($0)" }.joined(separator: "\n")
    }

    private func formattedMessages(title: String, messages: [PlatformMessagePreview]) -> String {
        guard !messages.isEmpty else { return unavailableText }
        let body = messages.suffix(8).map { message in
            "• \(compact(message.text))\n  Source: \(sourceLabel(for: message, in: messages))"
        }.joined(separator: "\n")
        return "\(title)\n\n\(body)"
    }

    private func sourceLabel(for message: PlatformMessagePreview, in messages: [PlatformMessagePreview]) -> String {
        if let time = message.time, !time.isEmpty { return "\(message.sender) · \(time)" }
        let index = messages.firstIndex(where: { $0.id == message.id }).map { $0 + 1 } ?? 1
        return "\(message.sender) · Message \(index)"
    }

    private func compact(_ text: String, limit: Int = 150) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.count > limit ? String(clean.prefix(limit)) + "…" : clean
    }

    private func stripReference(_ value: String) -> String {
        value.components(separatedBy: " — ").first ?? value
    }

    private func containsAny(_ text: String, _ terms: [String]) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func appendUnique(_ value: String, to values: inout [String]) {
        guard !value.isEmpty, !values.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { return }
        values.append(value)
    }

    private func extractMatches(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private func searchTokens(from query: String) -> [String] {
        query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }
}
