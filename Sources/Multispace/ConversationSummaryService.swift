import Foundation

enum SummaryUrgency: String, Codable, CaseIterable {
    case high = "High Priority"
    case medium = "Needs Attention"
    case normal = "Informational"
    case caughtUp = "All Caught Up"
}

struct ThreadBriefing: Identifiable, Codable, Equatable {
    var id: String { sender }
    let sender: String
    let messageCount: Int
    let detectedIntent: String
    let detectedQuestion: String?
    let actionItem: String?
    let contextSummary: String
    let suggestedReplies: [String]
    let urgency: SummaryUrgency
    let latestTime: String?

    init(
        sender: String,
        messageCount: Int,
        detectedIntent: String,
        detectedQuestion: String?,
        actionItem: String?,
        contextSummary: String,
        suggestedReplies: [String],
        urgency: SummaryUrgency,
        latestTime: String?
    ) {
        self.sender = sender
        self.messageCount = messageCount
        self.detectedIntent = detectedIntent
        self.detectedQuestion = detectedQuestion
        self.actionItem = actionItem
        self.contextSummary = contextSummary
        self.suggestedReplies = suggestedReplies
        self.urgency = urgency
        self.latestTime = latestTime
    }
}

struct PlatformConversationSummary: Identifiable, Codable, Equatable {
    var id: String { platformID }
    let platformID: String
    let platformName: String
    let accountName: String
    let totalConversations: Int
    let unreadCount: Int
    let activeSendersCount: Int
    let questionsCount: Int
    let headline: String
    let executiveOverview: String
    let threads: [ThreadBriefing]
    let bulletPoints: [String]
    let actionItems: [String]
    let keyTopics: [String]
    let urgency: SummaryUrgency
    let generatedAt: Date

    init(
        platformID: String,
        platformName: String,
        accountName: String,
        totalConversations: Int,
        unreadCount: Int,
        activeSendersCount: Int,
        questionsCount: Int,
        headline: String,
        executiveOverview: String,
        threads: [ThreadBriefing],
        bulletPoints: [String],
        actionItems: [String],
        keyTopics: [String],
        urgency: SummaryUrgency,
        generatedAt: Date = .now
    ) {
        self.platformID = platformID
        self.platformName = platformName
        self.accountName = accountName
        self.totalConversations = totalConversations
        self.unreadCount = unreadCount
        self.activeSendersCount = activeSendersCount
        self.questionsCount = questionsCount
        self.headline = headline
        self.executiveOverview = executiveOverview
        self.threads = threads
        self.bulletPoints = bulletPoints
        self.actionItems = actionItems
        self.keyTopics = keyTopics
        self.urgency = urgency
        self.generatedAt = generatedAt
    }
}

struct ConversationMessageSummary: Equatable {
    let sender: String
    let contextSummary: String
    let detectedIntent: String
    let detectedQuestion: String?
    let actionItem: String?
    let suggestedReplies: [String]
    let urgency: SummaryUrgency

    init(
        sender: String,
        contextSummary: String,
        detectedIntent: String,
        detectedQuestion: String?,
        actionItem: String?,
        suggestedReplies: [String],
        urgency: SummaryUrgency
    ) {
        self.sender = sender
        self.contextSummary = contextSummary
        self.detectedIntent = detectedIntent
        self.detectedQuestion = detectedQuestion
        self.actionItem = actionItem
        self.suggestedReplies = suggestedReplies
        self.urgency = urgency
    }
}

@MainActor
final class ConversationSummaryService {
    static let shared = ConversationSummaryService()

    private init() {}

