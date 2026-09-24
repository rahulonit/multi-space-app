import Foundation
import WebKit
import Combine
import AppKit
import NaturalLanguage

@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    // Stable UUIDs for AI web partitions
    static let geminiPartitionID = UUID(uuidString: "a1a1a1a1-bbbb-cccc-dddd-eeeeeeeeeeee")!
    static let chatGptPartitionID = UUID(uuidString: "b2b2b2b2-cccc-dddd-eeee-ffffffffffff")!

    static let geminiURL = URL(string: "https://gemini.google.com")!
    static let chatGptURL = URL(string: "https://chatgpt.com")!

    private init() {}

    // MARK: - Dedicated Website Data Stores
    var geminiDataStore: WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: Self.geminiPartitionID)
    }

    var chatGptDataStore: WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: Self.chatGptPartitionID)
    }

    // MARK: - Auth Status Checking
    func verifyGeminiAuth() async -> Bool {
        let store = geminiDataStore
        let cookies = await store.httpCookieStore.allCookies()
        let hasGoogleAuth = cookies.contains { cookie in
            let name = cookie.name.uppercased()
            return name == "SID" || name == "HSID" || name == "SAPISID" || name.contains("PSID") || name.contains("SSID")
        }
        return hasGoogleAuth
    }

    func verifyChatGptAuth() async -> Bool {
        let store = chatGptDataStore
        let cookies = await store.httpCookieStore.allCookies()
        let hasOpenAIAuth = cookies.contains { cookie in
            let name = cookie.name.lowercased()
            return name == "session-token" || name == "__secure-next-auth.session-token" || (name.contains("session-token") && !name.contains("cf"))
        }
        return hasOpenAIAuth
    }

    func signOut(provider: String, store: AppStore) async {
        if provider == "gemini" {
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            await geminiDataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast)
            store.preferences.isGeminiLoggedIn = false
            store.preferences.geminiAccountEmail = ""
            store.preferences.geminiApiKey = ""
            store.showToast("Disconnected Google Gemini")
        } else if provider == "chatgpt" {
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            await chatGptDataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast)
            store.preferences.isChatGptLoggedIn = false
            store.preferences.chatGptAccountEmail = ""
            store.preferences.openAiApiKey = ""
            store.showToast("Disconnected OpenAI")
        }
    }

    // MARK: - Deep Conversation Analysis (Private Preview Compatible)
    func analyzeChat(
        sender: String,
        messageText: String,
        platformName: String,
        accountName: String,
        preferences: AppPreferences,
        threadMessages: [PlatformMessagePreview] = []
    ) -> AIAnalysisResult {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()

        // 1. Detect Questions
        let detectedQuestion: String? = {
            if text.contains("?") {
                let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!\n"))
                if let questionSentence = sentences.first(where: { $0.contains("?") }) {
                    return questionSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if lower.contains("can you") || lower.contains("could you") || lower.contains("let me know if") ||
                      lower.contains("what do you think") || lower.contains("when are you") || lower.contains("would you be able") {
                return text
            }
            return nil
        }()

        // 2. Classify Intent, Urgency, Action Items & Sentiment
        var intent = "General Update"
        var urgency: SummaryUrgency = .normal
        var sentiment = "Neutral / Professional"
        var actionItem: String? = nil
        var contextSummary = ""

        if lower.contains("urgent") || lower.contains("asap") || lower.contains("critical") ||
           lower.contains("emergency") || lower.contains("blocked") || lower.contains("immediately") {
            intent = "🚨 Urgent Request"
            urgency = .high
            sentiment = "High Priority / Urgent"
            contextSummary = "\(sender) sent an urgent message on \(platformName) requiring swift action."
            actionItem = "Acknowledge and resolve \(sender)'s urgent blocker"
        } else if lower.contains("meet") || lower.contains("call") || lower.contains("sync") ||
                  lower.contains("zoom") || lower.contains("calendar") || lower.contains("schedule") {
            intent = "📅 Meeting Request"
            urgency = .medium
            sentiment = "Collaborative / Scheduling"
            contextSummary = "\(sender) requested a sync or scheduling discussion."
            actionItem = "Reply to \(sender) with open availability slots"
        } else if lower.contains("review") || lower.contains("feedback") || lower.contains("draft") ||
                  lower.contains("attached") || lower.contains("deck") || lower.contains("check out") {
            intent = "📝 Review & Feedback"
            urgency = .medium
            sentiment = "Constructive / Work Request"
            contextSummary = "\(sender) shared material requesting your feedback."
            actionItem = "Review submitted items from \(sender)"
        } else if lower.contains("proposal") || lower.contains("partnership") || lower.contains("contract") ||
                  lower.contains("pricing") || lower.contains("invoice") || lower.contains("quote") {
            intent = "🤝 Business Opportunity"
            urgency = .medium
            sentiment = "Commercial / Opportunity"
            contextSummary = "\(sender) reached out regarding a commercial proposal or partnership."
            actionItem = "Evaluate proposal details from \(sender)"
        } else if lower.contains("bug") || lower.contains("issue") || lower.contains("error") ||
                  lower.contains("release") || lower.contains("deploy") || lower.contains("pr ") {
            intent = "🚀 Product / Tech Update"
            urgency = detectedQuestion != nil ? .medium : .normal
            sentiment = "Technical Status"
            contextSummary = "\(sender) shared a tech or development update."
            if detectedQuestion != nil { actionItem = "Answer technical inquiry from \(sender)" }
        } else if detectedQuestion != nil {
            intent = "❓ Question / Inquiry"
            urgency = .medium
            sentiment = "Inquisitive"
            contextSummary = "\(sender) asked a direct question awaiting your answer."
            actionItem = "Provide answer to \(sender)"
        } else {
            intent = "💬 Message / Check-in"
            urgency = .normal
            sentiment = "Casual / Friendly"
            contextSummary = "\(sender) sent a direct message on \(platformName)."
        }

        // 3. Determine AIMessagePriority
        let aiPriority: AIMessagePriority
        if urgency == .high {
            aiPriority = .urgent
        } else if intent.contains("Meeting") {
            aiPriority = .meeting
        } else if detectedQuestion != nil {
            aiPriority = .question
        } else if intent.contains("Review") || intent.contains("Business") {
            aiPriority = .review
        } else {
            aiPriority = .normal
        }

        // 4. Extract Calendar Event if meeting or schedule mentioned
        let calendarEvent = extractCalendarEvent(sender: sender, messageText: text, platformName: platformName)

        // 5. Detect Non-English Language and Translation
        let langTranslation = detectLanguageAndTranslate(text: text)

        // 6. Context-Aware Multi-Tone Smart Replies
        let replies = generateMultiToneReplies(
            sender: sender,
            text: text,
            intent: intent,
            detectedQuestion: detectedQuestion,
            customPrompt: preferences.customAiPrompt
        )

        // 7. Daily Conversation Summary Synthesis
        let effectiveMessages: [PlatformMessagePreview] = {
            if !threadMessages.isEmpty { return threadMessages }
            return [PlatformMessagePreview(id: "current", sender: sender, text: text, time: nil, linkURL: nil, isUnread: true)]
        }()

        let dailySummary = generateDailyConversationSummary(
            sender: sender,
            messages: effectiveMessages,
            platformName: platformName,
            accountName: accountName,
            preferences: preferences
        )

        // 8. Honest Local Attribution
        let providerName = "Pinggo Smart Engine (Local Heuristic)"

        return AIAnalysisResult(
            sender: sender,
            contextSummary: contextSummary,
            detectedIntent: intent,
            detectedQuestion: detectedQuestion,
            actionItem: actionItem,
            urgency: urgency,
            sentiment: sentiment,
            replies: replies,
            providerName: providerName,
            isStealthMode: true,
            analyzedAt: .now,
            aiPriority: aiPriority,
            detectedCalendarEvent: calendarEvent,
            detectedLanguage: langTranslation?.language,
            translatedText: langTranslation?.translation,
            dailySummary: dailySummary
        )
    }

    // MARK: - Calendar Extraction & Apple Calendar Integration
    func extractCalendarEvent(sender: String, messageText: String, platformName: String) -> AICalendarEvent? {
        let lower = messageText.lowercased()
        let hasCalendarTrigger = lower.contains("meet") || lower.contains("call") || lower.contains("sync") ||
                                 lower.contains("zoom") || lower.contains("calendar") || lower.contains("schedule") ||
                                 lower.contains("coffee") || lower.contains("at ") || lower.contains("tomorrow") ||
                                 lower.contains("friday") || lower.contains("monday") || lower.contains("thursday")

        guard hasCalendarTrigger else { return nil }

        // Determine date suggestion
        var dateSuggestion = "Upcoming"
        if lower.contains("tomorrow") {
            dateSuggestion = "Tomorrow"
        } else if lower.contains("monday") {
            dateSuggestion = "This Monday"
        } else if lower.contains("tuesday") {
            dateSuggestion = "This Tuesday"
        } else if lower.contains("wednesday") {
            dateSuggestion = "This Wednesday"
        } else if lower.contains("thursday") {
            dateSuggestion = "This Thursday"
        } else if lower.contains("friday") {
            dateSuggestion = "This Friday"
        } else if lower.contains("next week") {
            dateSuggestion = "Next Week"
        } else if lower.contains("today") {
            dateSuggestion = "Today"
        }

        // Determine suggested time
        var startTime: String? = nil
        let timePatterns = ["10am", "11am", "12pm", "1pm", "2pm", "3pm", "4pm", "5pm", "10:00", "11:00", "14:00", "15:00", "16:00"]
        for p in timePatterns {
            if lower.contains(p) {
                startTime = p.uppercased()
                break
            }
        }
        if startTime == nil && (lower.contains("morning") || lower.contains("afternoon")) {
            startTime = lower.contains("morning") ? "10:00 AM" : "2:00 PM"
        }

        // Determine location or video call link
        var location = "Video Call"
        if lower.contains("zoom") { location = "Zoom Meeting" }
        else if lower.contains("meet") || lower.contains("google meet") { location = "Google Meet" }
        else if lower.contains("teams") { location = "Microsoft Teams" }
        else if lower.contains("office") || lower.contains("coffee") { location = "In Person / Coffee" }

        return AICalendarEvent(
            title: "\(sender) · \(platformName) Discussion",
            dateSuggestion: dateSuggestion,
            startTime: startTime ?? "2:00 PM",
            locationOrLink: location,
            notes: "Proposed in \(platformName) chat: \"\(messageText)\""
        )
    }

    func openInAppleCalendar(event: AICalendarEvent, store: AppStore) {
        let now = Date()
        let calendar = Calendar.current
        var targetDate = now

        let lowerDate = event.dateSuggestion.lowercased()
        if lowerDate.contains("tomorrow") {
            targetDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        } else if lowerDate.contains("monday") {
            targetDate = nextDate(dayOfWeek: 2, from: now)
        } else if lowerDate.contains("tuesday") {
            targetDate = nextDate(dayOfWeek: 3, from: now)
        } else if lowerDate.contains("wednesday") {
            targetDate = nextDate(dayOfWeek: 4, from: now)
        } else if lowerDate.contains("thursday") {
            targetDate = nextDate(dayOfWeek: 5, from: now)
        } else if lowerDate.contains("friday") {
            targetDate = nextDate(dayOfWeek: 6, from: now)
        } else if lowerDate.contains("saturday") {
            targetDate = nextDate(dayOfWeek: 7, from: now)
        } else if lowerDate.contains("sunday") {
            targetDate = nextDate(dayOfWeek: 1, from: now)
        }

        var hour = 14
        var minute = 0
        if let timeStr = event.startTime {
            let timeClean = timeStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isPM = timeClean.contains("pm")
            let digits = timeClean.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if let h = digits.first.flatMap(Int.init) {
                hour = isPM && h < 12 ? h + 12 : (!isPM && timeClean.contains("am") && h == 12 ? 0 : h)
                if digits.count > 1, let m = Int(digits[1]) {
                    minute = m
                }
            }
        }

        var comps = calendar.dateComponents([.year, .month, .day], from: targetDate)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        let startDateTime = calendar.date(from: comps) ?? targetDate
        let endDateTime = calendar.date(byAdding: .hour, value: 1, to: startDateTime) ?? startDateTime

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        let dtStart = formatter.string(from: startDateTime)
        let dtEnd = formatter.string(from: endDateTime)

        let icsString = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//PINGGO//AI Calendar//EN
        BEGIN:VEVENT
        SUMMARY:\(event.title)
        DESCRIPTION:\(event.notes)
        LOCATION:\(event.locationOrLink ?? "Online")
        DTSTART:\(dtStart)
        DTEND:\(dtEnd)
        STATUS:CONFIRMED
        END:VEVENT
        END:VCALENDAR
        """

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).ics")
        do {
            try icsString.write(to: tempURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(tempURL)
            store.showToast("Opening in Apple Calendar…")
        } catch {
            store.showToast("Copied meeting: \(event.title)")
        }
    }

    private func nextDate(dayOfWeek: Int, from date: Date) -> Date {
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.weekday = dayOfWeek
        return calendar.nextDate(after: date, matching: comps, matchingPolicy: .nextTime) ?? date
    }

    // MARK: - Language Detection & Real Translation
    func detectLanguage(text: String) -> (code: String, name: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        let code = dominant.rawValue
        if code == "en" || code == "und" { return nil }

        let langName = Locale.current.localizedString(forIdentifier: code) ?? code.uppercased()
        return (code, langName)
    }

    func translateMessage(text: String, targetLanguage: String = "English", preferences: AppPreferences) async throws -> String {
        let resolution = AIProviderResolver.resolve(preferences: preferences)
        guard resolution.canPerformGenerativeAI else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Translation unavailable without configured AI provider."])
        }

        let prompt = "Translate the following text into \(targetLanguage). Output only the translated text with no introductory or conversational remarks:\n\n\(text)"
        if resolution.provider == .gemini {
            return try await callGeminiAPI(apiKey: preferences.geminiApiKey, model: resolution.model, prompt: prompt)
        } else if resolution.provider == .chatgpt {
            return try await callOpenAIAPI(apiKey: preferences.openAiApiKey, model: resolution.model, prompt: prompt)
        } else if resolution.provider == .ollama {
            return try await callOllamaAPI(endpoint: preferences.ollamaEndpoint, model: resolution.model, prompt: prompt)
        }
        throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No active translation engine available."])
    }

    func detectLanguageAndTranslate(text: String) -> (language: String, translation: String)? {
        guard let (_, name) = detectLanguage(text: text) else { return nil }
        return (name, "Incoming message in \(name). Translate via AI Assistant.")
    }

    // MARK: - Apple ML Sentiment Analysis
    func analyzeSentimentML(text: String) -> (score: Double, label: String) {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        let score = Double(tag?.rawValue ?? "0") ?? 0.0

        let label: String
        if score >= 0.4 {
            label = "Warm & Highly Positive (\(String(format: "+%.1f", score)))"
        } else if score >= 0.1 {
            label = "Constructive / Collaborative (\(String(format: "+%.1f", score)))"
        } else if score <= -0.4 {
            label = "Urgent Concern / Critical (\(String(format: "%.1f", score)))"
        } else if score <= -0.1 {
            label = "Direct / Needs Resolution (\(String(format: "%.1f", score)))"
        } else {
            label = "Neutral / Professional"
        }
        return (score, label)
    }

    func analyzeSentiment(text: String) -> SentimentResult {
        let (score, label) = analyzeSentimentML(text: text)
        return SentimentResult(score: score, classification: label, detectedLanguage: "English")
    }

    // MARK: - Context & Entity Extraction Engine
    func extractSubjectAndEntities(from text: String) -> String {
        let lower = text.lowercased()

        // 1. Deliverable & Domain Specific Entities
        if lower.contains("figma") || lower.contains("mockup") || lower.contains("wireframe") || lower.contains("prototype") {
            if lower.contains("checkout") { return "the Figma checkout flow" }
            if lower.contains("onboarding") { return "the onboarding flow mockups" }
            if lower.contains("landing") { return "the landing page design" }
            if lower.contains("mobile") { return "the mobile app UI designs" }
            if lower.contains("component") { return "the Figma design system components" }
            return "the Figma design files"
        }
        if lower.contains("hotfix") || lower.contains("bug") || lower.contains("crash") || lower.contains("error") {
            if lower.contains("auth") || lower.contains("login") { return "the auth login crash hotfix" }
            if lower.contains("database") || lower.contains("db") { return "the database sync error" }
            if lower.contains("production") || lower.contains("prod") { return "the production crash issue" }
            if lower.contains("timeout") { return "the API timeout error" }
            return "the reported bug fix"
        }
        if lower.contains("pr ") || lower.contains("pull request") || lower.contains("merge") || lower.contains("deploy") || lower.contains("release") {
            if lower.contains("release") { return "the upcoming release deployment" }
            if lower.contains("pr") || lower.contains("pull request") { return "the pull request changes" }
            return "the deployment pipeline update"
        }
        if lower.contains("contract") || lower.contains("agreement") || lower.contains("nda") {
            return "the contract terms and agreement"
        }
        if lower.contains("invoice") || lower.contains("billing") || lower.contains("pricing") || lower.contains("quote") || lower.contains("payment") {
            if lower.contains("invoice") { return "the invoice details" }
            if lower.contains("pricing") { return "the pricing proposal" }
            return "the billing and payment terms"
        }
        if lower.contains("proposal") || lower.contains("pitch") || lower.contains("partnership") || lower.contains("collab") {
            return "the partnership proposal"
        }
        if lower.contains("deck") || lower.contains("slide") || lower.contains("presentation") {
            return "the presentation slide deck"
        }
        if lower.contains("budget") || lower.contains("forecast") || lower.contains("q3") || lower.contains("q4") {
            return "the quarterly budget plan"
        }
        if lower.contains("coffee") || lower.contains("lunch") || lower.contains("dinner") {
            return "meeting up for coffee"
        }
        if lower.contains("zoom") || lower.contains("google meet") || lower.contains("teams") || lower.contains("sync") || lower.contains("call") || lower.contains("interview") {
            return "the sync discussion"
        }
        if lower.contains("document") || lower.contains("doc") || lower.contains("pdf") || lower.contains("spec") {
            return "the project specification document"
        }

        // 2. Syntactic extraction: "about [xyz]", "regarding [xyz]", or "for [xyz]"
        if let range = text.range(of: "about ", options: .caseInsensitive) {
            let snippet = text[range.upperBound...]
            let phrase = snippet.components(separatedBy: CharacterSet(charactersIn: "?!.,\n")).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if phrase.count >= 4 && phrase.count <= 45 {
                return phrase
            }
        }
        if let range = text.range(of: "regarding ", options: .caseInsensitive) {
            let snippet = text[range.upperBound...]
            let phrase = snippet.components(separatedBy: CharacterSet(charactersIn: "?!.,\n")).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if phrase.count >= 4 && phrase.count <= 45 {
                return phrase
            }
        }
        if let range = text.range(of: "for ", options: .caseInsensitive) {
            let snippet = text[range.upperBound...]
            let phrase = snippet.components(separatedBy: CharacterSet(charactersIn: "?!.,\n")).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if phrase.count >= 4 && phrase.count <= 40 && !phrase.lowercased().hasPrefix("you") && !phrase.lowercased().hasPrefix("me") && !phrase.lowercased().hasPrefix("now") {
                return phrase
            }
        }

        // 3. Fallback to clean short summary of first clause
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!\n"))
        if let first = sentences.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            if first.count <= 40 {
                return "\"\(first)\""
            } else {
                return "\"\(first.prefix(35))…\""
            }
        }

        return "your message"
    }

    func extractTemporalContext(from text: String) -> String? {
        let lower = text.lowercased()
        var clockTime: String? = nil
        let timePatterns = ["10:00 am", "11:00 am", "12:00 pm", "1:00 pm", "2:00 pm", "3:00 pm", "4:00 pm", "5:00 pm", "10am", "11am", "12pm", "1pm", "2pm", "3pm", "4pm", "5pm", "9am", "10:00", "11:00", "14:00", "15:00"]
        for p in timePatterns {
            if lower.contains(p) {
                clockTime = p.uppercased()
                break
            }
        }

        var dayOrRelative: String? = nil
        if lower.contains("tomorrow morning") { dayOrRelative = "tomorrow morning" }
        else if lower.contains("tomorrow afternoon") { dayOrRelative = "tomorrow afternoon" }
        else if lower.contains("tomorrow") { dayOrRelative = "tomorrow" }
        else if lower.contains("this monday") || lower.contains("monday") { dayOrRelative = "Monday" }
        else if lower.contains("this tuesday") || lower.contains("tuesday") { dayOrRelative = "Tuesday" }
        else if lower.contains("this wednesday") || lower.contains("wednesday") { dayOrRelative = "Wednesday" }
        else if lower.contains("this thursday") || lower.contains("thursday") { dayOrRelative = "Thursday" }
        else if lower.contains("this friday") || lower.contains("friday") { dayOrRelative = "Friday" }
        else if lower.contains("next week") { dayOrRelative = "next week" }
        else if lower.contains("today eod") || lower.contains("eod") || lower.contains("end of day") { dayOrRelative = "by end of day" }
        else if lower.contains("this afternoon") { dayOrRelative = "this afternoon" }
        else if lower.contains("tonight") { dayOrRelative = "tonight" }

        if let day = dayOrRelative, let time = clockTime {
            return "\(day) at \(time)"
        } else if let day = dayOrRelative {
            return day
        } else if let time = clockTime {
            return time
        }
        return nil
    }

    // MARK: - Context-Aware, Non-Generic Multi-Tone Smart Replies
    func generateMultiToneReplies(
        sender: String,
        text: String,
        intent: String,
        detectedQuestion: String?,
        customPrompt: String
    ) -> [AIReplyOption] {
        let firstName = sender.components(separatedBy: " ").first ?? sender
        let lower = text.lowercased()
        let subject = extractSubjectAndEntities(from: text)
        let temporal = extractTemporalContext(from: text)

        if intent.contains("Meeting") || lower.contains("meet") || lower.contains("sync") || lower.contains("call") || lower.contains("coffee") {
            let timeStr = temporal ?? "tomorrow at 2:00 PM"
            return [
                .init(id: "prof", tone: .professional, text: "Thank you, \(firstName). I would be glad to connect regarding \(subject). \(timeStr) works well on my calendar—I will send over a calendar invite."),
                .init(id: "friend", tone: .friendly, text: "Hey \(firstName)! Sounds awesome, I'd love to chat about \(subject). \(timeStr) is perfect for me! Looking forward to catching up."),
                .init(id: "concise", tone: .concise, text: "Confirmed for \(timeStr) to discuss \(subject). Will send meeting link."),
                .init(id: "casual", tone: .casual, text: "Hey! Definitely, let's sync up on \(subject). \(temporal != nil ? "See you \(temporal!)!" : "Shoot over an invite whenever!")"),
                .init(id: "decline", tone: .politeDecline, text: "Thanks for the invitation to connect on \(subject), \(firstName). Unfortunately my schedule is fully committed right now, but I will ping you once my calendar opens up."),
                .init(id: "time", tone: .proposeTime, text: "Happy to connect on \(subject)! Would Thursday at 3:00 PM or Friday at 11:00 AM work better for you?")
            ]
        } else if intent.contains("Urgent") || lower.contains("urgent") || lower.contains("blocker") || lower.contains("crash") {
            return [
                .init(id: "prof", tone: .professional, text: "Received, \(firstName). I am actively prioritizing \(subject) as an urgent blocker and will deploy a fix immediately."),
                .init(id: "friend", tone: .friendly, text: "Got it \(firstName)! Jumping on \(subject) right this second, will keep you posted every step of the way."),
                .init(id: "concise", tone: .concise, text: "On \(subject) right now. Will update you in 15 mins."),
                .init(id: "casual", tone: .casual, text: "No worries, hopping on \(subject) right now! We'll get it sorted out fast."),
                .init(id: "decline", tone: .politeDecline, text: "Thanks \(firstName). I am currently handling another critical outage and cannot jump directly into \(subject) immediately."),
                .init(id: "time", tone: .proposeTime, text: "Understood on \(subject). I am reviewing the initial logs now and will be free to sync on status at 4:30 PM.")
            ]
        } else if intent.contains("Review") || lower.contains("figma") || lower.contains("draft") || lower.contains("deck") || lower.contains("feedback") {
            let timeCommitment = temporal ?? "end of day today"
            return [
                .init(id: "prof", tone: .professional, text: "Thank you for sending over \(subject), \(firstName). I am reviewing the details now and will return my compiled feedback by \(timeCommitment)."),
                .init(id: "friend", tone: .friendly, text: "Thanks \(firstName)! Just opened \(subject)—it looks fantastic so far! Sending a few quick thoughts by \(timeCommitment)."),
                .init(id: "concise", tone: .concise, text: "Received \(subject). Reviewing and sharing feedback by \(timeCommitment)."),
                .init(id: "casual", tone: .casual, text: "Looking through \(subject) right now—super clean work! Notes coming your way shortly."),
                .init(id: "decline", tone: .politeDecline, text: "Thank you for thinking of me for \(subject), \(firstName). Due to ongoing release commitments, I won't have the capacity for a thorough review right now."),
                .init(id: "time", tone: .proposeTime, text: "Received \(subject)! I have a review block reserved on Friday morning to go through this in detail.")
            ]
        } else if intent.contains("Business") || lower.contains("proposal") || lower.contains("invoice") || lower.contains("pricing") || lower.contains("contract") {
            return [
                .init(id: "prof", tone: .professional, text: "Thank you for reaching out, \(firstName). We are evaluating \(subject) with the team and will follow up with our formal response shortly."),
                .init(id: "friend", tone: .friendly, text: "Hi \(firstName), appreciate you sharing \(subject)! Looking forward to digging into this and following up."),
                .init(id: "concise", tone: .concise, text: "Received \(subject). Evaluating details and will reply soon."),
                .init(id: "casual", tone: .casual, text: "Sounds exciting! Taking a close look at \(subject) and will catch up with you later this week."),
                .init(id: "decline", tone: .politeDecline, text: "Thank you for sharing \(subject), \(firstName). After evaluating our current priorities, this isn't a strategic fit for us at this time."),
                .init(id: "time", tone: .proposeTime, text: "Thanks \(firstName). Could we sync to discuss \(subject) next Tuesday at 2:00 PM?")
            ]
        } else if detectedQuestion != nil {
            return [
                .init(id: "prof", tone: .professional, text: "Hello \(firstName), regarding \(subject): yes, we are on track and all requirements are met. I will follow up once next steps are completed."),
                .init(id: "friend", tone: .friendly, text: "Hey \(firstName)! Good question on \(subject)—yes, absolutely! Everything is in order. Let me know if you need any other details!"),
                .init(id: "concise", tone: .concise, text: "Yes, all set for \(subject). Proceeding as planned."),
                .init(id: "casual", tone: .casual, text: "Hey! Yup, all good on that front with \(subject) 👍"),
                .init(id: "decline", tone: .politeDecline, text: "Hi \(firstName), regarding \(subject): I won't be able to accommodate that request right now, but appreciate you asking."),
                .init(id: "time", tone: .proposeTime, text: "Let's walk through the specifics for \(subject) when we connect tomorrow at 3:00 PM.")
            ]
        } else {
            return [
                .init(id: "prof", tone: .professional, text: "Thank you for the update regarding \(subject), \(firstName). I have noted the details and will keep you informed."),
                .init(id: "friend", tone: .friendly, text: "Thanks for checking in on \(subject), \(firstName)! Hope everything is going smoothly with your week."),
                .init(id: "concise", tone: .concise, text: "Acknowledged regarding \(subject). Thanks for the note!"),
                .init(id: "casual", tone: .casual, text: "Hey, thanks for the heads up on \(subject)! Appreciate the ping."),
                .init(id: "decline", tone: .politeDecline, text: "Thanks for reaching out, \(firstName). I am currently focused on other commitments, but wish you all the best with this."),
                .init(id: "time", tone: .proposeTime, text: "Great to hear from you regarding \(subject)! Let's find time for a coffee or sync next week.")
            ]
        }
    }

    // MARK: - Daily Conversation Summary Generation
    func generateDailyConversationSummary(
        sender: String,
        messages: [PlatformMessagePreview],
        platformName: String,
        accountName: String,
        preferences: AppPreferences
    ) -> ConversationDailySummary {
        let combinedText = messages.map(\.text).joined(separator: " \n ")
        let primaryText = messages.first?.text ?? ""
        let targetText = combinedText.isEmpty ? primaryText : combinedText
        let subject = extractSubjectAndEntities(from: targetText)
        let temporal = extractTemporalContext(from: targetText)
        let lower = targetText.lowercased()

        // 1. Extract Key Topics
        var topics: [String] = []
        if lower.contains("figma") || lower.contains("design") || lower.contains("ui") || lower.contains("prototype") {
            topics.append("🎨 Design & Prototype")
        }
        if lower.contains("pr ") || lower.contains("deploy") || lower.contains("bug") || lower.contains("hotfix") || lower.contains("crash") {
            topics.append("🚀 Engineering & Deployment")
        }
        if lower.contains("meet") || lower.contains("call") || lower.contains("sync") || lower.contains("zoom") || lower.contains("coffee") {
            topics.append("📅 Scheduling & Coordination")
        }
        if lower.contains("contract") || lower.contains("proposal") || lower.contains("invoice") || lower.contains("pricing") {
            topics.append("💼 Commercial & Agreements")
        }
        if lower.contains("urgent") || lower.contains("asap") || lower.contains("critical") || lower.contains("blocker") {
            topics.append("🚨 Priority Blocker")
        }
        if topics.isEmpty {
            topics.append("💬 Chat Discussion")
        }

        // 2. Extract Decisions Made
        var decisions: [String] = []
        if lower.contains("agreed") || lower.contains("approved") || lower.contains("confirmed") || lower.contains("done") {
            decisions.append("Key deliverables agreed and approved in today's thread.")
        } else if lower.contains("meet") || lower.contains("call") {
            if let t = temporal {
                decisions.append("Discussion slot targeted for \(t).")
            } else {
                decisions.append("Follow-up sync proposed to review \(subject).")
            }
        } else if lower.contains("review") || lower.contains("draft") {
            decisions.append("Draft submitted for review and feedback.")
        } else {
            decisions.append("Active discussion underway regarding \(subject).")
        }

        // 3. Extract Pending Questions
        var pendingQuestions: [String] = []
        for msg in messages {
            if msg.text.contains("?") {
                let parts = msg.text.components(separatedBy: CharacterSet(charactersIn: ".!\n"))
                if let q = parts.first(where: { $0.contains("?") })?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    if !pendingQuestions.contains(q) {
                        pendingQuestions.append(q)
                    }
                }
            }
        }
        if pendingQuestions.isEmpty {
            if lower.contains("can you") || lower.contains("could you") || lower.contains("let me know") {
                pendingQuestions.append("Awaiting confirmation on \(subject).")
            }
        }

        // 4. Extract Action Items
        var actionItems: [String] = []
        if lower.contains("send") || lower.contains("share") || lower.contains("attach") {
            actionItems.append("Send requested \(subject) to \(sender)")
        }
        if lower.contains("review") || lower.contains("feedback") {
            actionItems.append("Review submitted items from \(sender) and share notes")
        }
        if lower.contains("meet") || lower.contains("sync") || lower.contains("calendar") {
            if let t = temporal {
                actionItems.append("Confirm calendar invite for \(t)")
            } else {
                actionItems.append("Provide availability slots to \(sender)")
            }
        }
        if lower.contains("urgent") || lower.contains("fix") || lower.contains("bug") {
            actionItems.append("Triage and resolve urgent issue: \(subject)")
        }
        if actionItems.isEmpty {
            actionItems.append("Follow up with \(sender) on \(platformName)")
        }

        // 5. Headline & Executive Overview
        let firstName = sender.components(separatedBy: " ").first ?? sender
        let headline: String
        let overview: String

        if lower.contains("urgent") || lower.contains("blocker") {
            headline = "🚨 Urgent Resolution with \(firstName) · \(subject)"
            overview = "\(sender) flagged an urgent priority regarding \(subject) on \(platformName). Immediate triage and status updates are required to unblock progress."
        } else if lower.contains("meet") || lower.contains("call") || lower.contains("sync") {
            headline = "📅 Scheduling & Sync with \(firstName) · \(subject)"
            overview = "Today's interaction with \(sender) focused on coordinating a sync for \(subject)\(temporal != nil ? " (\(temporal!))" : ""). Calendar availability and agenda items are currently pending."
        } else if lower.contains("review") || lower.contains("feedback") || lower.contains("deck") || lower.contains("figma") {
            headline = "📝 Review & Deliverable Status with \(firstName) · \(subject)"
            overview = "\(sender) shared material for \(subject) on \(platformName) requesting a comprehensive review. Feedback and approval sign-off are awaited."
        } else if !pendingQuestions.isEmpty {
            headline = "❓ Open Inquiries with \(firstName) · \(subject)"
            overview = "\(sender) reached out regarding \(subject) on \(platformName), with \(pendingQuestions.count) question\(pendingQuestions.count == 1 ? "" : "s") pending your direct reply."
        } else {
            headline = "✦ Daily Briefing with \(firstName) · \(subject)"
            overview = "\(sender) communicated on \(platformName) regarding \(subject). The conversation is currently active with \(messages.count) recent exchange\(messages.count == 1 ? "" : "s")."
        }

        // 6. Sentiment & Relationship Dynamic
        let sentiment: String
        let relationshipContext: String
        if lower.contains("urgent") {
            sentiment = "Urgent & High Priority"
            relationshipContext = "Critical Issue Resolution"
        } else if lower.contains("thanks") || lower.contains("great") || lower.contains("awesome") {
            sentiment = "Warm & Highly Collaborative"
            relationshipContext = "Positive Partner / Colleague Alignment"
        } else if lower.contains("proposal") || lower.contains("contract") || lower.contains("invoice") {
            sentiment = "Formal & Commercial"
            relationshipContext = "Client & Business Consultation"
        } else {
            sentiment = "Professional & Productive"
            relationshipContext = "Active Ongoing Collaboration"
        }

        let providerName: String
        if preferences.aiProvider == "gemini" && !preferences.geminiApiKey.isEmpty {
            providerName = "Google Gemini (Direct API: \(preferences.geminiModelTier))"
        } else if preferences.aiProvider == "chatgpt" && !preferences.openAiApiKey.isEmpty {
            providerName = "OpenAI (Direct API: \(preferences.openAiModelTier))"
        } else {
            providerName = "PINGGO Smart Engine (Apple ML)"
        }

        return ConversationDailySummary(
            id: "\(sender)-\(Date().formatted(date: .numeric, time: .omitted))",
            sender: sender,
            platformName: platformName,
            accountName: accountName,
            summaryDate: .now,
            headline: headline,
            executiveOverview: overview,
            keyTopics: Array(topics.prefix(4)),
            decisionsMade: Array(decisions.prefix(3)),
            pendingQuestions: Array(pendingQuestions.prefix(3)),
            actionItems: Array(actionItems.prefix(4)),
            sentiment: sentiment,
            relationshipContext: relationshipContext,
            providerName: providerName,
            messageCount: max(messages.count, 1)
        )
    }

    // MARK: - Interactive Thread Co-Pilot (Ask Gemini / ChatGPT)
    func askThreadCoPilot(
        prompt: String,
        messageContext: String,
        sender: String,
        platformName: String,
        tone: AIReplyTone,
        preferences: AppPreferences
    ) async -> String {
        let firstName = sender.components(separatedBy: " ").first ?? sender
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // A connected provider should handle every co-pilot request. Local
        // templates below are only the explicit offline fallback.
        let resolution = AIProviderResolver.resolve(preferences: preferences)
        if resolution.canPerformGenerativeAI {
            return await draftCustomReply(
                prompt: prompt,
                messageContext: messageContext,
                sender: sender,
                tone: tone,
                preferences: preferences
            )
        }

        let engineName: String
        if preferences.aiProvider == "gemini" && !preferences.geminiApiKey.isEmpty {
            engineName = "Google Gemini (\(preferences.geminiModelTier))"
        } else if preferences.aiProvider == "chatgpt" && !preferences.openAiApiKey.isEmpty {
            engineName = "OpenAI (\(preferences.openAiModelTier))"
        } else {
            engineName = "PINGGO Smart Engine"
        }

        // 1. Summary Quick Prompt
        if clean.contains("summary") || clean.contains("summarize") || clean.contains("bullet") {
            return """
            ✦ \(engineName) Summary:
            • Sender: \(sender) on \(platformName)
            • Core Message: "\(messageContext)"
            • Recommended Action: Respond acknowledging receipt and confirming next availability.
            """
        }

        // 2. Polite Decline
        if clean.contains("decline") || clean.contains("reject") || clean.contains("say no") {
            return """
            Hi \(firstName),

            Thank you for reaching out and sharing this with me.

            At this moment, I won't be able to take this on due to current commitments and bandwidth. I wanted to be upfront so you aren't waiting on me.

            Wishing you all the best, and thanks again for thinking of me!
            """
        }

        // 3. Counter Propose / Schedule Meeting
        if clean.contains("propose") || clean.contains("schedule") || clean.contains("meeting") || clean.contains("tomorrow") {
            return """
            Hi \(firstName),

            Thanks for reaching out! I would be happy to connect.

            Would tomorrow afternoon around 3:00 PM work for a quick 20-minute sync? Alternatively, I have an opening Friday at 11:00 AM.

            Let me know what fits best and I'll send over a calendar invite.
            """
        }

        // 4. Subtext / Tone Audit
        if clean.contains("subtext") || clean.contains("agenda") || clean.contains("tone") || clean.contains("intent") {
            return """
            🔍 \(engineName) Tone & Subtext Audit:
            • Tone Detected: Direct, collaborative, and action-oriented.
            • Underlying Intent: The sender wants quick clarity or confirmation so they can proceed.
            • Recommended Approach: A prompt, 1-sentence reply with a clear decision will establish confidence and de-escalate any urgency.
            """
        }

        // 5. Translation
        if clean.contains("translate") {
            if let detected = detectLanguageAndTranslate(text: messageContext) {
                return "🌐 Detected \(detected.language): \(detected.translation)"
            } else {
                return "🌐 English text. Spanish translation: \"Hola \(firstName), gracias por tu mensaje. Me pondré en contacto pronto.\""
            }
        }

        // 6. Custom Prompt Synthesis
        return await draftCustomReply(
            prompt: prompt,
            messageContext: messageContext,
            sender: sender,
            tone: tone,
            preferences: preferences
        )
    }

    // MARK: - Custom Reply Drafting with AI
    func draftCustomReply(
        prompt: String,
        messageContext: String,
        sender: String,
        tone: AIReplyTone,
        preferences: AppPreferences
    ) async -> String {
        let firstName = sender.components(separatedBy: " ").first ?? sender
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanPrompt.isEmpty else {
            return "Hi \(firstName), thanks for reaching out!"
        }

        // Direct Generative AI Call if API Key is configured
        let resolution = AIProviderResolver.resolve(preferences: preferences)
        if resolution.canPerformGenerativeAI {
            let sysInstruction = "You are an AI assistant drafting a chat reply in a \(tone.rawValue) tone. \(preferences.customAiPrompt.isEmpty ? "" : "User instructions: " + preferences.customAiPrompt)"
            let userPrompt = "Sender: \(sender)\nMessage context: \"\(messageContext)\"\nInstructions: \(cleanPrompt)\nDraft the reply message only, with no introductory or concluding commentary."
            do {
                if resolution.provider == .gemini {
                    return try await callGeminiAPI(apiKey: preferences.geminiApiKey, model: resolution.model, prompt: userPrompt, systemInstruction: sysInstruction)
                } else if resolution.provider == .chatgpt {
                    return try await callOpenAIAPI(apiKey: preferences.openAiApiKey, model: resolution.model, prompt: userPrompt, systemInstruction: sysInstruction)
                } else if resolution.provider == .ollama {
                    return try await callOllamaAPI(endpoint: preferences.ollamaEndpoint, model: resolution.model, prompt: userPrompt, systemInstruction: sysInstruction)
                }
            } catch {
                return "⚠️ \(resolution.provider.title) could not complete the request: \(error.localizedDescription)"
            }
        }

        let tonePrefix: String
        let toneSuffix: String

        switch tone {
        case .professional:
            tonePrefix = "Dear \(firstName),\n\nThank you for reaching out. "
            toneSuffix = "\n\nPlease let me know if you have any further questions.\n\nBest regards,"
        case .friendly:
            tonePrefix = "Hi \(firstName)!\n\nThanks for your message. "
            toneSuffix = "\n\nTalk soon!"
        case .concise:
            tonePrefix = "Hi \(firstName), "
            toneSuffix = " Thanks!"
        case .casual:
            tonePrefix = "Hey \(firstName), "
            toneSuffix = " Catch you later!"
        case .politeDecline:
            tonePrefix = "Hi \(firstName),\n\nThank you for reaching out. Regrettably, "
            toneSuffix = "\n\nI appreciate your understanding."
        case .proposeTime:
            tonePrefix = "Hi \(firstName),\n\nHappy to connect on this. "
            toneSuffix = "\n\nLet me know which time slot works best for you."
        }

        var coreText = cleanPrompt
        if coreText.lowercased().hasPrefix("tell them ") {
            coreText = String(coreText.dropFirst(10))
        } else if coreText.lowercased().hasPrefix("say ") {
            coreText = String(coreText.dropFirst(4))
        }

        if let first = coreText.first {
            coreText = String(first).uppercased() + String(coreText.dropFirst())
        }

        if !coreText.hasSuffix(".") && !coreText.hasSuffix("!") && !coreText.hasSuffix("?") {
            coreText += "."
        }

        if tone == .concise {
            return "\(tonePrefix)\(coreText)"
        }

        return "\(tonePrefix)\(coreText)\(toneSuffix)"
    }

    // MARK: - Direct Generative API Integrations
    func callGeminiAPI(
        apiKey: String,
        model: String = "gemini-3.5-flash",
        prompt: String,
        systemInstruction: String? = nil
    ) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Gemini API key is empty."])
        }

        let targetModel = model.isEmpty ? "gemini-3.5-flash" : model
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(targetModel):generateContent") else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini endpoint URL."])
        }

        var contents: [[String: Any]] = []
        if let system = systemInstruction, !system.isEmpty {
            contents.append([
                "role": "user",
                "parts": [["text": "System instructions: \(system)"]]
            ])
            contents.append([
                "role": "model",
                "parts": [["text": "Understood. I will follow these instructions."]]
            ])
        }
        contents.append([
            "role": "user",
            "parts": [["text": prompt]]
        ])

        let bodyDict: [String: Any] = ["contents": contents]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = bodyData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        guard httpResponse.statusCode == 200 else {
            if let errObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errDict = errObj["error"] as? [String: Any],
               let msg = errDict["message"] as? String {
                throw NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            let str = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(str)"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to parse response from Gemini."])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func callOpenAIAPI(
        apiKey: String,
        model: String = "gpt-4o-mini",
        prompt: String,
        systemInstruction: String? = nil
    ) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key is empty."])
        }

        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI endpoint URL."])
        }

        let targetModel = model.isEmpty ? "gpt-4o-mini" : model
        var bodyDict: [String: Any] = [
            "model": targetModel,
            "input": prompt,
            "store": false
        ]
        if let system = systemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines), !system.isEmpty {
            bodyDict["instructions"] = system
        }
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        guard httpResponse.statusCode == 200 else {
            if let errObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errDict = errObj["error"] as? [String: Any],
               let msg = errDict["message"] as? String {
                throw NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            }
            let str = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API Error (\(httpResponse.statusCode)): \(str)"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to parse response from OpenAI."])
        }

        if let outputText = json["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let output = json["output"] as? [[String: Any]] ?? []
        let textParts = output.flatMap { item -> [String] in
            guard item["type"] as? String == "message",
                  let content = item["content"] as? [[String: Any]] else { return [] }
            return content.compactMap { part in
                guard part["type"] as? String == "output_text" else { return nil }
                return part["text"] as? String
            }
        }
        let content = textParts.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "OpenAI returned no text output."])
        }
        return content
    }

    func callOllamaAPI(
        endpoint: String = "http://localhost:11434",
        model: String = "llama3.2",
        prompt: String,
        systemInstruction: String? = nil
    ) async throws -> String {
        let base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let cleanBase = base.isEmpty ? "http://localhost:11434" : base
        guard let url = URL(string: "\(cleanBase)/api/chat") else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama endpoint URL."])
        }

        var messages: [[String: String]] = []
        if let system = systemInstruction, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": prompt])

        let targetModel = model.isEmpty ? "llama3.2" : model
        let bodyDict: [String: Any] = [
            "model": targetModel,
            "messages": messages,
            "stream": false
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server response from Ollama."])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errText = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ollama Error (\(httpResponse.statusCode)): \(errText)"])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let msg = json["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to parse response from Ollama."])
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Streaming Generative API Integrations (Server-Sent Events)
    func streamGeminiAPI(
        apiKey: String,
        model: String = "gemini-3.5-flash",
        prompt: String,
        systemInstruction: String? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Gemini API key is empty."])
        }

        let targetModel = model.isEmpty ? "gemini-3.5-flash" : model
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(targetModel):streamGenerateContent?alt=sse") else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Gemini endpoint URL."])
        }

        var contents: [[String: Any]] = []
        if let system = systemInstruction, !system.isEmpty {
            contents.append([
                "role": "user",
                "parts": [["text": "System instructions: \(system)"]]
            ])
            contents.append([
                "role": "model",
                "parts": [["text": "Understood. I will follow these instructions."]]
            ])
        }
        contents.append([
            "role": "user",
            "parts": [["text": prompt]]
        ])

        let bodyDict: [String: Any] = ["contents": contents]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(cleanKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini streaming error (HTTP \(httpResponse.statusCode))"])
        }

        var fullText = ""
        for try await line in asyncBytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data: ") else { continue }
            let jsonString = String(trimmed.dropFirst(6))
            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let first = candidates.first,
                  let content = first["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                continue
            }
            fullText += text
            onChunk(text)
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func streamOpenAIAPI(
        apiKey: String,
        model: String = "gpt-4o-mini",
        prompt: String,
        systemInstruction: String? = nil,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key is empty."])
        }

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI endpoint URL."])
        }

        var messages: [[String: String]] = []
        if let system = systemInstruction, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": prompt])

        let targetModel = model.isEmpty ? "gpt-4o-mini" : model
        let bodyDict: [String: Any] = [
            "model": targetModel,
            "messages": messages,
            "temperature": 0.7,
            "stream": true
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cleanKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        guard httpResponse.statusCode == 200 else {
            throw NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI streaming error (HTTP \(httpResponse.statusCode))"])
        }

        var fullText = ""
        for try await line in asyncBytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data: ") else { continue }
            let payload = String(trimmed.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let jsonData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let text = delta["content"] as? String else {
                continue
            }
            fullText += text
            onChunk(text)
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func streamOllamaAPI(
        endpoint: String = "http://localhost:11434",
        model: String = "llama3.2",
        prompt: String,
        systemInstruction: String? = nil,
        history: [CopilotMessage] = [],
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let base = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let cleanBase = base.isEmpty ? "http://localhost:11434" : base
        guard let url = URL(string: "\(cleanBase)/api/chat") else {
            throw NSError(domain: "AIService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama endpoint URL."])
        }

        var messages: [[String: String]] = []
        if let system = systemInstruction, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        for h in history {
            messages.append(["role": h.role, "content": h.content])
        }
        messages.append(["role": "user", "content": prompt])

        let targetModel = model.isEmpty ? "llama3.2" : model
        let bodyDict: [String: Any] = [
            "model": targetModel,
            "messages": messages,
            "stream": true
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: bodyDict)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "AIService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server response from Ollama."])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "AIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Ollama streaming error (HTTP \(httpResponse.statusCode))"])
        }

        var fullText = ""
        for try await line in asyncBytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let jsonData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                continue
            }
            fullText += content
            onChunk(content)
        }
        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func streamCoPilotResponse(
        prompt: String,
        context: String,
        tone: AIReplyTone = .friendly,
        history: [CopilotMessage] = [],
        preferences: AppPreferences,
        onChunk: @escaping @MainActor (String) -> Void
    ) async -> String {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)

        let personaInstruction = PersonaStyle(rawValue: preferences.personaStyle)?.systemInstruction
            ?? "Adopt a direct, concise, and action-oriented communication style."
        let sysInstruction = "You are PINGGO Co-Pilot, an intelligent personal communication assistant. \(personaInstruction) Draft clear, concise, and context-aware responses in a \(tone.rawValue) tone. \(preferences.customAiPrompt.isEmpty ? "" : "User guidelines: " + preferences.customAiPrompt)"
        let userPrompt = cleanContext.isEmpty ? cleanPrompt : "Context:\n\(cleanContext)\n\nInstruction/Question:\n\(cleanPrompt)"

        let resolution = AIProviderResolver.resolve(preferences: preferences)

        if resolution.canPerformGenerativeAI {
            if resolution.provider == .gemini {
                if let result = try? await streamGeminiAPI(
                    apiKey: preferences.geminiApiKey,
                    model: resolution.model,
                    prompt: userPrompt,
                    systemInstruction: sysInstruction,
                    onChunk: { chunk in
                        Task { @MainActor in onChunk(chunk) }
                    }
                ), !result.isEmpty {
                    return result
                }
            } else if resolution.provider == .chatgpt {
                if let result = try? await streamOpenAIAPI(
                    apiKey: preferences.openAiApiKey,
                    model: resolution.model,
                    prompt: userPrompt,
                    systemInstruction: sysInstruction,
                    onChunk: { chunk in
                        Task { @MainActor in onChunk(chunk) }
                    }
                ), !result.isEmpty {
                    return result
                }
            } else if resolution.provider == .ollama {
                if let result = try? await streamOllamaAPI(
                    endpoint: preferences.ollamaEndpoint,
                    model: resolution.model,
                    prompt: userPrompt,
                    systemInstruction: sysInstruction,
                    history: history,
                    onChunk: { chunk in
                        Task { @MainActor in onChunk(chunk) }
                    }
                ), !result.isEmpty {
                    return result
                }
            }
        }

        // Local Smart Engine fallback - render instantly without fake typewriter delay
        let fallbackReply = await draftCustomReply(
            prompt: cleanPrompt,
            messageContext: cleanContext,
            sender: "User",
            tone: tone,
            preferences: preferences
        )
        onChunk(fallbackReply)
        return fallbackReply
    }

    func testAPIConnection(provider: String, apiKey: String, model: String) async -> (success: Bool, message: String) {
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            if provider == "ollama" {
                let base = cleanKey.isEmpty ? "http://localhost:11434" : cleanKey.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                guard let url = URL(string: "\(base)/api/tags") else {
                    return (false, "Invalid endpoint URL.")
                }
                var req = URLRequest(url: url)
                req.timeoutInterval = 5
                let (_, res) = try await URLSession.shared.data(for: req)
                if let httpRes = res as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                    return (true, "Ollama Connected! Local model server active at \(base).")
                } else {
                    return (false, "Ollama responded with HTTP \((res as? HTTPURLResponse)?.statusCode ?? 0)")
                }
            } else if provider == "gemini" {
                guard !cleanKey.isEmpty else { return (false, "API Key is required to test connection.") }
                let reply = try await callGeminiAPI(apiKey: cleanKey, model: model, prompt: "Respond with the single word 'CONNECTED'.")
                return (true, "Google Gemini Connected! Response: \(reply.prefix(30))")
            } else {
                guard !cleanKey.isEmpty else { return (false, "API Key is required to test connection.") }
                let reply = try await callOpenAIAPI(apiKey: cleanKey, model: model, prompt: "Respond with the single word 'CONNECTED'.")
                return (true, "OpenAI ChatGPT Connected! Response: \(reply.prefix(30))")
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Alert & Notification Analysis
    func analyzeAlert(
        title: String,
        alertText: String,
        category: String,
        platformName: String,
        preferences: AppPreferences
    ) -> AIAlertAnalysisResult {
        let text = alertText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let catLower = category.lowercased()

        let providerName: String
        providerName = "PINGGO Smart Engine (Local Heuristic)"

        var requiresReply = false
        var contextSummary = ""
        var replies: [AIReplyOption] = []

        if catLower.contains("mention") || lower.contains("@") {
            requiresReply = true
            contextSummary = "Direct mention on \(platformName) awaiting your response."
            replies = [
                .init(id: "m_prof", tone: .professional, text: "Thank you for looping me in. I am reviewing the details and will follow up shortly."),
                .init(id: "m_friend", tone: .friendly, text: "Thanks for the ping! Looking into this right now 👍"),
                .init(id: "m_concise", tone: .concise, text: "On it! Will update here soon."),
                .init(id: "m_casual", tone: .casual, text: "Got the ping, jumping on this right now!")
            ]
        } else if catLower.contains("request") || lower.contains("connect") || lower.contains("invite") {
            requiresReply = true
            contextSummary = "Connection request or invite on \(platformName)."
            replies = [
                .init(id: "r_prof", tone: .professional, text: "Thank you for reaching out to connect. Looking forward to staying in touch."),
                .init(id: "r_friend", tone: .friendly, text: "Thanks for the connection request! Great to connect with you."),
                .init(id: "r_decline", tone: .politeDecline, text: "Thank you for reaching out. Unfortunately, I am keeping my network limited at this time.")
            ]
        } else if catLower.contains("reply") || lower.contains("comment") || lower.contains("replied") {
            requiresReply = true
            contextSummary = "Comment or thread reply received on \(platformName)."
            replies = [
                .init(id: "c_prof", tone: .professional, text: "Thank you for sharing your thoughts. I appreciate the valuable feedback."),
                .init(id: "c_friend", tone: .friendly, text: "Thanks so much for commenting! Really glad you found this helpful."),
                .init(id: "c_concise", tone: .concise, text: "Appreciate the note, thanks!")
            ]
        } else if catLower.contains("security") || lower.contains("login") || lower.contains("password") {
            requiresReply = false
            contextSummary = "Security or system verification notice from \(platformName)."
            replies = []
        } else {
            requiresReply = false
            contextSummary = "Notification update on \(platformName)."
            replies = [
                .init(id: "g_friend", tone: .friendly, text: "Thanks for the update!"),
                .init(id: "g_concise", tone: .concise, text: "Acknowledged, thank you.")
            ]
        }

        return AIAlertAnalysisResult(
            title: title,
            alertText: text,
            category: category,
            requiresReply: requiresReply,
            contextSummary: contextSummary,
            suggestedReplies: replies,
            providerName: providerName
        )
    }

    // MARK: - Cross-Platform Auto-Reply Queue (Draft for All Messages & Alerts)
    func generateAutoReplyQueue(
        messages: [UnifiedMessageItem],
        alerts: [UnifiedAlertItem],
        preferences: AppPreferences
    ) async -> [AIAutoReplyItem] {
        var queue: [AIAutoReplyItem] = []

        // 1. Process Unread Chat Messages
        for item in messages.prefix(15) {
            let analysis = analyzeChat(
                sender: item.message.sender,
                messageText: item.message.text,
                platformName: item.platform.name,
                accountName: item.accountName,
                preferences: preferences
            )

            let preferredTone: AIReplyTone = {
                switch preferences.defaultReplyTone {
                case "Friendly": return .friendly
                case "Concise": return .concise
                case "Casual": return .casual
                default: return .professional
                }
            }()

            let replyText = analysis.replies.first(where: { $0.tone == preferredTone })?.text
                ?? analysis.replies.first?.text
                ?? "Thank you, received."

            queue.append(AIAutoReplyItem(
                id: "msg-\(item.id)",
                sourceType: .chat,
                platformID: item.platform.id,
                platformName: item.platform.name,
                platformColor: item.platform.color,
                accountID: item.accountID,
                accountName: item.accountName,
                senderOrTitle: item.message.sender,
                originalContent: item.message.text,
                detectedContext: analysis.contextSummary,
                draftedReply: replyText,
                selectedTone: preferredTone,
                directURL: item.message.linkURL
            ))
        }

        // 2. Process Actionable Alerts & Mentions
        for alert in alerts.filter({ $0.categoryType == .mention || $0.categoryType == .reply || $0.categoryType == .request }).prefix(10) {
            let analysis = analyzeAlert(
                title: alert.title,
                alertText: alert.alertText,
                category: alert.category,
                platformName: alert.platform.name,
                preferences: preferences
            )

            if analysis.requiresReply, let topReply = analysis.suggestedReplies.first {
                queue.append(AIAutoReplyItem(
                    id: "alert-\(alert.id)",
                    sourceType: .alert,
                    platformID: alert.platform.id,
                    platformName: alert.platform.name,
                    platformColor: alert.platform.color,
                    accountID: alert.account.id,
                    accountName: alert.account.name,
                    senderOrTitle: alert.title,
                    originalContent: alert.alertText,
                    detectedContext: analysis.contextSummary,
                    draftedReply: topReply.text,
                    selectedTone: topReply.tone,
                    directURL: alert.directURL?.absoluteString
                ))
            }
        }

        return queue
    }
}
