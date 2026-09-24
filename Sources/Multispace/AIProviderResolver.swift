import Foundation

enum AIProviderType: String, CaseIterable, Codable {
    case gemini = "gemini"
    case chatgpt = "chatgpt"
    case ollama = "ollama"
    case smart = "smart"

    var title: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .chatgpt: return "OpenAI ChatGPT"
        case .ollama: return "Ollama (Local)"
        case .smart: return "Pinggo Smart Engine"
        }
    }
}

enum AIAuthMode: String, Codable {
    case directApiKey = "Direct API Key"
    case localServer = "Local Server"
    case webSessionReadOnly = "Web Session (Read Only)"
    case none = "None"
}

enum AIProviderAvailability: Equatable {
    case ready
    case unconfigured(String)
    case authenticationRequired(String)
    case rateLimited(String)
    case error(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .ready:
            return "Ready"
        case .unconfigured(let msg),
             .authenticationRequired(let msg),
             .rateLimited(let msg),
             .error(let msg):
            return msg
        }
    }
}

struct AIProviderCapabilities: OptionSet {
    let rawValue: Int

    static let summarize     = AIProviderCapabilities(rawValue: 1 << 0)
    static let chat          = AIProviderCapabilities(rawValue: 1 << 1)
    static let draftReply    = AIProviderCapabilities(rawValue: 1 << 2)
    static let translate     = AIProviderCapabilities(rawValue: 1 << 3)
    static let stream        = AIProviderCapabilities(rawValue: 1 << 4)

    static let fullSuite: AIProviderCapabilities = [.summarize, .chat, .draftReply, .translate, .stream]
    static let localHeuristic: AIProviderCapabilities = [.summarize, .chat]
}

struct AIProviderResolution: Equatable {
    let provider: AIProviderType
    let model: String
    let authMode: AIAuthMode
    let availability: AIProviderAvailability
    let capabilities: AIProviderCapabilities
    let displayBadge: String

    var canPerformGenerativeAI: Bool {
        availability.isReady && (authMode == .directApiKey || authMode == .localServer)
    }
}

final class AIProviderResolver {
    static func resolve(preferences: AppPreferences) -> AIProviderResolution {
        guard preferences.aiEnabled else {
            return AIProviderResolution(
                provider: .smart,
                model: "Local Engine",
                authMode: .none,
                availability: .unconfigured("AI is disabled in Settings."),
                capabilities: .localHeuristic,
                displayBadge: "AI Disabled"
            )
        }

        let rawProvider = preferences.aiProvider.lowercased()

        switch rawProvider {
        case "gemini":
            let model = preferences.geminiModelTier.isEmpty ? "gemini-3.5-flash" : preferences.geminiModelTier
            let apiKey = preferences.geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            if !apiKey.isEmpty && preferences.isGeminiLoggedIn {
                return AIProviderResolution(
                    provider: .gemini,
                    model: model,
                    authMode: .directApiKey,
                    availability: .ready,
                    capabilities: .fullSuite,
                    displayBadge: "Google Gemini · \(model)"
                )
            } else if !apiKey.isEmpty {
                return AIProviderResolution(
                    provider: .gemini,
                    model: model,
                    authMode: .directApiKey,
                    availability: .authenticationRequired("Validate the saved Gemini credential in Settings > AI."),
                    capabilities: .localHeuristic,
                    displayBadge: "Gemini (Validation Required)"
                )
            } else {
                return AIProviderResolution(
                    provider: .gemini,
                    model: model,
                    authMode: .none,
                    availability: .unconfigured("Google Gemini API Key is required. Configure it in Settings > AI."),
                    capabilities: .localHeuristic,
                    displayBadge: "Google Gemini (Unconfigured)"
                )
            }

        case "chatgpt":
            let model = preferences.openAiModelTier.isEmpty ? "gpt-4o-mini" : preferences.openAiModelTier
            let apiKey = preferences.openAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            if !apiKey.isEmpty && preferences.isChatGptLoggedIn {
                return AIProviderResolution(
                    provider: .chatgpt,
                    model: model,
                    authMode: .directApiKey,
                    availability: .ready,
                    capabilities: .fullSuite,
                    displayBadge: "OpenAI · \(model)"
                )
            } else if !apiKey.isEmpty {
                return AIProviderResolution(
                    provider: .chatgpt,
                    model: model,
                    authMode: .directApiKey,
                    availability: .authenticationRequired("Validate the saved OpenAI credential in Settings > AI."),
                    capabilities: .localHeuristic,
                    displayBadge: "OpenAI (Validation Required)"
                )
            } else {
                return AIProviderResolution(
                    provider: .chatgpt,
                    model: model,
                    authMode: .none,
                    availability: .unconfigured("OpenAI API Key is required. Configure it in Settings > AI."),
                    capabilities: .localHeuristic,
                    displayBadge: "OpenAI (Unconfigured)"
                )
            }

        case "ollama":
            let model = preferences.ollamaModelTier.isEmpty ? preferences.ollamaModel : preferences.ollamaModelTier
            let endpoint = preferences.ollamaEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveModel = model.isEmpty ? "llama3.2" : model

            if !endpoint.isEmpty {
                return AIProviderResolution(
                    provider: .ollama,
                    model: effectiveModel,
                    authMode: .localServer,
                    availability: .ready,
                    capabilities: .fullSuite,
                    displayBadge: "Ollama · \(effectiveModel)"
                )
            } else {
                return AIProviderResolution(
                    provider: .ollama,
                    model: effectiveModel,
                    authMode: .none,
                    availability: .unconfigured("Ollama endpoint URL is missing. Set to http://localhost:11434 in Settings > AI."),
                    capabilities: .localHeuristic,
                    displayBadge: "Ollama (Unconfigured)"
                )
            }

        default: // "smart" or local
            return AIProviderResolution(
                provider: .smart,
                model: "Pinggo Smart Engine",
                authMode: .none,
                availability: .ready,
                capabilities: .localHeuristic,
                displayBadge: "Pinggo Smart Engine"
            )
        }
    }
}