    // MARK: - Single Message Analysis
    func analyzeMessage(_ message: PlatformMessagePreview) -> ConversationMessageSummary {
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        var intent = "General Update"
        var urgency: SummaryUrgency = .normal
        var actionItem: String? = nil
        var contextSummary = ""
        var replies: [String] = []

        // 1. Detect Explicit Questions
        let detectedQuestion: String? = {
            if text.contains("?") {
                let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!\n"))
                if let questionSentence = sentences.first(where: { $0.contains("?") }) {
                    return questionSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if lower.contains("when can") || lower.contains("could you") || lower.contains("can you") ||
                      lower.contains("let me know if") || lower.contains("what do you think") {
                return text
            }
            return nil
        }()

        // 2. Classify Intent & Synthesize Meaningful Context
        if lower.contains("meet") || lower.contains("meeting") || lower.contains("call") ||
           lower.contains("sync") || lower.contains("zoom") || lower.contains("calendar") ||
           lower.contains("schedule") || lower.contains("chat this week") {
            intent = "📅 Meeting Request"
            urgency = .medium
            contextSummary = "\(message.sender) proposed an intro/sync call to connect."
            actionItem = "Reply to \(message.sender) with your available times"
            replies = [
                "Sounds great! How does tomorrow at 2 PM work for you?",
                "Could you send an agenda first?",
                "I'm fully booked this week, but let's connect next week."
            ]
        } else if lower.contains("review") || lower.contains("please check") || lower.contains("feedback") ||
                  lower.contains("take a look") || lower.contains("draft") || lower.contains("attached") ||
                  lower.contains("deck") || lower.contains("slides") || lower.contains("document") {
            intent = "📝 Review & Feedback"
            urgency = .medium
            contextSummary = "\(message.sender) shared materials requesting your review and feedback."
            actionItem = "Review materials from \(message.sender) and send feedback"
            replies = [
                "Taking a look now, will send my notes shortly.",
                "Looks great to me, proceed with this draft!",
                "Thanks for sending! Will review by end of day."
            ]
        } else if lower.contains("urgent") || lower.contains("asap") || lower.contains("immediately") ||
                  lower.contains("critical") || lower.contains("emergency") || lower.contains("blocked") ||
                  lower.contains("today eod") {
            intent = "🚨 Urgent Request"
            urgency = .high
            contextSummary = "\(message.sender) flagged an urgent inquiry requiring quick turnaround."
            actionItem = "Respond urgently to \(message.sender)"
            replies = [
                "On it right now! Will update you in 15 minutes.",
                "Looking into this immediately.",
                "Just sent over the required items."
            ]
        } else if lower.contains("proposal") || lower.contains("partnership") || lower.contains("collab") ||
                  lower.contains("pricing") || lower.contains("invoice") || lower.contains("contract") ||
                  lower.contains("quote") || lower.contains("offer") {
            intent = "🤝 Business Opportunity"
            urgency = .medium
            contextSummary = "\(message.sender) reached out regarding a commercial proposal or partnership."
            actionItem = "Evaluate proposal details from \(message.sender)"
            replies = [
                "Happy to explore this. Could you share a brief outline?",
                "Received the details, our team is reviewing.",
                "Let's schedule a 15-minute call to discuss."
            ]
        } else if lower.contains("bug") || lower.contains("issue") || lower.contains("release") ||
                  lower.contains("deploy") || lower.contains("launch") || lower.contains("live") ||
                  lower.contains("error") || lower.contains("fixed") {
            intent = "🚀 Product / Tech Update"
            urgency = .normal
            contextSummary = "\(message.sender) shared a technical status update regarding releases or issues."
            if detectedQuestion != nil {
                actionItem = "Answer technical question from \(message.sender)"
            }
            replies = [
                "Thanks for the update! Glad to hear this is resolved.",
                "Acknowledged. Monitoring the deployment closely.",
                "Can you share the logs or error traceback?"
            ]
        } else {
            // General conversation / Inquiry
            if detectedQuestion != nil {
                intent = "❓ Question / Inquiry"
                urgency = .medium
                contextSummary = "\(message.sender) asked a direct question needing response."
                actionItem = "Answer \(message.sender)'s question"
                replies = [
                    "Thanks for reaching out! Let me check and get back to you.",
                    "Yes, that sounds good to proceed.",
                    "No problem, happy to help with this."
                ]
            } else {
                intent = "💬 Message / Check-in"
                urgency = .normal
                contextSummary = "\(message.sender) sent a chat message or update."
                replies = [
                    "Thanks for the note!",
                    "Appreciate the check-in, hope you're having a good week!",
                    "Received, will keep you posted."
                ]
            }
        }

        return ConversationMessageSummary(
            sender: message.sender,
            contextSummary: contextSummary,
            detectedIntent: intent,
            detectedQuestion: detectedQuestion,
            actionItem: actionItem,
            suggestedReplies: replies,
            urgency: urgency
        )
    }

    // MARK: - Platform Summary Generation
    func generateSummary(
        for platform: SocialPlatform,
        accounts: [PlatformAccount],
        messages: [PlatformMessagePreview],
        unreadCount: Int
    ) -> PlatformConversationSummary {
        let accountNames = accounts.map(\.name).joined(separator: ", ")

        if messages.isEmpty {
            return PlatformConversationSummary(
                platformID: platform.id,
                platformName: platform.name,
                accountName: accountNames.isEmpty ? "Connected" : accountNames,
                totalConversations: 0,
                unreadCount: unreadCount,
                activeSendersCount: 0,
                questionsCount: 0,
                headline: unreadCount > 0
                    ? "\(unreadCount) unread alert\(unreadCount == 1 ? "" : "s") on \(platform.name)"
                    : "\(platform.name) is all caught up",
                executiveOverview: "Portal session is active with no new incoming messages. All conversations are up to date.",
                threads: [],
                bulletPoints: [
                    "No pending threads or follow-ups detected.",
                    "Live portal is actively monitoring for incoming messages."
                ],
                actionItems: unreadCount > 0 ? ["Check unread notifications in \(platform.name)"] : [],
                keyTopics: ["Sync Ready"],
                urgency: unreadCount > 0 ? .medium : .caughtUp
            )
        }

        // Group messages by sender (normalized)
        var senderGroups: [String: [PlatformMessagePreview]] = [:]
        for msg in messages {
            let key = msg.sender.trimmingCharacters(in: .whitespacesAndNewlines)
            senderGroups[key, default: []].append(msg)
        }

        var threads: [ThreadBriefing] = []
        var allActions: [String] = []
        var topicSet = Set<String>()
        var questionsCount = 0
        var highestUrgency: SummaryUrgency = unreadCount > 0 ? .medium : .normal

        for (sender, msgs) in senderGroups {
            guard let latest = msgs.first else { continue }
            let analysis = analyzeMessage(latest)
            topicSet.insert(analysis.detectedIntent)

            if analysis.urgency == .high {
                highestUrgency = .high
            } else if analysis.urgency == .medium && highestUrgency != .high {
                highestUrgency = .medium
            }

            if analysis.detectedQuestion != nil {
                questionsCount += 1
            }

            if let action = analysis.actionItem, !allActions.contains(action) {
                allActions.append(action)
            }

            let thread = ThreadBriefing(
                sender: sender,
                messageCount: msgs.count,
                detectedIntent: analysis.detectedIntent,
                detectedQuestion: analysis.detectedQuestion,
                actionItem: analysis.actionItem,
                contextSummary: analysis.contextSummary,
                suggestedReplies: analysis.suggestedReplies,
                urgency: analysis.urgency,
                latestTime: latest.time
            )
            threads.append(thread)
        }

        // Sort threads: High urgency first, then medium, then normal
        threads.sort { a, b in
            if a.urgency == .high && b.urgency != .high { return true }
            if a.urgency == .medium && b.urgency == .normal { return true }
            return a.messageCount > b.messageCount
        }

        // Generate Human-Readable Bullet Points from Thread Briefings
        var bullets: [String] = []
        for thread in threads.prefix(5) {
            let detail: String
            if let q = thread.detectedQuestion {
                detail = "\(thread.contextSummary) Asked: \"\(q.prefix(70))\(q.count > 70 ? "…" : "")\""
            } else {
                detail = thread.contextSummary
            }
            bullets.append("\(thread.sender) (\(thread.detectedIntent)): \(detail)")
        }

        // Executive Overview Sentence
        let activeCount = senderGroups.count
        let executiveOverview: String
        if !allActions.isEmpty {
            let names = threads.prefix(2).map(\.sender).joined(separator: " and ")
            executiveOverview = "Across \(activeCount) active contact\(activeCount == 1 ? "" : "s") on \(platform.name), \(allActions.count) item\(allActions.count == 1 ? "" : "s") require attention (including \(names)). \(questionsCount > 0 ? "\(questionsCount) question\(questionsCount == 1 ? "" : "s") awaiting reply." : "")"
        } else if unreadCount > 0 {
            executiveOverview = "\(unreadCount) unread alert\(unreadCount == 1 ? "" : "s") on \(platform.name) across \(activeCount) discussion thread\(activeCount == 1 ? "" : "s"). All recent messages reviewed."
        } else {
            executiveOverview = "\(activeCount) active discussion thread\(activeCount == 1 ? "" : "s") on \(platform.name). All conversations are reviewed and up to date."
        }

        // Headline
        let headline: String
        if !allActions.isEmpty {
            headline = "\(activeCount) contact\(activeCount == 1 ? "" : "s") · \(allActions.count) action\(allActions.count == 1 ? "" : "s") required"
        } else if unreadCount > 0 {
            headline = "\(unreadCount) unread message\(unreadCount == 1 ? "" : "s") across \(activeCount) chat\(activeCount == 1 ? "" : "s")"
        } else {
            headline = "\(activeCount) active contact\(activeCount == 1 ? "" : "s") · All caught up"
        }

        let topics = Array(topicSet.prefix(4)).sorted()

        return PlatformConversationSummary(
            platformID: platform.id,
            platformName: platform.name,
            accountName: accountNames.isEmpty ? "Connected" : accountNames,
            totalConversations: messages.count,
            unreadCount: unreadCount,
            activeSendersCount: activeCount,
            questionsCount: questionsCount,
            headline: headline,
            executiveOverview: executiveOverview,
            threads: threads,
            bulletPoints: bullets,
            actionItems: Array(allActions.prefix(4)),
            keyTopics: topics.isEmpty ? ["Messages"] : topics,
            urgency: highestUrgency
        )
    }

    // MARK: - Executive Cross-Platform Briefing
    func generateExecutiveBriefing(
        platforms: [SocialPlatform],
        accounts: [PlatformAccount],
        activity: [UUID: PlatformActivitySnapshot]
    ) -> PlatformConversationSummary {
        var totalMsgs = 0
        var totalUnread = 0
        var totalQuestions = 0
        var allActions: [String] = []
        var allBullets: [String] = []
        var allThreads: [ThreadBriefing] = []
        var topicSet = Set<String>()
        var platformSummariesList: [PlatformConversationSummary] = []

        for platform in platforms {
            let platformAccounts = accounts.filter { $0.platformID == platform.id }
            var platformMsgs: [PlatformMessagePreview] = []
            var platformUnread = 0

            for acc in platformAccounts {
                if let snap = activity[acc.id] {
                    platformMsgs.append(contentsOf: snap.messages)
                    platformUnread += snap.unreadCount ?? 0
                }
            }

            totalMsgs += platformMsgs.count
            totalUnread += platformUnread

            if !platformMsgs.isEmpty {
                let pSummary = generateSummary(
                    for: platform,
                    accounts: platformAccounts,
                    messages: platformMsgs,
                    unreadCount: platformUnread
                )
                platformSummariesList.append(pSummary)
                totalQuestions += pSummary.questionsCount
                allActions.append(contentsOf: pSummary.actionItems)
                allThreads.append(contentsOf: pSummary.threads)
                topicSet.formUnion(pSummary.keyTopics)
                if let topBullet = pSummary.bulletPoints.first {
                    allBullets.append("[\(platform.name)] \(topBullet)")
                }
            }
        }

        let totalSenders = allThreads.count
        let urgency: SummaryUrgency = !allActions.isEmpty ? .medium : (totalUnread > 0 ? .medium : .caughtUp)

        let headline = totalMsgs > 0
            ? "\(totalSenders) active contact\(totalSenders == 1 ? "" : "s") across \(platforms.count) platforms · \(allActions.count) action\(allActions.count == 1 ? "" : "s")"
            : "All inboxes clear across \(platforms.count) connected platforms"

        let executiveOverview = totalMsgs > 0
            ? "Unified briefing: \(totalSenders) active discussion thread\(totalSenders == 1 ? "" : "s") across \(platforms.count) platforms. \(allActions.count) actionable follow-up\(allActions.count == 1 ? "" : "s") detected\(totalQuestions > 0 ? ", with \(totalQuestions) question\(totalQuestions == 1 ? "" : "s") needing response." : ".")"
            : "No pending messages or action items across any connected platforms. You are completely caught up!"

        return PlatformConversationSummary(
            platformID: "all",
            platformName: "All Inboxes",
            accountName: "\(accounts.count) accounts",
            totalConversations: totalMsgs,
            unreadCount: totalUnread,
            activeSendersCount: totalSenders,
            questionsCount: totalQuestions,
            headline: headline,
            executiveOverview: executiveOverview,
            threads: allThreads,
            bulletPoints: Array(allBullets.prefix(5)),
            actionItems: Array(allActions.prefix(5)),
            keyTopics: Array(topicSet.prefix(5)),
            urgency: urgency
        )
    }
}
