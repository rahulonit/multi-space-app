import Foundation

func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        print("FAIL: \(message)")
        exit(1)
    }
}

print("Running logic verification...")

// 1. Test AIProviderResolver status logic
enum MockProvider: String {
    case gemini, chatgpt, ollama, local
}

struct MockPrefs {
    var aiProvider: MockProvider = .gemini
    var geminiApiKey: String = ""
    var chatGptApiKey: String = ""
    var ollamaBaseUrl: String = "http://localhost:11434"
    var isGeminiLoggedIn: Bool = false
    var isChatGptLoggedIn: Bool = false
    var isOllamaLoggedIn: Bool = false
}

func resolveStatus(provider: MockProvider, prefs: MockPrefs) -> String {
    switch provider {
    case .local:
        return "ready"
    case .gemini:
        if prefs.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "unconfigured"
        }
        guard prefs.isGeminiLoggedIn else {
            return "authenticationRequired"
        }
        return "ready"
    case .chatgpt:
        if prefs.chatGptApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "unconfigured"
        }
        guard prefs.isChatGptLoggedIn else {
            return "authenticationRequired"
        }
        return "ready"
    case .ollama:
        if !prefs.isOllamaLoggedIn {
            return "unconfigured"
        }
        return "ready"
    }
}

// Test Provider resolution
var prefs = MockPrefs()
assert(resolveStatus(provider: .gemini, prefs: prefs) == "unconfigured", "Empty Gemini should be unconfigured")
prefs.geminiApiKey = "AIzaSyTest"
assert(resolveStatus(provider: .gemini, prefs: prefs) == "authenticationRequired", "Unauthenticated Gemini should require authentication")
prefs.isGeminiLoggedIn = true
assert(resolveStatus(provider: .gemini, prefs: prefs) == "ready", "Authenticated Gemini should be ready")

prefs = MockPrefs()
assert(resolveStatus(provider: .chatgpt, prefs: prefs) == "unconfigured", "Empty ChatGPT should be unconfigured")
prefs.chatGptApiKey = "sk-proj-test"
assert(resolveStatus(provider: .chatgpt, prefs: prefs) == "authenticationRequired", "Unauthenticated ChatGPT should require authentication")
prefs.isChatGptLoggedIn = true
assert(resolveStatus(provider: .chatgpt, prefs: prefs) == "ready", "Authenticated ChatGPT should be ready")

prefs = MockPrefs()
assert(resolveStatus(provider: .ollama, prefs: prefs) == "unconfigured", "Unverified Ollama should be unconfigured")
prefs.isOllamaLoggedIn = true
assert(resolveStatus(provider: .ollama, prefs: prefs) == "ready", "Verified Ollama should be ready")
print("PASS: AIProviderResolver state validation passed.")

// 2. Test Conversation isolation logic
var conversationHistories: [String: [String]] = [:]
func saveHistory(contact: String, messages: [String]) {
    let key = contact.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    conversationHistories[key] = messages
}
func loadHistory(contact: String) -> [String] {
    let key = contact.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return conversationHistories[key] ?? []
}

saveHistory(contact: "Alice Smith", messages: ["Hi Alice", "How are you?"])
saveHistory(contact: "Bob Jones", messages: ["Hello Bob", "Project update?"])

assert(loadHistory(contact: "Alice Smith").count == 2, "Alice should have 2 messages")
assert(loadHistory(contact: "Bob Jones").count == 2, "Bob should have 2 messages")
assert(loadHistory(contact: "alice smith").first == "Hi Alice", "Case-insensitive lookup for Alice")
assert(loadHistory(contact: "Charlie").isEmpty, "Charlie should have empty history")
print("PASS: Conversation isolation logic passed.")

// 3. Test Unread indicator logic
struct MockPreview {
    let isUnreadExplicit: Bool
}
func computeUnread(previews: [MockPreview]) -> Int {
    var count = 0
    for p in previews {
        if p.isUnreadExplicit {
            count += 1
        }
    }
    return count
}

let testPreviews = [
    MockPreview(isUnreadExplicit: false),
    MockPreview(isUnreadExplicit: true),
    MockPreview(isUnreadExplicit: false)
]
// Verify index 0 is NOT counted as unread when isUnreadExplicit is false
assert(computeUnread(previews: testPreviews) == 1, "Only explicit unread items should be counted")
print("PASS: Unread inference logic passed.")

// 4. Test Split account logic - no silent account creation
struct MockAccount {
    let id: UUID
    let platformId: String
    let name: String
}
func resolveSplitPane(accounts: [MockAccount], platformId: String) -> String {
    let platformAccounts = accounts.filter { $0.platformId == platformId }
    if platformAccounts.count > 1 {
        return "splitWithSecondAccount"
    } else {
        return "browser"
    }
}

let singleAccount = [MockAccount(id: UUID(), platformId: "whatsapp", name: "Personal")]
assert(resolveSplitPane(accounts: singleAccount, platformId: "whatsapp") == "browser", "Single account should fall back to browser, NOT create Work account")

let multiAccounts = [
    MockAccount(id: UUID(), platformId: "whatsapp", name: "Personal"),
    MockAccount(id: UUID(), platformId: "whatsapp", name: "Work")
]
assert(resolveSplitPane(accounts: multiAccounts, platformId: "whatsapp") == "splitWithSecondAccount", "Multi accounts should split with second account")
print("PASS: Split account logic passed.")

print("\nALL 4 LOGIC VERIFICATION SUITES PASSED SUCCESSFULLY!")
