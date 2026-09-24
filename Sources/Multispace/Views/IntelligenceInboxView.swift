import SwiftUI

// MARK: - Models for Scoped Conversation Overview
private struct IntelligenceConversation: Identifiable, Hashable {
    let id: String
    let accountID: UUID?
    let platform: SocialPlatform?
    let sender: String
    let preview: String
    let time: String
    let unread: Int
    let priority: String
    let messages: [PlatformMessagePreview]
    let isPreview: Bool
}

private struct IntelligenceAuditEntry: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let time = Date()
}

private enum InboxFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unread = "Unread"
    case priority = "Priority"
    case needsReply = "Needs Reply"
    case aiHighPriority = "AI High Priority"

    var id: String { rawValue }
}

private enum SummaryDisplayMode: String, CaseIterable, Identifiable {
    case focus = "Important"
    case details = "All details"

    var id: String { rawValue }
}

private struct AIChatHistoryItem: Identifiable, Hashable {
    let id: String = UUID().uuidString
    let question: String
    let answer: String
    let origin: String
    let timestamp: Date = Date()
    let sourceMessageId: String?
}

private struct IntelligencePermissionScope {
    var messages = true
    var participants = true
    var links = true
    var attachments = true
    var metadata = true
    var voiceTranscripts = false
    var draftReplies = true
    var sendMessages = false
    var createTasks = true
    var createReminders = true
    var calendarEvents = false
}

// MARK: - Intelligence Inbox View
struct IntelligenceInboxView: View {
    @EnvironmentObject private var store: AppStore

    // Selection & Filter State
    @State private var selectedID: String?
    @State private var searchText: String = ""
    @State private var selectedFilter: InboxFilter = .all
    @State private var centerTab: ConversationNavTab = .summary
    @State private var aiTab: AIPanelTab = .ask
    @State private var aiTasksSubFilter: String = "All"
    @State private var showAllPrompts: Bool = false
    @State private var summaryDisplayMode: SummaryDisplayMode = .focus

    // Context & Thread Q&A Isolation State
    @State private var activeConversationContexts: [String: ConversationContext] = [:]
    @State private var chatHistory: [String: [AIChatHistoryItem]] = [:]
    @State private var activeTaskId: UUID? = nil

    // AI & Input State
    @State private var question: String = ""
    @State private var answer: String?
    @State private var answerOrigin: String?
    @State private var isThinking: Bool = false
    @State private var showAccess: Bool = false
    @State private var permissionScope = IntelligencePermissionScope()
    @State private var pendingExternalAction: String?
    @State private var audits: [IntelligenceAuditEntry] = []
    @State private var completedTaskIDs: Set<String> = []
    @State private var openQuestions: [String] = [
        "What is the final cut-off time for the staging deployment?",
        "Has the stakeholder approval sign-off been received?"
    ]

    // MARK: - Conversations Data
    private var conversations: [IntelligenceConversation] {
        let live = store.platformAccounts.flatMap { account -> [IntelligenceConversation] in
            guard let platform = store.platform(account.platformID),
                  let snapshot = store.platformActivity[account.id] else { return [] }
            let grouped = Dictionary(grouping: snapshot.messages, by: \.sender)
            return grouped.compactMap { sender, messages in
                guard let latest = messages.first else { return nil }
                let unreadCount = messages.filter(\.unread).count
                let priority: String = {
                    if unreadCount > 2 { return "🔥 Urgent" }
                    if latest.text.lowercased().contains("review") || latest.text.lowercased().contains("plan") { return "📝 Task" }
                    if latest.text.contains("?") { return "❓ Needs Reply" }
                    return "Normal"
                }()
                return IntelligenceConversation(
                    id: "\(account.id)-\(sender)",
                    accountID: account.id,
                    platform: platform,
                    sender: sender,
                    preview: latest.text,
                    time: latest.time ?? "Recent",
                    unread: unreadCount,
                    priority: priority,
                    messages: messages,
                    isPreview: false
                )
            }
        }
        return live.isEmpty ? previewConversations : live.sorted { $0.unread > $1.unread }
    }

