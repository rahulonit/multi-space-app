using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using PINGGO.Models;

namespace PINGGO.Services
{
    public class AppData
    {
        [JsonPropertyName("socialPlatforms")]
        public List<SocialPlatform> SocialPlatforms { get; set; } = new();

        [JsonPropertyName("platformAccounts")]
        public List<PlatformAccount> PlatformAccounts { get; set; } = new();

        [JsonPropertyName("preferences")]
        public AppPreferences Preferences { get; set; } = new();

        [JsonPropertyName("bookmarks")]
        public List<BrowserBookmark> Bookmarks { get; set; } = new();
    }

    public class DataStoreService
    {
        private static readonly Lazy<DataStoreService> _instance = new(() => new DataStoreService());
        public static DataStoreService Shared => _instance.Value;

        private readonly string _dataFilePath;
        private readonly string _appDataDirectory;

        public AppData CurrentData { get; private set; }

        public DataStoreService()
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            _appDataDirectory = Path.Combine(appData, "PINGGO");
            Directory.CreateDirectory(_appDataDirectory);
            _dataFilePath = Path.Combine(_appDataDirectory, "data.json");

            CurrentData = LoadOrCreateData();
        }

        public string GetProfileDirectory(Guid accountId)
        {
            var profilePath = Path.Combine(_appDataDirectory, "Profiles", accountId.ToString());
            Directory.CreateDirectory(profilePath);
            return profilePath;
        }

        private AppData LoadOrCreateData()
        {
            try
            {
                if (File.Exists(_dataFilePath))
                {
                    var json = File.ReadAllText(_dataFilePath);
                    var data = JsonSerializer.Deserialize<AppData>(json);
                    if (data != null)
                    {
                        string legacyGeminiKey = string.Empty;
                        string legacyOpenAiKey = string.Empty;
                        try
                        {
                            using var legacyDocument = JsonDocument.Parse(json);
                            if (legacyDocument.RootElement.TryGetProperty("preferences", out var preferences))
                            {
                                if (preferences.TryGetProperty("geminiApiKey", out var geminiKey)) legacyGeminiKey = geminiKey.GetString() ?? string.Empty;
                                if (preferences.TryGetProperty("openAiApiKey", out var openAiKey)) legacyOpenAiKey = openAiKey.GetString() ?? string.Empty;
                            }
                        }
                        catch { }

                        HydrateAICredentials(data, legacyGeminiKey, legacyOpenAiKey);
                        EnsureDefaultPlatforms(data);
                        EnsurePrimaryAccounts(data);
                        SaveData(data);
                        return data;
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DataStoreService] Error loading data.json: {ex.Message}");
            }

            // Create initial default data
            var defaultData = new AppData
            {
                SocialPlatforms = SocialPlatform.DefaultPlatforms,
                Preferences = new AppPreferences(),
                Bookmarks = new List<BrowserBookmark>
                {
                    new() { Title = "Google", UrlString = "https://www.google.com", Symbol = "magnifyingglass" },
                    new() { Title = "GitHub", UrlString = "https://github.com", Symbol = "code" },
                    new() { Title = "Hacker News", UrlString = "https://news.ycombinator.com", Symbol = "newspaper" },
                    new() { Title = "YouTube", UrlString = "https://www.youtube.com", Symbol = "play" },
                    new() { Title = "Reddit", UrlString = "https://www.reddit.com", Symbol = "chat" },
                    new() { Title = "Wikipedia", UrlString = "https://www.wikipedia.org", Symbol = "book" },
                    new() { Title = "ChatGPT", UrlString = "https://chatgpt.com", Symbol = "sparkles" },
                    new() { Title = "Microsoft", UrlString = "https://www.microsoft.com", Symbol = "laptop" }
                }
            };

            // Seed initial accounts for primary platforms
            foreach (var platform in defaultData.SocialPlatforms.Take(4))
            {
                defaultData.PlatformAccounts.Add(new PlatformAccount
                {
                    Id = Guid.NewGuid(),
                    PlatformID = platform.Id,
                    AccountName = "Personal",
                    Color = platform.Color,
                    Symbol = platform.Symbol,
                    UsesLegacyStore = true
                });
            }

            EnsurePrimaryAccounts(defaultData);
            HydrateAICredentials(defaultData, string.Empty, string.Empty);
            SaveData(defaultData);
            return defaultData;
        }

        private void EnsureDefaultPlatforms(AppData data)
        {
            if (data.SocialPlatforms == null || data.SocialPlatforms.Count == 0)
            {
                data.SocialPlatforms = SocialPlatform.DefaultPlatforms;
                return;
            }

            // Add any newly introduced platforms from presets
            var existingIds = new HashSet<string>(data.SocialPlatforms.Select(p => p.Id));
            foreach (var preset in SocialPlatform.DefaultPlatforms)
            {
                if (!existingIds.Contains(preset.Id))
                {
                    data.SocialPlatforms.Add(preset);
                }
            }
        }

        private static void EnsurePrimaryAccounts(AppData data)
        {
            data.PlatformAccounts ??= new List<PlatformAccount>();
            foreach (var platform in data.SocialPlatforms)
            {
                if (!data.PlatformAccounts.Any(account => account.PlatformID == platform.Id))
                {
                    data.PlatformAccounts.Add(new PlatformAccount
                    {
                        PlatformID = platform.Id,
                        AccountName = "Personal",
                        Color = platform.Color,
                        Symbol = platform.Symbol,
                        UsesLegacyStore = true
                    });
                }
            }
            foreach (var accounts in data.PlatformAccounts.GroupBy(account => account.PlatformID))
            {
                if (!accounts.Any(account => account.UsesLegacyStore))
                {
                    accounts.First().UsesLegacyStore = true;
                }
            }
        }

        public bool DeleteProfileDirectory(Guid accountId)
        {
            var profilePath = Path.Combine(_appDataDirectory, "Profiles", accountId.ToString());
            try
            {
                if (Directory.Exists(profilePath)) Directory.Delete(profilePath, true);
                return true;
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DataStoreService] Could not delete profile {accountId}: {ex.Message}");
                return false;
            }
        }

        public void Save()
        {
            SaveData(CurrentData);
        }

        private static void HydrateAICredentials(AppData data, string legacyGeminiKey, string legacyOpenAiKey)
        {
            var geminiKey = AICredentialStore.Load("gemini");
            var openAiKey = AICredentialStore.Load("openai");

            if (string.IsNullOrWhiteSpace(geminiKey) && !string.IsNullOrWhiteSpace(legacyGeminiKey))
            {
                AICredentialStore.Save("gemini", legacyGeminiKey);
                geminiKey = legacyGeminiKey;
            }
            if (string.IsNullOrWhiteSpace(openAiKey) && !string.IsNullOrWhiteSpace(legacyOpenAiKey))
            {
                AICredentialStore.Save("openai", legacyOpenAiKey);
                openAiKey = legacyOpenAiKey;
            }

            data.Preferences.GeminiApiKey = geminiKey;
            data.Preferences.OpenAiApiKey = openAiKey;
        }

        private void SaveData(AppData data)
        {
            try
            {
                var options = new JsonSerializerOptions { WriteIndented = true };
                var json = JsonSerializer.Serialize(data, options);
                File.WriteAllText(_dataFilePath, json);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[DataStoreService] Error saving data.json: {ex.Message}");
            }
        }
    }
}
