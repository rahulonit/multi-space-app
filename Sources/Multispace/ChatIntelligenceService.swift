import Foundation

struct ChatIntelligenceSource: Identifiable, Equatable {
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

struct ChatIntelligenceAnalysis: Equatable {
    let conversationID: String
    let messageCount: Int
    let summary: [String]
    let topics: [String]
    let decisions: [String]
    let tasks: [String]
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
    static let maximumMessages = 100

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
        var dates: [String] = []
        var questions: [String] = []
        var phones: [String] = []
        var emails: [String] = []
        var links: [String] = []
        var files: [String] = []
        var wordCounts: [String: Int] = [:]

        for message in scoped {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()
            let referenced = "\(compact(text)) — \(sourceLabel(for: message, in: scoped))"

            if containsAny(lower, ["decided", "agreed", "approved", "confirmed", "we'll proceed", "will proceed", "final decision"]) {
                appendUnique(referenced, to: &decisions)
            }
            if containsAny(lower, ["need to", "needs to", "please ", "todo", "to-do", "action item", "must ", "should ", "will send", "will update", "follow up", "deadline"]) {
                appendUnique(referenced, to: &tasks)
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

        var suggestions: [String] = []
        if !tasks.isEmpty { suggestions.append("What tasks are pending for me?") }
        if !decisions.isEmpty { suggestions.append("What decisions were made?") }
        if !dates.isEmpty { suggestions.append("What deadlines or dates were mentioned?") }
        if !questions.isEmpty { suggestions.append("Summarize unresolved questions.") }
        if !links.isEmpty { suggestions.append("Show all links shared in this chat.") }
        if !phones.isEmpty { suggestions.append("List all phone numbers shared in this conversation.") }
        if people.count > 1 { suggestions.append("List all members in this group.") }
        if let frequent = people.first { suggestions.append("What is \(frequent) saying in this conversation?") }

        return ChatIntelligenceAnalysis(
            conversationID: conversationID,
            messageCount: scoped.count,
            summary: Array(summary.prefix(5)),
            topics: Array(topics),
            decisions: Array(decisions.prefix(8)),
            tasks: Array(tasks.prefix(12)),
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
        members: [AIChatMemberItem]?
    ) -> AIChatMessage {
        let scoped = Array(messages.suffix(Self.maximumMessages))
        let lower = question.lowercased()
        var text: String
        var actions: [String]? = nil
        var phoneItems: [AIChatPhoneNumberItem]? = nil
        var memberItems: [AIChatMemberItem]? = nil

        if containsAny(lower, ["task", "to-do", "todo", "need to do", "pending for me", "action item"]) {
            text = formattedList(title: "Pending tasks", values: analysis.tasks)
            actions = analysis.tasks.map(stripReference)
        } else if lower.contains("decision") {
            text = formattedList(title: "Decisions found", values: analysis.decisions)
        } else if containsAny(lower, ["deadline", "date", "when"]) {
            text = formattedList(title: "Dates and deadlines mentioned", values: analysis.dates)
        } else if containsAny(lower, ["unresolved", "open question", "questions pending"]) {
            text = formattedList(title: "Unresolved questions", values: analysis.unresolvedQuestions)
        } else if containsAny(lower, ["link", "url"]) {
            text = formattedList(title: "Links shared", values: analysis.links)
        } else if containsAny(lower, ["file", "document", "attachment"]) {
            text = formattedList(title: "Files mentioned", values: analysis.files)
        } else if containsAny(lower, ["phone", "mobile", "contact number"]) {
            text = formattedList(title: "Phone numbers shared in this conversation", values: analysis.phoneNumbers)
            phoneItems = analysis.phoneNumbers.map { number in
                let owner = scoped.first(where: { $0.text.contains(number) })?.sender ?? "Shared contact"
                return AIChatPhoneNumberItem(name: owner, number: number, context: "Found in selected conversation")
            }
        } else if containsAny(lower, ["member", "participant", "who is in", "people in this group"]) {
            let available = groundedMembers(messages: scoped, metadataMembers: members)
            memberItems = available
            guard !available.isEmpty else {
                return unavailableAnswer()
            }
            text = "Group Members\n\n" + available.map { member in
                let phone = member.phoneNumber?.isEmpty == false ? member.phoneNumber! : "Phone number unavailable"
                return "• \(member.name) — \(phone)"
            }.joined(separator: "\n")
        } else if let speaker = analysis.people.first(where: { lower.contains($0.lowercased()) }) {
            let matches = scoped.filter { $0.sender.localizedCaseInsensitiveCompare(speaker) == .orderedSame }
            text = matches.isEmpty ? unavailableText : formattedMessages(title: "What \(speaker) said", messages: matches)
        } else {
            let tokens = searchTokens(from: question)
            let matches = scoped.filter { message in
                tokens.isEmpty ? false : tokens.contains { message.text.localizedCaseInsensitiveContains($0) || message.sender.localizedCaseInsensitiveContains($0) }
            }
            text = matches.isEmpty ? unavailableText : formattedMessages(title: "Relevant conversation evidence", messages: matches)
        }

        return AIChatMessage(
            id: UUID().uuidString,
            isUser: false,
            text: text,
            timestamp: .now,
            actionItems: actions,
            phoneNumbers: phoneItems,
            members: memberItems,
            relatedPrompts: analysis.suggestedQuestions
        )
    }

    private var unavailableText: String { "I couldn’t find that information in this conversation." }

    private func unavailableAnswer() -> AIChatMessage {
        AIChatMessage(id: UUID().uuidString, isUser: false, text: unavailableText, timestamp: .now)
    }

    private func groundedMembers(messages: [PlatformMessagePreview], metadataMembers: [AIChatMemberItem]?) -> [AIChatMemberItem] {
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