    private var filteredConversations: [IntelligenceConversation] {
        var list = conversations

        // Filter chips
        switch selectedFilter {
        case .all:
            break
        case .unread:
            list = list.filter { $0.unread > 0 }
        case .priority:
            list = list.filter { $0.priority.contains("Urgent") || $0.priority.contains("Task") }
        case .needsReply:
            list = list.filter { $0.priority.contains("Needs Reply") || $0.unread > 0 }
        case .aiHighPriority:
            list = list.filter { $0.priority.contains("Urgent") }
        }

        // Search text
        guard !searchText.isEmpty else { return list }
        return list.filter {
            $0.sender.localizedCaseInsensitiveContains(searchText) ||
            $0.preview.localizedCaseInsensitiveContains(searchText) ||
            ($0.platform?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var selected: IntelligenceConversation {
        conversations.first(where: { $0.id == selectedID }) ?? conversations.first ?? previewConversations[0]
    }

    private var selectedSummary: PlatformConversationSummary? {
        if let platform = selected.platform { return store.platformSummaries[platform.id] }
        return store.platformSummaries["all"]
    }

    private var currentContext: ConversationContext {
        let conv = selected
        if let existing = activeConversationContexts[conv.id] {
            var updated = existing
            updated.tasks = updated.tasks.map { t in
                var task = t
                task.isDone = task.isDone || completedTaskIDs.contains(t.id)
                return task
            }
            return updated
        }
        return buildInitialContext(for: conv)
    }

    private var aiResolution: AIProviderResolution {
        AIProviderResolver.resolve(preferences: store.preferences)
    }

    private var aiStatusColor: Color {
        aiResolution.canPerformGenerativeAI ? .green : .orange
    }

    private var aiProcessingLabel: String {
        guard aiResolution.canPerformGenerativeAI else { return "Local" }
        switch aiResolution.provider {
        case .chatgpt: return "OpenAI"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        case .smart: return "Local"
        }
    }

    private func buildInitialContext(for conv: IntelligenceConversation) -> ConversationContext {
        if !conv.isPreview {
            return buildGroundedContext(for: conv)
        }

        let title = conv.sender
        let prefix = conv.id

        let initialSummary: String = {
            if !conv.messages.isEmpty, let firstText = conv.messages.first?.text {
                let snippet = firstText.count > 80 ? String(firstText.prefix(80)) + "..." : firstText
                return "The team is actively coordinating in \(title). Recent discussion centers on: \"\(snippet)\". Key milestones, verification items, and action items are tracked locally under authorized scope."
            }
            return "The team is actively coordinating in \(title) on deliverables, milestone verification, and operational readiness. All recent decisions and open tasks are tracked locally under authorized scope."
        }()

        let initialDecisions: [ProjectDecisionItem] = [
            ProjectDecisionItem(id: "\(prefix)-dec-1", text: "Adopt standardized milestone schedule for \(title)", status: "Approved", certainty: .confirmed, source: "\(title) Lead", sourceMessageId: "msg-1", timeString: "Today 4:15 PM"),
            ProjectDecisionItem(id: "\(prefix)-dec-2", text: "Proceed with updated deliverables checklist", status: "Approved", certainty: .confirmed, source: "Review Team", sourceMessageId: "msg-2", timeString: "Today 2:30 PM"),
            ProjectDecisionItem(id: "\(prefix)-dec-3", text: "Finalize compliance and verification notes prior to release", status: "Pending Confirmation", certainty: .tentative, source: "Operations Team", sourceMessageId: "msg-3", timeString: "Yesterday")
        ]

        let initialTasks: [ProjectTaskItem] = [
            ProjectTaskItem(id: "\(prefix)-task-1", title: "Confirm timeline before staging freeze in \(title)", owner: "Project Lead", dueDate: "Today 5:00 PM", certainty: .confirmed, status: "In Progress", source: "Message #4", sourceMessageId: "msg-4", isDone: completedTaskIDs.contains("\(prefix)-task-1")),
            ProjectTaskItem(id: "\(prefix)-task-2", title: "Review updated specifications and attachments", owner: "Design Team", dueDate: "Tomorrow", certainty: .confirmed, status: "In Progress", source: "Message #2", sourceMessageId: "msg-2", isDone: completedTaskIDs.contains("\(prefix)-task-2")),
            ProjectTaskItem(id: "\(prefix)-task-3", title: "Share finalized compliance sheet with Operations", owner: "Operations Team", dueDate: "25 Sep", certainty: .confirmed, status: "Pending", source: "Message #5", sourceMessageId: "msg-5", isDone: completedTaskIDs.contains("\(prefix)-task-3")),
            ProjectTaskItem(id: "\(prefix)-task-4", title: "Verify build logs and environment status", owner: "Review Team", dueDate: "Today", certainty: .confirmed, status: "In Progress", source: "Message #3", sourceMessageId: "msg-3", isDone: completedTaskIDs.contains("\(prefix)-task-4")),
            ProjectTaskItem(id: "\(prefix)-task-5", title: "Publish status notes and checklist", owner: "You", dueDate: "Thursday", certainty: .tentative, status: "Pending", source: "Message #1", sourceMessageId: "msg-1", isDone: completedTaskIDs.contains("\(prefix)-task-5"))
        ]

        let initialDeadlines: [UpcomingDeadlineItem] = [
            UpcomingDeadlineItem(id: "\(prefix)-dl-1", title: "\(title) Review Meeting", timeString: "Today · 5:00 PM", certainty: .confirmed, source: "Message #1", sourceMessageId: "msg-1"),
            UpcomingDeadlineItem(id: "\(prefix)-dl-2", title: "\(title) Deployment Window", timeString: "Tomorrow Morning", certainty: .tentative, source: "Message #2", sourceMessageId: "msg-2"),
            UpcomingDeadlineItem(id: "\(prefix)-dl-3", title: "Final Documentation Submission", timeString: "25 Sep · 6:00 PM", certainty: .confirmed, source: "Message #3", sourceMessageId: "msg-3")
        ]

        let initialFiles: [SharedFileItem] = [
            SharedFileItem(id: "\(prefix)-f-1", filename: "\(title.replacingOccurrences(of: " ", with: "_"))_Report.pdf", sizeString: "2.4 MB", fileType: "PDF Document", sharedTime: "Today 10:45 AM", sourceMessageId: "msg-1"),
            SharedFileItem(id: "\(prefix)-f-2", filename: "Deployment_Plan.xlsx", sizeString: "1.8 MB", fileType: "Spreadsheet", sharedTime: "Yesterday", sourceMessageId: "msg-2"),
            SharedFileItem(id: "\(prefix)-f-3", filename: "UI_Updates.fig", sizeString: "14.2 MB", fileType: "Figma File", sharedTime: "2d ago", sourceMessageId: "msg-3"),
            SharedFileItem(id: "\(prefix)-f-4", filename: "API_Specifications.json", sizeString: "450 KB", fileType: "JSON Schema", sharedTime: "3d ago", sourceMessageId: "msg-4"),
            SharedFileItem(id: "\(prefix)-f-5", filename: "Sprint_Review_Deck.pptx", sizeString: "8.5 MB", fileType: "Presentation", sharedTime: "4d ago", sourceMessageId: "msg-5"),
            SharedFileItem(id: "\(prefix)-f-6", filename: "Security_Audit_Summary.docx", sizeString: "620 KB", fileType: "Word Document", sharedTime: "5d ago", sourceMessageId: "msg-6")
        ]

        let initialLinks: [SharedLinkItem] = [
            SharedLinkItem(id: "\(prefix)-l-1", title: "\(title) Dashboard", url: "https://internal.workspace", domain: "internal.workspace", sharedTime: "Today 10:45 AM", sourceMessageId: "msg-1"),
            SharedLinkItem(id: "\(prefix)-l-2", title: "Documentation Portal", url: "https://docs.workspace", domain: "docs.workspace", sharedTime: "Today 09:30 AM", sourceMessageId: "msg-2"),
            SharedLinkItem(id: "\(prefix)-l-3", title: "Design Prototype", url: "https://figma.com", domain: "figma.com", sharedTime: "Yesterday", sourceMessageId: "msg-3"),
            SharedLinkItem(id: "\(prefix)-l-4", title: "Deployment Guide", url: "https://wiki.workspace", domain: "wiki.workspace", sharedTime: "2d ago", sourceMessageId: "msg-4"),
            SharedLinkItem(id: "\(prefix)-l-5", title: "Reference Document", url: "https://standards.workspace", domain: "standards.workspace", sharedTime: "3d ago", sourceMessageId: "msg-5")
        ]

        let initialContributors: [KeyContributorItem] = [
            KeyContributorItem(id: "\(prefix)-c-1", roleName: "Project Lead", contributionCount: 6, decisionsCount: 2, openActionsCount: 1, isConfirmedRole: true),
            KeyContributorItem(id: "\(prefix)-c-2", roleName: "Design Team", contributionCount: 4, decisionsCount: 1, openActionsCount: 1, isConfirmedRole: true),
            KeyContributorItem(id: "\(prefix)-c-3", roleName: "Operations Team", contributionCount: 5, decisionsCount: 1, openActionsCount: 2, isConfirmedRole: true),
            KeyContributorItem(id: "\(prefix)-c-4", roleName: "Review Team", contributionCount: 3, decisionsCount: 1, openActionsCount: 1, isConfirmedRole: true)
        ]

        let initialTimeline: [ConversationTimelineItem] = [
            ConversationTimelineItem(id: "\(prefix)-tl-1", timeString: "10:45 AM", role: "Project Lead", event: "Milestone plan updated for \(title)", source: "Chat", dayGroup: "Today"),
            ConversationTimelineItem(id: "\(prefix)-tl-2", timeString: "09:30 AM", role: "Design Team", event: "Shared specification and review notes", source: "Files", dayGroup: "Today"),
            ConversationTimelineItem(id: "\(prefix)-tl-3", timeString: "08:15 AM", role: "Operations Team", event: "Staging build verified and logged", source: "System", dayGroup: "Today"),
            ConversationTimelineItem(id: "\(prefix)-tl-4", timeString: "04:30 PM", role: "Review Team", event: "Completed sprint deliverable review", source: "Review", dayGroup: "Yesterday"),
            ConversationTimelineItem(id: "\(prefix)-tl-5", timeString: "02:00 PM", role: "Project Lead", event: "Approved timeline for Thursday release", source: "Decisions", dayGroup: "Yesterday")
        ]

        let initialNeedsAttention: [NeedsAttentionItem] = [
            NeedsAttentionItem(title: "Timeline confirmation pending in \(title)", urgency: "High", category: "Confirmation", source: "Message #1", sourceMessageId: "msg-1"),
            NeedsAttentionItem(title: "Latest file requires review", urgency: "Medium", category: "Review", source: "Message #2", sourceMessageId: "msg-2"),
            NeedsAttentionItem(title: "One task is pending assignment", urgency: "Medium", category: "Assignment", source: "Message #3", sourceMessageId: "msg-3")
        ]

        let initialStatus = ProjectStatusInfo(
            status: "On Track",
            upcomingDeadline: "\(title) Review today",
            latestActivity: "\(title) deliverables verified",
            source: "Sprint Matrix",
            sourceMessageId: "msg-1"
        )

        return ConversationContext(
            workspaceId: "work-workspace",
            accountId: conv.accountID,
            conversationId: conv.id,
            conversationTitle: title,
            platformId: conv.platform?.id ?? "workspace",
            platformName: conv.platform?.name ?? "Messaging Platform",
            isPreview: conv.isPreview,
            messages: conv.messages,
            summaryText: initialSummary,
            topics: ["\(title) Milestones", "Requirements", "Review & Sign-Off", "Deployment Verification", "Documentation"],
            decisions: initialDecisions,
            tasks: initialTasks,
            deadlines: initialDeadlines,
            files: initialFiles,
            links: initialLinks,
            contributors: initialContributors,
            timeline: initialTimeline,
            recentChanges: [
                ConversationChangeItem(text: "3 action items updated in \(title)", source: "AI Delta", timestamp: "Today"),
                ConversationChangeItem(text: "Milestone window confirmed for Thursday morning", source: "Project Lead", timestamp: "Today"),
                ConversationChangeItem(text: "Review attachments logged", source: "Design Team", timestamp: "Yesterday")
            ],
            needsAttention: initialNeedsAttention,
            openQuestions: [
                "What is the final cut-off time for the \(title) staging deployment?",
                "Has the stakeholder approval sign-off been received for \(title)?"
            ],
            statusInfo: initialStatus
        )
    }

    /// Builds live conversation intelligence only from messages that were actually indexed.
    /// The richer sample dataset below remains available for explicitly marked preview threads.
    private func buildGroundedContext(for conv: IntelligenceConversation) -> ConversationContext {
        let analysis = ChatIntelligenceService.shared.analyze(
            conversationID: conv.id,
            messages: conv.messages
        )
        let prefix = conv.id

        let decisions = analysis.decisions.enumerated().map { index, text in
            ProjectDecisionItem(
                id: "\(prefix)-decision-\(index)",
                text: cleanExtractedText(text),
                status: "Detected",
                certainty: .aiInferred,
                source: sourceLabel(from: text),
                sourceMessageId: nil,
                timeString: "From conversation"
            )
        }

        let tasks = analysis.structuredTasks.enumerated().map { index, item in
            ProjectTaskItem(
                id: item.id.isEmpty ? "\(prefix)-task-\(index)" : item.id,
                title: item.title,
                owner: item.assignee ?? "Unassigned",
                dueDate: item.dueDate ?? "Not specified",
                certainty: .aiInferred,
                status: item.isCompleted ? "Completed" : "Detected",
                source: "Indexed message",
                sourceMessageId: item.sourceMessageId,
                isDone: item.isCompleted || completedTaskIDs.contains(item.id)
            )
        }

        let deadlines = analysis.dates.enumerated().map { index, date in
            UpcomingDeadlineItem(
                id: "\(prefix)-date-\(index)",
                title: "Date mentioned in conversation",
                timeString: date,
                certainty: .aiInferred,
                source: "Indexed messages",
                sourceMessageId: nil
            )
        }

        let files = analysis.files.enumerated().map { index, filename in
            let ext = URL(fileURLWithPath: filename).pathExtension
            return SharedFileItem(
                id: "\(prefix)-file-\(index)",
                filename: filename,
                sizeString: "Size unavailable",
                fileType: ext.isEmpty ? "File" : ext.uppercased(),
                sharedTime: "Mentioned in conversation",
                sourceMessageId: nil
            )
        }

        let links = analysis.links.enumerated().map { index, address in
            let host = URL(string: address)?.host ?? address
            return SharedLinkItem(
                id: "\(prefix)-link-\(index)",
                title: host,
                url: address,
                domain: host,
                sharedTime: "Mentioned in conversation",
                sourceMessageId: nil
            )
        }

        let groupedContributors = Dictionary(grouping: conv.messages, by: \PlatformMessagePreview.sender)
        let contributors = groupedContributors
            .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { name, messages in
                KeyContributorItem(
                    id: "\(prefix)-contributor-\(name)",
                    roleName: name,
                    contributionCount: messages.count,
                    decisionsCount: 0,
                    openActionsCount: 0,
                    isConfirmedRole: true
                )
            }
            .sorted { $0.contributionCount > $1.contributionCount }

        let timeline = conv.messages.suffix(6).enumerated().map { index, message in
            ConversationTimelineItem(
                id: "\(prefix)-timeline-\(message.id)-\(index)",
                timeString: message.time ?? "Recent",
                role: message.sender,
                event: message.text,
                source: "Message",
                dayGroup: "Recent"
            )
        }

        var attention: [NeedsAttentionItem] = tasks
            .filter { !$0.isDone }
            .prefix(3)
            .map {
                NeedsAttentionItem(
                    title: $0.title,
                    urgency: $0.owner == "You" ? "High" : "Medium",
                    category: $0.owner == "You" ? "Your task" : "Task",
                    source: $0.source,
                    sourceMessageId: $0.sourceMessageId
                )
            }
        if attention.count < 3 {
            attention.append(contentsOf: analysis.unresolvedQuestions.prefix(3 - attention.count).map {
                NeedsAttentionItem(
                    title: cleanExtractedText($0),
                    urgency: "Medium",
                    category: "Question",
                    source: sourceLabel(from: $0),
                    sourceMessageId: nil
                )
            })
        }

        let summary: String
        if analysis.messageCount == 0 {
            summary = "No indexed messages are available for this conversation yet."
        } else if analysis.summary.isEmpty {
            summary = "No important actions or decisions were detected in the indexed messages."
        } else {
            summary = analysis.summary.map(cleanExtractedText).joined(separator: " ")
        }

        let status: String
        if analysis.messageCount == 0 {
            status = "No Data"
        } else if !attention.isEmpty {
            status = "Needs Attention"
        } else if !tasks.isEmpty {
            status = "Action Required"
        } else {
            status = "Up to Date"
        }

        let latestActivity = conv.messages.last.map { cleanExtractedText($0.text) } ?? "No recent activity"
        return ConversationContext(
            workspaceId: "work-workspace",
            accountId: conv.accountID,
            conversationId: conv.id,
            conversationTitle: conv.sender,
            platformId: conv.platform?.id ?? "workspace",
            platformName: conv.platform?.name ?? "Messaging Platform",
            isPreview: false,
            messages: conv.messages,
            summaryText: summary,
            topics: analysis.topics,
            decisions: decisions,
            tasks: tasks,
            deadlines: deadlines,
            files: files,
            links: links,
            contributors: contributors,
            timeline: timeline,
            recentChanges: [],
            needsAttention: attention,
            openQuestions: analysis.unresolvedQuestions.map(cleanExtractedText),
            statusInfo: ProjectStatusInfo(
                status: status,
                upcomingDeadline: deadlines.first?.timeString ?? "No deadline detected",
                latestActivity: latestActivity,
                source: "Indexed conversation",
                sourceMessageId: conv.messages.last?.id
            )
        )
    }

    private func cleanExtractedText(_ value: String) -> String {
        value.components(separatedBy: " — ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? value
    }

    private func sourceLabel(from value: String) -> String {
        let parts = value.components(separatedBy: " — ")
        return parts.count > 1 ? parts.last! : "Indexed message"
    }

    private var topics: [String] { currentContext.topics }
    private var summaryText: String { currentContext.summaryText }

    // MARK: - View Body (3-Pane Center Architecture)
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                // PANE 1: Inbox Conversation List (280-310px)
                conversationList
                    .frame(width: proxy.size.width < 1180 ? 270 : 300)

                divider

                // PANE 2: Center Workspace (Flexible)
                centerWorkspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                divider

                // PANE 3: Right AI Intelligence Panel (360-400px)
                rightAIPanel
                    .frame(width: proxy.size.width < 1320 ? 360 : 390)
            }
        }
        .background(Palette.background)
        .onAppear {
            if selectedID == nil { selectedID = conversations.first?.id }
            store.refreshAllPortals()
            store.refreshSummaries()
        }
        .sheet(isPresented: $showAccess) { accessSheet }
        .confirmationDialog(
            "Confirm External Action",
            isPresented: Binding(
                get: { pendingExternalAction != nil },
                set: { if !$0 { pendingExternalAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Confirm & Execute") {
                if let action = pendingExternalAction {
                    audits.insert(.init(title: action, detail: "Confirmed by you · executed under authorized scope"), at: 0)
                    store.showToast("Action confirmed and executed")
                }
                pendingExternalAction = nil
            }
            Button("Cancel", role: .cancel) { pendingExternalAction = nil }
        } message: {
            Text("Pinggo never performs an external write silently. Review the action and target before proceeding.")
        }
    }

    private var divider: some View {
        Rectangle().fill(Palette.border).frame(width: 1)
    }

    // MARK: - PANE 1: Conversation List
    private var conversationList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Inbox")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.primary)
                Spacer()
                let totalUnread = conversations.reduce(0) { $0 + $1.unread }
                if totalUnread > 0 {
                    Text("\(totalUnread)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.blue, in: Capsule())
                }
            }
            .padding(.horizontal, 14).frame(height: 48)

            // Search Bar + Dedicated AI Query Button
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search conversations...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                        }.buttonStyle(.plain)
                    }
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 9).frame(height: 32)
                .background(Palette.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))

                Button {
                    aiTab = .ask
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text("Ask AI")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8).frame(height: 32)
                    .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.accent.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .help("Ask Pinggo AI about current conversation")
            }
            .padding(.horizontal, 10)

            // Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(InboxFilter.allCases) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 6)

            // Conversation Rows
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredConversations) { item in
                        conversationRow(item)
                    }
                }
                .padding(.horizontal, 7).padding(.top, 4).padding(.bottom, 8)
            }

            // Bottom Status
            HStack(spacing: 7) {
                Circle().fill(Color.green).frame(width: 7, height: 7)
                Text("\(currentContext.indexedMessageCount) msgs indexed · Scoped")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button { store.refreshAllPortals() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(Palette.sidebar)
            .overlay(divider.frame(height: 1), alignment: .top)
        }
        .background(Palette.panel)
    }

    private func filterChip(_ filter: InboxFilter) -> some View {
        let active = selectedFilter == filter
        return Button {
            selectedFilter = filter
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 10.5, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? .white : Palette.muted)
                .padding(.horizontal, 9).frame(height: 26)
                .background(active ? Palette.accent.opacity(0.75) : Palette.card.opacity(0.45), in: Capsule())
                .overlay(Capsule().stroke(active ? Palette.accent : Palette.border))
        }
        .buttonStyle(.plain)
    }

    private func conversationRow(_ item: IntelligenceConversation) -> some View {
        let active = selected.id == item.id
        return Button {
            if selectedID != item.id {
                selectedID = item.id
                answer = nil
                question = ""
                isThinking = false
                centerTab = .summary
                activeTaskId = UUID() // Context guard: cancels in-flight tasks
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                avatar(item.sender, size: 36, color: item.platform.map { spaceColor($0.color) } ?? Palette.accent)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.sender)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(item.time)
                            .font(.system(size: 9.5))
                            .foregroundStyle(active ? Palette.accent : Palette.muted)
                    }
                    HStack(spacing: 4) {
                        if let platform = item.platform {
                            PlatformLogo(platform: platform, size: 10)
                        }
                        Text(item.preview)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if item.unread > 0 {
                            Text("\(item.unread)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 17, minHeight: 17)
                                .background(Palette.accent, in: Circle())
                        }
                    }
                    // Priority Pill
                    if item.priority != "Normal" {
                        Text(item.priority)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(item.priority.contains("Urgent") ? .orange : Palette.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .background(active ? Color.blue.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.blue.opacity(0.5) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: - PANE 2: Center Workspace
    private var centerWorkspace: some View {
        VStack(spacing: 0) {
            // Selected Conversation Header (64px)
            conversationHeader

            // Sub-Navigation Bar
            centerSubNavBar

            // Dynamic Content
            Group {
                switch centerTab {
                case .summary:
                    summaryContent
                case .messages:
                    messagesContent
                case .files:
                    filesContent
                case .tasks:
                    tasksContent
                case .links:
                    linksContent
                case .activity:
                    activityContent
                case .insights:
                    insightsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background)
    }

    private var conversationHeader: some View {
        HStack(spacing: 12) {
            avatar(selected.sender, size: 38, color: selected.platform.map { spaceColor($0.color) } ?? Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(selected.sender)
                    .font(.system(size: 15, weight: .bold))
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("Active")
                    Text("·")
                    if let platform = selected.platform {
                        PlatformLogo(platform: platform, size: 11)
                        Text(platform.name)
                    } else {
                        Text("Messaging Platform")
                    }
                    Text("·")
                    Image(systemName: "lock.fill").font(.system(size: 9))
                    Text("Authorized AI Scope")
                }
                .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
            }
            Spacer()

            // Header Action Buttons
            circleButton("magnifyingglass") { store.showToast("Searching active thread") }
            circleButton("phone.fill") { store.showToast("Audio calling available in live portal") }
            circleButton("video.fill") { store.showToast("Video calling available in live portal") }
            circleButton("ellipsis") { showAccess = true }
        }
        .padding(.horizontal, 16).frame(height: 64)
        .background(Palette.panel)
    }

    private var centerSubNavBar: some View {
        HStack(spacing: 4) {
            ForEach(ConversationNavTab.allCases) { tab in
                Button {
                    centerTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10))
                        Text(tab.rawValue)
                        if tab == .files { countBadge(currentContext.fileCount) }
                        if tab == .tasks { countBadge(currentContext.taskCount) }
                        if tab == .links { countBadge(currentContext.links.count) }
                    }
                    .font(.system(size: 11, weight: centerTab == tab ? .semibold : .medium))
                    .foregroundStyle(centerTab == tab ? .white : Palette.muted)
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(centerTab == tab ? Palette.accent.opacity(0.8) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel)
        .overlay(divider.frame(height: 1), alignment: .top)
    }

    // MARK: - Center "Summary" Tab Content (Primary Hub)
    private var summaryContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conversation intelligence")
                            .font(.system(size: 13, weight: .semibold))
                        Text(summaryDisplayMode == .focus
                             ? "Only decisions, actions, deadlines, and risks"
                             : "Complete extracted conversation detail")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Picker("Summary density", selection: $summaryDisplayMode) {
                        ForEach(SummaryDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                if summaryDisplayMode == .focus {
                    importantSummaryContent
                } else {
                    detailedSummaryContent
                }
            }
            .padding(14)
            .padding(.bottom, 24)
        }
    }

    private var importantSummaryContent: some View {
        VStack(spacing: 14) {
            importantBriefCard

            if currentContext.needsAttention.isEmpty &&
                currentContext.tasks.filter({ !$0.isDone }).isEmpty &&
                currentContext.decisions.isEmpty &&
                currentContext.deadlines.isEmpty {
                importantEmptyState
            } else {
                if !currentContext.needsAttention.isEmpty || !currentContext.tasks.filter({ !$0.isDone }).isEmpty {
                    topPrioritiesCard
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        if !currentContext.decisions.isEmpty { importantDecisionsCard }
                        if !currentContext.deadlines.isEmpty { importantDeadlinesCard }
                    }
                    VStack(spacing: 12) {
                        if !currentContext.decisions.isEmpty { importantDecisionsCard }
                        if !currentContext.deadlines.isEmpty { importantDeadlinesCard }
                    }
                }
            }
        }
    }

    private var detailedSummaryContent: some View {
        VStack(spacing: 14) {
                // 1. Conversation Summary Card + Metrics
                conversationSummaryCard

                // 2. Project Status & Needs Attention
                HStack(alignment: .top, spacing: 12) {
                    projectStatusCard
                    needsAttentionCard
                }

                // 3. Key Topics Discussed
                keyTopicsCard

                // 4. Decisions | Tasks (Two-Column Grid)
                HStack(alignment: .top, spacing: 12) {
                    decisionsCard
                    tasksOverviewCard
                }

                // 5. Deadlines | Key Contributors (Two-Column Grid)
                HStack(alignment: .top, spacing: 12) {
                    deadlinesCard
                    contributorsCard
                }

                // 6. Timeline | Recent Changes (Two-Column Grid)
                if !currentContext.timeline.isEmpty || !currentContext.recentChanges.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        if !currentContext.timeline.isEmpty { timelineCard }
                        if !currentContext.recentChanges.isEmpty { recentChangesCard }
                    }
                }

                // 7. Shared Files & Shared Links
                if !currentContext.files.isEmpty || !currentContext.links.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        if !currentContext.files.isEmpty { sharedFilesCard }
                        if !currentContext.links.isEmpty { sharedLinksCard }
                    }
                }

                // 8. Open Questions & Workstream Status
                if !currentContext.openQuestions.isEmpty || currentContext.isPreview {
                    HStack(alignment: .top, spacing: 12) {
                        if !currentContext.openQuestions.isEmpty { openQuestionsCard }
                        if currentContext.isPreview { workstreamStatusCard }
                    }
                }
        }
    }

    private var importantBriefCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Important brief", systemImage: "scope")
                        .font(.system(size: 14, weight: .bold))
                    Text("Grounded in \(currentContext.indexedMessageCount) indexed \(currentContext.indexedMessageCount == 1 ? "message" : "messages")")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(currentContext.statusInfo.status)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(importantStatusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(importantStatusColor.opacity(0.12), in: Capsule())
            }

            Text(currentContext.summaryText)
                .font(.system(size: 12.5, weight: .medium))
                .lineSpacing(3)
                .lineLimit(4)

            HStack(spacing: 8) {
                importantMetric(
                    "\(currentContext.needsAttention.count)",
                    "Attention",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
                importantMetric(
                    "\(currentContext.tasks.filter { !$0.isDone }.count)",
                    "Open actions",
                    icon: "checklist",
                    color: .blue
                )
                importantMetric(
                    "\(currentContext.decisionCount)",
                    "Decisions",
                    icon: "checkmark.seal.fill",
                    color: .teal
                )
                importantMetric(
                    "\(currentContext.deadlineCount)",
                    "Dates",
                    icon: "calendar.badge.clock",
                    color: .purple
                )
            }

            HStack {
                Label("Results are extracted only from this conversation", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.green)
                Spacer()
                Button("View messages") { centerTab = .messages }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Palette.accent.opacity(0.15), Palette.card.opacity(0.82)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.accent.opacity(0.4)))
    }

    private var topPrioritiesCard: some View {
        dashboardCard(title: "Top priorities", icon: "exclamationmark.triangle.fill", color: .orange) {
            VStack(spacing: 0) {
                ForEach(Array(currentContext.needsAttention.prefix(3))) { item in
                    importantRow(
                        title: item.title,
                        detail: item.category,
                        icon: item.urgency == "High" ? "exclamationmark.circle.fill" : "circle.fill",
                        color: item.urgency == "High" ? .orange : .yellow,
                        sourceMessageID: item.sourceMessageId
                    )
                }

                let existingTitles = Set(currentContext.needsAttention.map(\.title))
                ForEach(Array(currentContext.tasks.filter { !$0.isDone && !existingTitles.contains($0.title) }.prefix(3))) { task in
                    importantRow(
                        title: task.title,
                        detail: "\(task.owner) · \(task.dueDate)",
                        icon: "square",
                        color: .blue,
                        sourceMessageID: task.sourceMessageId
                    )
                }
            }
        }
    }

    private var importantDecisionsCard: some View {
        dashboardCard(title: "Decisions", icon: "checkmark.seal.fill", color: .teal) {
            VStack(spacing: 0) {
                ForEach(Array(currentContext.decisions.prefix(3))) { decision in
                    importantRow(
                        title: decision.text,
                        detail: "\(decision.status) · \(decision.certainty.rawValue)",
                        icon: "checkmark.circle.fill",
                        color: .teal,
                        sourceMessageID: decision.sourceMessageId
                    )
                }
            }
        }
    }

    private var importantDeadlinesCard: some View {
        dashboardCard(title: "Dates & deadlines", icon: "calendar.badge.clock", color: .purple) {
            VStack(spacing: 0) {
                ForEach(Array(currentContext.deadlines.prefix(3))) { deadline in
                    importantRow(
                        title: deadline.title,
                        detail: "\(deadline.timeString) · \(deadline.certainty.rawValue)",
                        icon: "clock.fill",
                        color: .purple,
                        sourceMessageID: deadline.sourceMessageId
                    )
                }
            }
        }
    }

    private var importantEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: currentContext.indexedMessageCount == 0 ? "tray" : "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(currentContext.indexedMessageCount == 0 ? Palette.muted : Color.green)
            Text(currentContext.indexedMessageCount == 0 ? "Nothing analyzed yet" : "No urgent items detected")
                .font(.system(size: 13, weight: .semibold))
            Text(currentContext.indexedMessageCount == 0
                 ? "Open or sync the conversation to index its messages."
                 : "No decisions, action items, unresolved questions, or dates were found in the indexed messages.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
            Button("View conversation") { centerTab = .messages }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Palette.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .cardStyle()
    }

    private var importantStatusColor: Color {
        switch currentContext.statusInfo.status {
        case "Needs Attention", "Action Required": return .orange
        case "Up to Date": return .green
        default: return Palette.muted
        }
    }

    private func importantMetric(_ value: String, _ label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: 13, weight: .bold))
                Text(label).font(.system(size: 8.5)).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func importantRow(
        title: String,
        detail: String,
        icon: String,
        color: Color,
        sourceMessageID: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            if sourceMessageID != nil {
                Button("Source") { centerTab = .messages }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.vertical, 7)
        .overlay(divider.frame(height: 1), alignment: .bottom)
    }

    // 1. Conversation Summary Card
    private var conversationSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Conversation Summary", systemImage: "sparkles")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Text("\(currentContext.indexedMessageCount) messages analyzed · Current conversation scope")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Button("Refresh") {
                    store.refreshAllPortals()
                    store.refreshSummaries()
                    store.showToast("Conversation memory refreshed")
                }
                .buttonStyle(.bordered).controlSize(.small).tint(Palette.accent)
            }
            Text(currentContext.summaryText)
                .font(.system(size: 11.5)).foregroundStyle(.primary.opacity(0.9)).lineSpacing(3)

            // Metrics Strip - Derived strictly from currentContext
            HStack(spacing: 8) {
                metric("\(currentContext.topicCount)", "Key Topics", "checkmark.seal.fill", .purple)
                metric("\(currentContext.decisionCount)", "Decisions", "checkmark.circle.fill", .teal)
                metric("\(currentContext.taskCount - currentContext.completedTaskCount)", "Pending Tasks", "tray.full.fill", .blue)
                metric("\(currentContext.deadlineCount)", "Deadlines", "calendar.badge.clock", .orange)
                metric("\(currentContext.fileCount)", "Shared Files", "doc.fill", .indigo)
            }
        }
        .cardStyle()
    }

    // 2. Project Status Card
    private var projectStatusCard: some View {
        dashboardCard(title: "Project Status", icon: "chart.bar.fill", color: .green) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tracked task progress: \(currentContext.progressPercent)% (\(currentContext.completedTaskCount) of \(currentContext.taskCount) tasks completed)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color.green)
                    Spacer()
                    Text(currentContext.statusInfo.status)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.green.opacity(0.12), in: Capsule())
                }
                ProgressView(value: Double(currentContext.completedTaskCount), total: max(Double(currentContext.taskCount), 1.0))
                    .tint(.green)

                VStack(spacing: 4) {
                    statusRow("Open Tasks", value: "\(currentContext.taskCount - currentContext.completedTaskCount) active")
                    statusRow("Completed Tasks", value: "\(currentContext.completedTaskCount) items")
                    statusRow("Upcoming Deadline", value: currentContext.statusInfo.upcomingDeadline)
                    statusRow("Latest Activity", value: currentContext.statusInfo.latestActivity)
                }
                .font(.system(size: 10.5))

                HStack {
                    Spacer()
                    Button("[View Source]") {
                        centerTab = .messages
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                }
            }
        }
    }

    // 2. Needs Attention Card
    private var needsAttentionCard: some View {
        dashboardCard(title: "Needs Attention", icon: "exclamationmark.triangle.fill", color: .orange) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(currentContext.needsAttention) { item in
                    attentionItem(item.title, urgency: item.urgency, cat: item.category, source: item.source)
                }

                HStack {
                    Spacer()
                    Button("Review All") {
                        centerTab = .tasks
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(Palette.accent)
                }
                .padding(.top, 4)
            }
        }
    }

    private func attentionItem(_ title: String, urgency: String, cat: String, source: String = "") -> some View {
        HStack(spacing: 6) {
            Circle().fill(urgency == "High" ? Color.orange : Color.yellow).frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
            Spacer()
            Text(cat)
                .font(.system(size: 9))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 4))
            Button("[Source]") {
                centerTab = .messages
            }
            .buttonStyle(.plain)
            .font(.system(size: 8.5))
            .foregroundStyle(Palette.accent)
        }
    }

    // 3. Key Topics Card
    private var keyTopicsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key Topics Discussed")
                .font(.system(size: 12.5, weight: .semibold))
            FlowLayout(spacing: 6) {
                ForEach(currentContext.topics, id: \.self) { topic in
                    Text(topic)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.9))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Palette.card.opacity(0.7), in: Capsule())
                        .overlay(Capsule().stroke(Palette.accent.opacity(0.35)))
                }
            }
        }
        .cardStyle()
    }

    // 4. Decisions Card
    private var decisionsCard: some View {
        dashboardCard(title: "Decisions", icon: "checkmark.circle.fill", color: .teal) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(currentContext.decisions) { dec in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.teal)
                            Text(dec.text)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(2)
                            Spacer()
                        }
                        HStack {
                            Text("\(dec.status) (\(dec.certainty.rawValue)) · \(dec.timeString)")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.muted)
                            Spacer()
                            Button("[View Source]") {
                                centerTab = .messages
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                        }
                    }
                    if dec.id != currentContext.decisions.last?.id {
                        Divider().background(Palette.border)
                    }
                }
            }
        }
    }

    // 4. Tasks Card
    private var tasksOverviewCard: some View {
        dashboardCard(title: "Pending Tasks", icon: "checklist", color: .blue) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(currentContext.tasks) { task in
                    let isCompleted = completedTaskIDs.contains(task.id)
                    HStack(alignment: .top, spacing: 7) {
                        Button {
                            if isCompleted {
                                completedTaskIDs.remove(task.id)
                            } else {
                                completedTaskIDs.insert(task.id)
                            }
                            audits.insert(.init(title: "Task status changed", detail: task.title), at: 0)
                        } label: {
                            Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                                .foregroundStyle(isCompleted ? Color.green : Color.blue)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(task.title)
                                .font(.system(size: 10.5, weight: .medium))
                                .strikethrough(isCompleted)
                                .lineLimit(1)
                            Text("\(task.owner) · Due \(task.dueDate) · \(task.certainty.rawValue)")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("[View Source]") {
                            centerTab = .messages
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
        }
    }

    // 5. Deadlines Card
    private var deadlinesCard: some View {
        dashboardCard(title: "Upcoming Deadlines", icon: "calendar.badge.clock", color: .orange) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(currentContext.deadlines) { dl in
                    HStack(spacing: 7) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dl.title)
                                .font(.system(size: 10.5, weight: .medium))
                            Text("\(dl.timeString) · \(dl.source)")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text(dl.certainty.rawValue)
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(dl.certainty == .confirmed ? .green : .orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.white.opacity(0.06), in: Capsule())

                        Button("[View Source]") {
                            centerTab = .messages
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Palette.accent)
                    }
                }
            }
        }
    }

    // 5. Contributors Card
    private var contributorsCard: some View {
        dashboardCard(title: "Key Contributors", icon: "person.2.fill", color: .cyan) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(currentContext.contributors) { c in
                    HStack(spacing: 7) {
                        avatar(c.roleName, size: 24, color: .cyan)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.roleName)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("\(c.contributionCount) messages · \(c.decisionsCount) decisions · \(c.openActionsCount) actions")
                                .font(.system(size: 8.5))
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button("Ask AI") {
                            question = "What did \(c.roleName) work on in \(currentContext.conversationTitle)?"
                            aiTab = .ask
                            ask(question)
                        }
                        .buttonStyle(.bordered).controlSize(.mini).tint(Palette.accent)
                    }
                }
            }
        }
    }

    // 6. Timeline Card
    private var timelineCard: some View {
        dashboardCard(title: "Conversation Timeline", icon: "clock.arrow.circlepath", color: .purple) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(currentContext.timeline) { item in
                    HStack(spacing: 6) {
                        Text(item.timeString)
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 48, alignment: .leading)
                        Circle().fill(Palette.accent).frame(width: 5, height: 5)
                        Text(item.role)
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(item.event)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                        Spacer()
                    }
                }
            }
        }
    }

    // 6. Recent Changes Card
    private var recentChangesCard: some View {
        dashboardCard(title: "Recent Changes", icon: "sparkles", color: .indigo) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(currentContext.recentChanges) { change in
                    bullet(change.text, meta: "\(change.timestamp) · \(change.source)")
                }

                HStack {
                    Spacer()
                    Button("View Changes") {
                        centerTab = .insights
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(Palette.accent)
                }
        }
    }
}

    // 7. Shared Files Card
    private var sharedFilesCard: some View {
        dashboardCard(title: "Shared Files", icon: "folder.fill", color: .indigo) {
            VStack(spacing: 6) {
                ForEach(currentContext.files.prefix(4)) { file in
                    fileRow(
                        file.filename,
                        meta: "\(file.sizeString) · \(file.fileType)",
                        color: fileColor(for: file.fileType),
                        icon: fileIcon(for: file.fileType)
                    )
                }
            }
        }
    }

    private func fileRow(_ name: String, meta: String, color: Color, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 26, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Text(meta).font(.system(size: 8.5)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button("Open") { store.showToast("Opening \(name)") }.buttonStyle(.bordered).controlSize(.mini)
            Button("Ask AI") {
                question = "Summarize \(name)"
                aiTab = .ask
                ask(question)
            }.buttonStyle(.bordered).controlSize(.mini).tint(Palette.accent)
        }
        .padding(5).background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
    }

    // 7. Shared Links Card
    private var sharedLinksCard: some View {
        dashboardCard(title: "Shared Links", icon: "link", color: .blue) {
            VStack(spacing: 6) {
                ForEach(currentContext.links.prefix(4)) { link in
                    linkRow(link.title, domain: link.domain)
                }
            }
        }
    }

    private func linkRow(_ title: String, domain: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(Palette.accent)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                Text(domain).font(.system(size: 8.5)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer()
            Button("Open") { store.showToast("Opening link: \(title)") }.buttonStyle(.bordered).controlSize(.mini)
            Button("Ask AI") {
                question = "What is in \(title)?"
                aiTab = .ask
                ask(question)
            }.buttonStyle(.bordered).controlSize(.mini).tint(Palette.accent)
        }
        .padding(5).background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
    }

    // 8. Open Questions Card
    private var openQuestionsCard: some View {
        dashboardCard(title: "Open Questions", icon: "questionmark.circle.fill", color: .yellow) {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(openQuestions, id: \.self) { q in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(q)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(2)
                        HStack {
                            Spacer()
                            Button("Find Answer") {
                                question = q
                                aiTab = .ask
                                ask(q)
                            }
                            .buttonStyle(.bordered).controlSize(.mini).tint(Palette.accent)
                        }
                    }
                    if q != openQuestions.last {
                        Divider().background(Palette.border)
                    }
                }
            }
        }
    }

    // 8. Workstream Status Card
    private var workstreamStatusCard: some View {
        dashboardCard(title: "Workstream Status", icon: "chart.line.uptrend.xyaxis", color: .teal) {
            VStack(spacing: 6) {
                workstreamRow("Design", progress: 0.80, status: "80% · On Track", color: .purple)
                workstreamRow("Development", progress: 0.65, status: "65% · In Progress", color: .blue)
                workstreamRow("Deployment", progress: 0.40, status: "40% · Waiting", color: .orange)
                workstreamRow("Documentation", progress: 0.75, status: "75% · Review", color: .green)
            }
        }
    }

    private func workstreamRow(_ name: String, progress: Double, status: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name).font(.system(size: 9.5, weight: .medium))
                Spacer()
                Text(status).font(.system(size: 8.5)).foregroundStyle(Palette.muted)
            }
            ProgressView(value: progress).tint(color)
        }
    }

    // MARK: - Center Other Tabs
    private var messagesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Messages in \(selected.sender)")
                    .font(.system(size: 13.5, weight: .semibold))

                let msgs = selected.messages.isEmpty ? previewMessages(for: selected.sender) : selected.messages
                ForEach(msgs) { msg in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            avatar(msg.sender, size: 22, color: Palette.accent)
                            Text(msg.sender).font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text(msg.time ?? "Recent").font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                        }
                        Text(msg.text).font(.system(size: 11.5)).lineSpacing(2)

                        HStack {
                            Spacer()
                            Button("Use as Source") {
                                question = "Summarize message from \(msg.sender)"
                                aiTab = .ask
                                ask(question)
                            }
                            .buttonStyle(.plain).font(.system(size: 9.5)).foregroundStyle(Palette.accent)
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(14)
        }
    }

    private var filesContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("All Files Shared in this Thread")
                    .font(.system(size: 13.5, weight: .semibold))

                VStack(spacing: 8) {
                    ForEach(currentContext.files) { file in
                        fileDetailCard(file.filename, size: file.sizeString, type: file.fileType, time: file.sharedTime, color: fileColor(for: file.fileType), icon: fileIcon(for: file.fileType))
                    }
                }
            }
            .padding(14)
        }
    }

    private func fileIcon(for type: String) -> String {
        let t = type.lowercased()
        if t.contains("pdf") { return "doc.fill" }
        if t.contains("sheet") || t.contains("excel") || t.contains("csv") { return "tablecells.fill" }
        if t.contains("figma") || t.contains("design") || t.contains("image") { return "paintpalette.fill" }
        if t.contains("json") || t.contains("code") { return "curlybraces" }
        if t.contains("present") || t.contains("deck") || t.contains("pptx") { return "rectangle.inset.filled.and.person.filled" }
        return "doc.text.fill"
    }

    private func fileColor(for type: String) -> Color {
        let t = type.lowercased()
        if t.contains("pdf") { return .red }
        if t.contains("sheet") || t.contains("excel") { return .green }
        if t.contains("figma") || t.contains("design") { return .purple }
        if t.contains("json") || t.contains("code") { return .blue }
        if t.contains("present") || t.contains("deck") { return .orange }
        return .indigo
    }

    private func fileDetailCard(_ name: String, size: String, type: String, time: String, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 32, height: 36)
                .background(color, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 11, weight: .semibold))
                Text("\(size) · \(type) · \(time)")
                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button("Open") { store.showToast("Opening \(name)") }.buttonStyle(.bordered).controlSize(.small)
            Button("Preview") { store.showToast("Previewing \(name)") }.buttonStyle(.bordered).controlSize(.small)
            Button("Ask AI") {
                question = "Analyze \(name)"
                aiTab = .ask
                ask(question)
            }.buttonStyle(.bordered).controlSize(.small).tint(Palette.accent)
        }
        .cardStyle()
    }

    private var tasksContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Tasks & Action Items")
                        .font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                    Text("\(currentContext.completedTaskCount) of \(currentContext.taskCount) completed")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                }

                VStack(spacing: 8) {
                    ForEach(currentContext.tasks) { task in
                        let isCompleted = task.isDone || completedTaskIDs.contains(task.id)
                        HStack(alignment: .top, spacing: 10) {
                            Button {
                                if isCompleted { completedTaskIDs.remove(task.id) }
                                else { completedTaskIDs.insert(task.id) }
                            } label: {
                                Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(isCompleted ? Color.green : Palette.accent)
                                    .font(.system(size: 14))
                            }.buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .strikethrough(isCompleted)
                                HStack(spacing: 6) {
                                    Text("Assignee: \(task.owner)")
                                    Text("·")
                                    Text("Due: \(task.dueDate)")
                                    Text("·")
                                    Text("Source: \(task.source)")
                                }
                                .font(.system(size: 9)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Button("Create Reminder") {
                                pendingExternalAction = "Create reminder for: \(task.title)"
                            }
                            .buttonStyle(.bordered).controlSize(.mini)
                        }
                        .cardStyle()
                    }
                }
            }
            .padding(14)
        }
    }

    private var linksContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Shared Links & Documentation")
                    .font(.system(size: 13.5, weight: .semibold))

                VStack(spacing: 8) {
                    ForEach(currentContext.links) { link in
                        sharedLinkDetail(link.title, url: link.url, time: link.sharedTime)
                    }
                }
            }
            .padding(14)
        }
    }

    private func sharedLinkDetail(_ title: String, url: String, time: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(Palette.accent)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text("\(url) · Shared \(time)")
                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button("Open") { store.showToast("Opening \(title)") }.buttonStyle(.bordered).controlSize(.small)
            Button("Save") { store.showToast("Saved to bookmarks") }.buttonStyle(.bordered).controlSize(.small)
            Button("Ask AI") {
                question = "Explain link \(title)"
                aiTab = .ask
                ask(question)
            }.buttonStyle(.bordered).controlSize(.small).tint(Palette.accent)
        }
        .cardStyle()
    }

    private var activityContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Workspace Activity Stream")
                    .font(.system(size: 13.5, weight: .semibold))

                timelineCard
                contributorsCard
            }
            .padding(14)
        }
    }

    private var insightsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Intelligence & Privacy Pipeline")
                    .font(.system(size: 13.5, weight: .semibold))

                securityPipelineCard
                recentChangesCard

                dashboardCard(title: "Privacy & Grounding Telemetry", icon: "checkmark.shield.fill", color: .green) {
                    VStack(alignment: .leading, spacing: 6) {
                        statusRow("Conversation ID", value: selected.id)
                        statusRow("Answer Engine", value: aiResolution.displayBadge)
                        statusRow("Indexing Status", value: "Indexed · 100% on-device")
                        statusRow(
                            "External AI Context",
                            value: aiResolution.canPerformGenerativeAI
                                ? "Scoped messages sent when you ask"
                                : "Disabled"
                        )
                        statusRow("Write Actions", value: "Requires explicit user confirmation")
                    }
                    .font(.system(size: 10))
                }
            }
            .padding(14)
        }
    }

    // MARK: - PANE 3: Right AI Panel ("Pinggo AI")
    private var rightAIPanel: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pinggo AI")
                            .font(.system(size: 14, weight: .bold))
                        Text(currentContext.conversationTitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                    Spacer()

                    // Permissions Badges
                    HStack(spacing: 4) {
                        badgeTag("Current chat", color: .purple)
                        badgeTag(
                            permissionScope.sendMessages ? "Read + write" : "Read only",
                            color: permissionScope.sendMessages ? .green : .blue
                        )
                        badgeTag(aiProcessingLabel, color: aiResolution.canPerformGenerativeAI ? .purple : .blue)
                    }

                    Button {
                        showAccess = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                }

                // Status Banner
                HStack {
                    Circle().fill(aiStatusColor).frame(width: 6, height: 6)
                    Text("\(aiResolution.displayBadge) · \(currentContext.indexedMessageCount) messages analyzed")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                    Button(aiResolution.canPerformGenerativeAI ? "AI Settings" : "Connect AI") {
                        store.destination = .settings
                    }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
            .background(Palette.panel)

            // 5 Tabs Bar: Ask | Tasks | Files | Activity | Actions
            HStack(spacing: 2) {
                ForEach(AIPanelTab.allCases) { tab in
                    Button {
                        aiTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 9.5))
                            Text(tab.rawValue)
                        }
                        .font(.system(size: 10, weight: aiTab == tab ? .semibold : .medium))
                        .foregroundStyle(aiTab == tab ? .white : Palette.muted)
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background(aiTab == tab ? Palette.accent.opacity(0.8) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Palette.panel)
            .overlay(divider.frame(height: 1), alignment: .top)

            // Dynamic Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch aiTab {
                    case .ask:
                        aiAskTab
                    case .tasks:
                        aiTasksTab
                    case .files:
                        aiFilesTab
                    case .activity:
                        aiActivityTab
                    case .actions:
                        aiActionsTab
                    }
                }
                .padding(12)
            }

            // Bottom Portal Button
            VStack(spacing: 4) {
                Button {
                    if let accountID = selected.accountID {
                        store.openPlatformInbox(accountID: accountID)
                    } else {
                        store.showToast("Opening live conversation portal")
                    }
                } label: {
                    Label("Open Live Conversation", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(Palette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.accent))
                }
                .buttonStyle(.plain)

                Text("Pinggo uses read-only contextual ingestion. Open live chat to send messages.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
            .background(Palette.panel)
        }
        .background(Palette.background)
    }

    // 1. Ask Tab
    private var aiAskTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Input Field
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.muted)
                TextField("Ask anything about this conversation...", text: $question)
                    .textFieldStyle(.plain)
                    .onSubmit { ask(question) }
                Button {
                    ask(question)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(Palette.navActiveBg, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 10).frame(height: 38)
            .background(Palette.card.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Palette.accent.opacity(0.7)))

            // Thinking Indicator
            if isThinking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reasoning over \(currentContext.conversationTitle)...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.vertical, 4)
            }

            // Isolated Q&A History for Selected Conversation
            let history = chatHistory[selected.id] ?? []
            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(history) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundStyle(Palette.muted)
                                    .font(.system(size: 12))
                                Text(item.question)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.primary)
                            }

                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(Palette.accent)
                                    .font(.system(size: 12))
                                Text(item.answer)
                                    .font(.system(size: 11))
                                    .lineSpacing(2)
                                    .foregroundStyle(.primary)
                            }

                            HStack {
                                Label(item.origin, systemImage: "checkmark.shield.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 8.5, weight: .medium))
                                Spacer()
                                Button("View Source") {
                                    centerTab = .messages
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(8)
                        .background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
                    }
                }
            } else if let answer = answer {
                VStack(alignment: .leading, spacing: 6) {
                    Text(answer)
                        .font(.system(size: 11.5))
                        .lineSpacing(2)
                    HStack {
                        Label(answerOrigin ?? "Grounded Engine", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 8.5))
                        Spacer()
                        Button("View Source") {
                            centerTab = .messages
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.accent)
                    }
                }
                .padding(8)
                .background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            }

            // Suggested Contextual Prompts (3 primary + 4 expandable)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("Contextual Prompts", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button(showAllPrompts ? "Show less" : "+ Show 4 more") {
                        showAllPrompts.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.accent)
                }

                FlowLayout(spacing: 5) {
                    ForEach(contextualPrompts, id: \.self) { prompt in
                        Button(prompt) {
                            question = prompt
                            ask(prompt)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Palette.accent.opacity(0.08), in: Capsule())
                        .overlay(Capsule().stroke(Palette.accent.opacity(0.35)))
                    }
                }
            }
            .cardStyle()
        }
    }

    private var contextualPrompts: [String] {
        let primaryPrompts = [
            "What do I need to do today?",
            "What decisions were made?",
            "What is the latest project status?"
        ]

        let additionalPrompts = [
            "Which tasks are still pending?",
            "Show upcoming deadlines",
            "Which files need review?",
            "What changed since yesterday?"
        ]

        return showAllPrompts ? (primaryPrompts + additionalPrompts) : primaryPrompts
    }

    private var filteredAITasks: [ProjectTaskItem] {
        let tasks = currentContext.tasks
        switch aiTasksSubFilter {
        case "Completed":
            return tasks.filter { $0.isDone || completedTaskIDs.contains($0.id) }
        case "Waiting":
            return tasks.filter { $0.status.lowercased().contains("wait") || $0.status.lowercased().contains("pending") }
        case "My Tasks":
            return tasks.filter { $0.owner.contains("Lead") || $0.owner.contains("Me") }
        case "Team Tasks":
            return tasks.filter { !$0.owner.contains("Lead") && !$0.owner.contains("Me") }
        default:
            return tasks
        }
    }

    // 2. Tasks Tab in AI Panel
    private var aiTasksTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Sub-filter tabs
            HStack(spacing: 4) {
                ForEach(["All", "My Tasks", "Team Tasks", "Waiting", "Completed"], id: \.self) { filter in
                    Button(filter) {
                        aiTasksSubFilter = filter
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: aiTasksSubFilter == filter ? .bold : .medium))
                    .foregroundStyle(aiTasksSubFilter == filter ? .white : Palette.muted)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(aiTasksSubFilter == filter ? Palette.accent.opacity(0.7) : Palette.card.opacity(0.4), in: Capsule())
                }
            }

            VStack(spacing: 7) {
                if filteredAITasks.isEmpty {
                    Text("No tasks match '\(aiTasksSubFilter)' in this conversation.")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                        .padding(.vertical, 8)
                } else {
                    ForEach(filteredAITasks) { task in
                        let isCompleted = task.isDone || completedTaskIDs.contains(task.id)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(task.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .strikethrough(isCompleted)
                                Spacer()
                                Text(task.dueDate)
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(Palette.muted)
                            }
                            HStack {
                                Text("Owner: \(task.owner)")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(Palette.muted)
                                Spacer()
                                Button("Source") { centerTab = .messages }
                                    .buttonStyle(.plain).font(.system(size: 8.5)).foregroundStyle(Palette.accent)
                                Button(isCompleted ? "Completed" : "Done") {
                                    if isCompleted { completedTaskIDs.remove(task.id) }
                                    else { completedTaskIDs.insert(task.id) }
                                }
                                .buttonStyle(.bordered).controlSize(.mini)
                            }
                        }
                        .padding(8).background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    // 3. Files Tab in AI Panel
    private var aiFilesTab: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Recent Files & AI Prompts")
                .font(.system(size: 12, weight: .semibold))

            ForEach(currentContext.files.prefix(4)) { file in
                fileQuickAction(file.filename, prompt: "Summarize \(file.filename)")
            }

            HStack {
                Spacer()
                Button("View All Files (\(currentContext.fileCount))") { centerTab = .files }
                    .buttonStyle(.bordered).controlSize(.small).tint(Palette.accent)
            }
        }
    }

    private func fileQuickAction(_ name: String, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(size: 10.5, weight: .semibold))
            Button(prompt) {
                question = prompt
                aiTab = .ask
                ask(prompt)
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5))
            .foregroundStyle(Palette.accent)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    // 4. Activity Tab in AI Panel
    private var aiActivityTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conversation Intelligence Activity")
                .font(.system(size: 12, weight: .semibold))

            metricCard("Messages Indexed", value: "\(currentContext.indexedMessageCount)", subtitle: "Scanned on-device")
            metricCard("Decisions Detected", value: "\(currentContext.decisions.count)", subtitle: "\(currentContext.decisions.filter { $0.certainty == .confirmed }.count) confirmed")
            metricCard("Tasks Tracked", value: "\(currentContext.taskCount)", subtitle: "\(currentContext.completedTaskCount) completed")
            metricCard("Files Analyzed", value: "\(currentContext.fileCount)", subtitle: "Shared files")
            metricCard("Deadlines Found", value: "\(currentContext.deadlineCount)", subtitle: "Next: \(currentContext.deadlines.first?.title ?? "None")")
        }
    }

    private func metricCard(_ title: String, value: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10.5, weight: .medium))
                Text(subtitle).font(.system(size: 8.5)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Text(value).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.accent)
        }
        .padding(8).background(Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    // 5. Actions Tab in AI Panel
    private var aiActionsTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            dashboardCard(title: "Suggested Actions", icon: "wand.and.stars", color: .purple) {
                VStack(spacing: 8) {
                    actionButton("Draft confirmation for \(currentContext.conversationTitle)") {
                        answer = "Drafted for \(currentContext.conversationTitle): All milestone deliverables have been verified and logged."
                        aiTab = .ask
                    }
                    if let firstDl = currentContext.deadlines.first {
                        actionButton("Create reminder for \(firstDl.title)") {
                            pendingExternalAction = "Create calendar reminder for \(firstDl.title) (\(firstDl.timeString))"
                        }
                    }
                    if let firstOwner = currentContext.contributors.first {
                        actionButton("Request review from \(firstOwner.roleName)") {
                            pendingExternalAction = "Send review request notification to \(firstOwner.roleName)"
                        }
                    }
                }
            }

            dashboardCard(title: "Session Audit Log", icon: "checkmark.seal.fill", color: .green) {
                if audits.isEmpty {
                    Text("No external write actions performed in this session.")
                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                } else {
                    ForEach(audits.prefix(6)) { entry in
                        bullet(entry.title, meta: entry.detail)
                    }
                }
            }
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 10, weight: .medium))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 9))
            }
            .padding(8)
            .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.accent.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Access Scope Sheet
    private var accessSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pinggo AI Access Control")
                        .font(.system(size: 18, weight: .bold))
                    Text("Scoped to \(selected.sender) · 100% on-device governance")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            }
            Divider()

            Text("READ ACCESS").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.muted)
            permissionToggle("Messages & chat logs", value: $permissionScope.messages)
            permissionToggle("Participants & role metadata", value: $permissionScope.participants)
            permissionToggle("Shared links & documents", value: $permissionScope.links)
            permissionToggle("File attachments", value: $permissionScope.attachments)

            Text("WRITE PERMISSIONS · Confirmation required").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.muted).padding(.top, 4)
            permissionToggle("Draft replies locally", value: $permissionScope.draftReplies)
            permissionToggle("Send messages (Prompt on send)", value: $permissionScope.sendMessages)
            permissionToggle("Create local tasks", value: $permissionScope.createTasks)
            permissionToggle("Create calendar reminders", value: $permissionScope.createReminders)

            HStack {
                Text("All write operations trigger an explicit confirmation dialog.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Done") {
                    showAccess = false
                    audits.insert(.init(title: "Permissions updated", detail: "Scope settings saved"), at: 0)
                }
                .buttonStyle(.borderedProminent).tint(Palette.accent)
            }
            .padding(.top, 8)
        }
        .padding(20).frame(width: 440)
    }

    private func permissionToggle(_ title: String, value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value)
            .toggleStyle(.switch)
            .tint(Palette.accent)
            .font(.system(size: 11.5))
    }

    // MARK: - Grounded AI Ask Logic
    private func ask(_ prompt: String) {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let currentTargetId = selected.id
        let targetMessages = selected.messages
        let priorTurns = (chatHistory[currentTargetId] ?? []).suffix(4)
        let priorContext = String(priorTurns.map {
            "User: \($0.question)\nPinggo AI: \($0.answer)"
        }.joined(separator: "\n\n").prefix(6_000))
        let preferences = store.preferences
        let queryTaskId = UUID()
        activeTaskId = queryTaskId
        isThinking = true

        Task { @MainActor in
            let analysis = ChatIntelligenceService.shared.analyze(
                conversationID: currentTargetId,
                messages: targetMessages
            )
            let aiMessage = await ChatIntelligenceService.shared.answer(
                question: clean,
                analysis: analysis,
                messages: targetMessages,
                members: nil,
                preferences: preferences,
                priorContext: priorContext
            )

            // Context guard: never place a delayed answer in a different conversation.
            guard activeTaskId == queryTaskId && selected.id == currentTargetId else { return }

            let generatedAnswer = aiMessage.text
            let generatedOrigin = aiMessage.source?.badgeText ?? "Pinggo AI"
            let title = selected.sender

            answer = generatedAnswer
            answerOrigin = generatedOrigin

            let historyItem = AIChatHistoryItem(
                question: clean,
                answer: generatedAnswer,
                origin: generatedOrigin,
                sourceMessageId: aiMessage.sourceMessageId
            )
            var list = chatHistory[currentTargetId] ?? []
            list.append(historyItem)
            chatHistory[currentTargetId] = list

            audits.insert(.init(title: "AI answer generated for \(title)", detail: generatedOrigin), at: 0)
            isThinking = false
            question = ""
        }
    }

    // MARK: - UI Helpers
    private func metric(_ value: String, _ label: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(value).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(color)
            Text(label).font(.system(size: 8.5)).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3)))
    }

    private func dashboardCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func bullet(_ title: String, meta: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10, weight: .medium)).lineLimit(2)
                Text(meta).font(.system(size: 8.5)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer()
        }
    }

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.muted)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }

    private func badgeTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Palette.accent.opacity(0.16), in: Capsule())
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .frame(width: 30, height: 30)
                .background(Palette.card.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(Palette.border))
        }
        .buttonStyle(.plain)
    }

    private func avatar(_ name: String, size: CGFloat, color: Color) -> some View {
        Circle()
            .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Text(initials(name))
                    .font(.system(size: size * 0.32, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var securityPipelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Grounded AI Governance Pipeline", systemImage: "lock.shield.fill")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("LOCAL + SCOPED").font(.system(size: 8.5, weight: .bold)).foregroundStyle(.green)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Color.green.opacity(0.12), in: Capsule())
            }
            HStack(spacing: 4) {
                pipelineStep("Access", "checkmark.shield")
                pipelineArrow
                pipelineStep("Index", "externaldrive.fill")
                pipelineArrow
                pipelineStep("Memory", "brain.head.profile")
                pipelineArrow
                pipelineStep("Retrieve", "magnifyingglass")
                pipelineArrow
                pipelineStep("Reason", "sparkles")
                pipelineArrow
                pipelineStep("Confirm", "hand.raised.fill")
                pipelineArrow
                pipelineStep("Audit", "checkmark.seal.fill")
            }
        }
        .cardStyle()
    }

    private func pipelineStep(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Palette.accent)
            Text(title).font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var pipelineArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 6, weight: .bold))
            .foregroundStyle(Palette.muted.opacity(0.4))
    }

    // MARK: - Sanitized Preview Messages (No personal data)
    private func previewMessages(for title: String) -> [PlatformMessagePreview] {
        [
            .init(id: "\(title)-1", sender: "Project Lead", text: "Milestone status updated for \(title). Review meeting scheduled for tomorrow.", time: "10:45 AM", isUnread: true),
            .init(id: "\(title)-2", sender: "Design Team", text: "New document shared for \(title). Ready for team review.", time: "09:30 AM", isUnread: true),
            .init(id: "\(title)-3", sender: "Operations Team", text: "Timeline and checklist need confirmation before staging.", time: "08:15 AM", isUnread: false),
            .init(id: "\(title)-4", sender: "Review Team", text: "Deliverables for \(title) verified and logged.", time: "Yesterday", isUnread: false)
        ]
    }

    // MARK: - Sanitized Preview Conversations (Pure Workspace Placeholders)
    private var previewConversations: [IntelligenceConversation] {
        let items: [(String, String, String, Int, String, String)] = [
            ("Project Alpha", "Deployment plan updated for Project Alpha. Review meeting scheduled.", "10:45 AM", 2, "purple", "🔥 Urgent"),
            ("Design Review", "New file shared: UI_Updates.fig. Ready for team review.", "09:30 AM", 1, "pink", "📝 Task"),
            ("Operations Team", "Timeline needs confirmation before staging deployment.", "08:15 AM", 3, "orange", "❓ Needs Reply"),
            ("Client Project", "Review requested for the updated milestone deliverables.", "Yesterday", 0, "blue", "📅 Meeting"),
            ("Product Team", "New action items added for the upcoming release cycle.", "Yesterday", 1, "green", "Normal"),
            ("Team Alpha", "Weekly sprint objectives and milestone checklist confirmed.", "2d ago", 0, "indigo", "Normal"),
            ("Workspace Update", "Staging build verified. Deployment pipeline ready.", "3d ago", 0, "cyan", "Normal"),
            ("Review Meeting", "Action items recorded for cross-team alignment.", "4d ago", 0, "teal", "Normal"),
            ("Deployment Plan", "Production migration scheduled for Thursday 10:00 AM.", "5d ago", 0, "blue", "Normal")
        ]
        return items.enumerated().map { index, entry in
            IntelligenceConversation(
                id: "preview-\(index)",
                accountID: nil,
                platform: nil,
                sender: entry.0,
                preview: entry.1,
                time: entry.2,
                unread: entry.3,
                priority: entry.5,
                messages: previewMessages(for: entry.0),
                isPreview: true
            )
        }
    }
}

// MARK: - View Helpers
private extension View {
    func cardStyle() -> some View {
        self.padding(10)
            .background(Palette.card.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border))
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 500
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: width, height: y + lineHeight), points)
    }
}
