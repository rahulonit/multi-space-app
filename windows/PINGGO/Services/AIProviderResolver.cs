using System;
using PINGGO.Models;

namespace PINGGO.Services
{
    public enum AIProviderType
    {
        Gemini,
        ChatGpt,
        Ollama,
        Smart
    }

    public enum AIAuthMode
    {
        DirectApiKey,
        LocalServer,
        WebSessionReadOnly,
        None
    }

    public enum AIProviderStatus
    {
        Ready,
        Unconfigured,
        AuthenticationRequired,
        RateLimited,
        Error
    }

    public class AIProviderResolution
    {
        public AIProviderType Provider { get; set; }
        public string Model { get; set; } = string.Empty;
        public AIAuthMode AuthMode { get; set; }
        public AIProviderStatus Status { get; set; }
        public string StatusMessage { get; set; } = string.Empty;
        public string DisplayBadge { get; set; } = string.Empty;

        public bool CanPerformGenerativeAI =>
            Status == AIProviderStatus.Ready &&
            (AuthMode == AIAuthMode.DirectApiKey || AuthMode == AIAuthMode.LocalServer);
    }

    public static class AIProviderResolver
    {
        public static AIProviderResolution Resolve(AppPreferences preferences)
        {
            if (!preferences.AiEnabled)
            {
                return new AIProviderResolution
                {
                    Provider = AIProviderType.Smart,
                    Model = "Local Engine",
                    AuthMode = AIAuthMode.None,
                    Status = AIProviderStatus.Unconfigured,
                    StatusMessage = "AI is disabled in Settings.",
                    DisplayBadge = "AI Disabled"
                };
            }

            var provider = (preferences.AiProvider ?? "gemini").Trim().ToLowerInvariant();

            switch (provider)
            {
                case "gemini":
                    var rawGeminiModel = string.IsNullOrWhiteSpace(preferences.GeminiModelTier) ? "gemini-2.5-flash" : preferences.GeminiModelTier;
                    var geminiModel = rawGeminiModel.Contains("gemini-3.5") ? "gemini-2.5-flash" : rawGeminiModel;
                    var geminiKey = (preferences.GeminiApiKey ?? string.Empty).Trim();

                    if (!string.IsNullOrEmpty(geminiKey))
                    {
                        return new AIProviderResolution
                        {
                            Provider = AIProviderType.Gemini,
                            Model = geminiModel,
                            AuthMode = AIAuthMode.DirectApiKey,
                            Status = AIProviderStatus.Ready,
                            StatusMessage = "Ready",
                            DisplayBadge = $"Google Gemini · {geminiModel}"
                        };
                    }
                    else
                    {
                        return new AIProviderResolution
                        {
                            Provider = AIProviderType.Gemini,
                            Model = geminiModel,
                            AuthMode = AIAuthMode.None,
                            Status = AIProviderStatus.Unconfigured,
                            StatusMessage = "Google Gemini API Key is required. Configure it in Settings > AI.",
                            DisplayBadge = "Google Gemini (Unconfigured)"
                        };
                    }

                case "chatgpt":
                    var openAiModel = string.IsNullOrWhiteSpace(preferences.OpenAiModelTier) ? "gpt-4o-mini" : preferences.OpenAiModelTier;
                    var openAiKey = (preferences.OpenAiApiKey ?? string.Empty).Trim();

                    if (!string.IsNullOrEmpty(openAiKey))
                    {
                        return new AIProviderResolution
                        {
                            Provider = AIProviderType.ChatGpt,
                            Model = openAiModel,
                            AuthMode = AIAuthMode.DirectApiKey,
                            Status = AIProviderStatus.Ready,
                            StatusMessage = "Ready",
                            DisplayBadge = $"OpenAI · {openAiModel}"
                        };
                    }
                    else
                    {
                        return new AIProviderResolution
                        {
                            Provider = AIProviderType.ChatGpt,
                            Model = openAiModel,
                            AuthMode = AIAuthMode.None,
                            Status = AIProviderStatus.Unconfigured,
                            StatusMessage = "OpenAI API Key is required. Configure it in Settings > AI.",
                            DisplayBadge = "OpenAI (Unconfigured)"
                        };
                    }

                case "ollama":
                    var ollamaModel = string.IsNullOrWhiteSpace(preferences.OllamaModelTier) ? preferences.OllamaModel : preferences.OllamaModelTier;
                    if (string.IsNullOrWhiteSpace(ollamaModel)) ollamaModel = "llama3.2";
                    var endpoint = (preferences.OllamaEndpoint ?? string.Empty).Trim();

                    if (!string.IsNullOrEmpty(endpoint))
                    {
                        return new AIProviderResolution
                        {
                            Provider = AIProviderType.Ollama,
                            Model = ollamaModel,
                            AuthMode = AIAuthMode.LocalServer,
                            Status = AIProviderStatus.Ready,
                            StatusMessage = "Ready",
                            DisplayBadge = $"Ollama · {ollamaModel}"
                        };
                    }
                    else
                    {
                        return new AIProviderResolution
                        {
                            Provider = AIProviderType.Ollama,
                            Model = ollamaModel,
                            AuthMode = AIAuthMode.None,
                            Status = AIProviderStatus.Unconfigured,
                            StatusMessage = "Ollama endpoint URL is missing. Set to http://localhost:11434 in Settings > AI.",
                            DisplayBadge = "Ollama (Unconfigured)"
                        };
                    }

                default:
                    return new AIProviderResolution
                    {
                        Provider = AIProviderType.Smart,
                        Model = "Pinggo Smart Engine",
                        AuthMode = AIAuthMode.None,
                        Status = AIProviderStatus.Ready,
                        StatusMessage = "Ready",
                        DisplayBadge = "Pinggo Smart Engine"
                    };
            }
        }
    }
}
