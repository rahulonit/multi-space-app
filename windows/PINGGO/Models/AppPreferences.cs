using System.Text.Json.Serialization;

namespace PINGGO.Models
{
    public class AppPreferences
    {
        [JsonPropertyName("language")]
        public string Language { get; set; } = "Follow System";

        [JsonPropertyName("appearance")]
        public string Appearance { get; set; } = "Follow System"; // "Dark", "Light", "Follow System"

        [JsonPropertyName("accent")]
        public string Accent { get; set; } = "indigo";

        [JsonPropertyName("compactMode")]
        public bool CompactMode { get; set; } = false;

        [JsonPropertyName("openTo")]
        public string OpenTo { get; set; } = "Home";

        [JsonPropertyName("launchWebsites")]
        public bool LaunchWebsites { get; set; } = true;

        [JsonPropertyName("launchDelay")]
        public int LaunchDelay { get; set; } = 0;

        [JsonPropertyName("showWebsiteAlerts")]
        public bool ShowWebsiteAlerts { get; set; } = true;

        [JsonPropertyName("appLockEnabled")]
        public bool AppLockEnabled { get; set; } = false;

        [JsonPropertyName("autoLockMinutes")]
        public int AutoLockMinutes { get; set; } = 5;

        [JsonPropertyName("tabFreezingEnabled")]
        public bool TabFreezingEnabled { get; set; } = true;

        [JsonPropertyName("tabFreezeMinutes")]
        public int TabFreezeMinutes { get; set; } = 15;

        [JsonPropertyName("lockMethod")]
        public string LockMethod { get; set; } = "biometric"; // "biometric", "customPin", "both"

        [JsonPropertyName("customPinHash")]
        public string CustomPinHash { get; set; } = string.Empty;

        [JsonPropertyName("customPinSalt")]
        public string CustomPinSalt { get; set; } = string.Empty;

        [JsonPropertyName("customPinHint")]
        public string CustomPinHint { get; set; } = string.Empty;

        // MARK: - AI Assistant Preferences
        [JsonPropertyName("aiEnabled")]
        public bool AiEnabled { get; set; } = true;

        [JsonPropertyName("aiProvider")]
        public string AiProvider { get; set; } = "gemini"; // "gemini" or "chatgpt"

        [JsonPropertyName("isGeminiLoggedIn")]
        public bool IsGeminiLoggedIn { get; set; } = false;

        [JsonPropertyName("geminiAccountEmail")]
        public string GeminiAccountEmail { get; set; } = string.Empty;

        [JsonPropertyName("isChatGptLoggedIn")]
        public bool IsChatGptLoggedIn { get; set; } = false;

        [JsonPropertyName("chatGptAccountEmail")]
        public string ChatGptAccountEmail { get; set; } = string.Empty;

        [JsonPropertyName("geminiApiKey")]
        [JsonIgnore]
        public string GeminiApiKey { get; set; } = string.Empty;

        [JsonPropertyName("openAiApiKey")]
        [JsonIgnore]
        public string OpenAiApiKey { get; set; } = string.Empty;

        [JsonPropertyName("aiModelTier")]
        public string AiModelTier { get; set; } = "gemini-2.5-flash";

        [JsonPropertyName("geminiModelTier")]
        public string GeminiModelTier { get; set; } = "gemini-2.5-flash";

        [JsonPropertyName("openAiModelTier")]
        public string OpenAiModelTier { get; set; } = "gpt-4o-mini";

        [JsonPropertyName("ollamaModelTier")]
        public string OllamaModelTier { get; set; } = "llama3.2";

        [JsonPropertyName("ollamaEndpoint")]
        public string OllamaEndpoint { get; set; } = "http://localhost:11434";

        [JsonPropertyName("ollamaModel")]
        public string OllamaModel { get; set; } = "llama3.2";

        [JsonPropertyName("personaStyle")]
        public string PersonaStyle { get; set; } = "Direct & Crisp";

        [JsonPropertyName("stealthModeDefault")]
        public bool StealthModeDefault { get; set; } = true;

        [JsonPropertyName("defaultReplyTone")]
        public string DefaultReplyTone { get; set; } = "Professional";

        [JsonPropertyName("customAiPrompt")]
        public string CustomAiPrompt { get; set; } = string.Empty;

        // MARK: - Browser & AdBlock Preferences
        [JsonPropertyName("adBlockBlockAds")]
        public bool AdBlockBlockAds { get; set; } = true;

        [JsonPropertyName("adBlockBlockTrackers")]
        public bool AdBlockBlockTrackers { get; set; } = true;

        [JsonPropertyName("adBlockBlockCookieBanners")]
        public bool AdBlockBlockCookieBanners { get; set; } = true;
    }
}
