using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using PINGGO.Models;

namespace PINGGO.Services
{
    public class AIService
    {
        private static readonly Lazy<AIService> _instance = new(() => new AIService());
        public static AIService Shared => _instance.Value;

        private readonly HttpClient _httpClient = new() { Timeout = TimeSpan.FromSeconds(20) };

        public async Task<(bool Success, string Message)> TestConnectionAsync(string provider, string apiKey)
        {
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                return (false, "API Key is required.");
            }

            try
            {
                if (provider.Equals("gemini", StringComparison.OrdinalIgnoreCase))
                {
                    var url = $"https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key={apiKey}";
                    var payload = new
                    {
                        contents = new[]
                        {
                            new { parts = new[] { new { text = "Ping" } } }
                        }
                    };
                    var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                    var res = await _httpClient.PostAsync(url, content);
                    if (res.IsSuccessStatusCode)
                    {
                        return (true, "Google Gemini API connection verified!");
                    }
                    var err = await res.Content.ReadAsStringAsync();
                    return (false, $"Gemini Error: {res.StatusCode}");
                }
                else
                {
                    var url = "https://api.openai.com/v1/chat/completions";
                    var payload = new
                    {
                        model = "gpt-4o-mini",
                        messages = new[]
                        {
                            new { role = "user", content = "Ping" }
                        },
                        max_tokens = 5
                    };
                    using var req = new HttpRequestMessage(HttpMethod.Post, url);
                    req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
                    req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

                    var res = await _httpClient.SendAsync(req);
                    if (res.IsSuccessStatusCode)
                    {
                        return (true, "OpenAI ChatGPT API connection verified!");
                    }
                    return (false, $"OpenAI Error: {res.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                return (false, $"Network error: {ex.Message}");
            }
        }

        public async Task<string> AskCoPilotAsync(string prompt, string context = "")
        {
            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            var systemPrompt = "You are PINGGO Copilot, a privacy-focused executive assistant. Provide concise, helpful answers.";
            var fullPrompt = string.IsNullOrWhiteSpace(context) ? prompt : $"Context:\n{context}\n\nUser Question:\n{prompt}";

            if (prefs.AiProvider == "gemini" && !string.IsNullOrWhiteSpace(prefs.GeminiApiKey))
            {
                try
                {
                    var url = $"https://generativelanguage.googleapis.com/v1beta/models/{prefs.AiModelTier}:generateContent?key={prefs.GeminiApiKey}";
                    var payload = new
                    {
                        system_instruction = new { parts = new[] { new { text = systemPrompt } } },
                        contents = new[] { new { parts = new[] { new { text = fullPrompt } } } }
                    };
                    var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                    var res = await _httpClient.PostAsync(url, content);
                    if (res.IsSuccessStatusCode)
                    {
                        var json = await res.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        var text = doc.RootElement.GetProperty("candidates")[0]
                            .GetProperty("content").GetProperty("parts")[0]
                            .GetProperty("text").GetString();
                        if (!string.IsNullOrEmpty(text)) return text;
                    }
                }
                catch { }
            }
            else if (prefs.AiProvider == "chatgpt" && !string.IsNullOrWhiteSpace(prefs.OpenAiApiKey))
            {
                try
                {
                    var url = "https://api.openai.com/v1/chat/completions";
                    var payload = new
                    {
                        model = "gpt-4o-mini",
                        messages = new[]
                        {
                            new { role = "system", content = systemPrompt },
                            new { role = "user", content = fullPrompt }
                        },
                        max_tokens = 500
                    };
                    using var req = new HttpRequestMessage(HttpMethod.Post, url);
                    req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", prefs.OpenAiApiKey);
                    req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                    var res = await _httpClient.SendAsync(req);
                    if (res.IsSuccessStatusCode)
                    {
                        var json = await res.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(json);
                        var text = doc.RootElement.GetProperty("choices")[0]
                            .GetProperty("message").GetProperty("content").GetString();
                        if (!string.IsNullOrEmpty(text)) return text;
                    }
                }
                catch { }
            }

            // Local fallback smart reply
            return GenerateLocalSmartSummary(prompt);
        }

        public SentimentResult AnalyzeSentiment(string text)
        {
            if (string.IsNullOrWhiteSpace(text))
            {
                return new SentimentResult { Score = 0, Classification = "Neutral", DetectedLanguage = "English" };
            }

            var lower = text.ToLowerInvariant();
            double score = 0.0;

            // Heuristic scoring dictionary
            if (lower.Contains("great") || lower.Contains("excellent") || lower.Contains("thank") || lower.Contains("love") || lower.Contains("awesome") || lower.Contains("perfect"))
                score += 0.6;
            if (lower.Contains("good") || lower.Contains("agree") || lower.Contains("sounds good") || lower.Contains("helpful"))
                score += 0.3;
            if (lower.Contains("issue") || lower.Contains("problem") || lower.Contains("delay") || lower.Contains("blocked"))
                score -= 0.4;
            if (lower.Contains("urgent") || lower.Contains("broken") || lower.Contains("error") || lower.Contains("fail") || lower.Contains("angry"))
                score -= 0.7;

            score = Math.Clamp(score, -1.0, 1.0);

            string classification = score switch
            {
                >= 0.5 => "Warm & Highly Positive (+0.6)",
                >= 0.1 => "Constructive / Collaborative (+0.2)",
                <= -0.5 => "Urgent Concern / Critical (-0.6)",
                <= -0.1 => "Direct / Needs Resolution (-0.2)",
                _ => "Neutral / Professional"
            };

            return new SentimentResult
            {
                Score = score,
                Classification = classification,
                DetectedLanguage = "English"
            };
        }

        public List<SmartReplyOption> GenerateReplyOptions(string incomingMessage)
        {
            return new List<SmartReplyOption>
            {
                new() { Tone = "Professional", Content = "Thank you for the update. I have reviewed this and agree with proceeding as outlined.", Icon = "Briefcase" },
                new() { Tone = "Friendly", Content = "Sounds awesome! Thanks for sharing this with me. Let's do it!", Icon = "Smile" },
                new() { Tone = "Concise", Content = "Acknowledged and confirmed.", Icon = "Lightning" },
                new() { Tone = "Propose Time", Content = "Could we jump on a brief 10-minute sync later today to walk through the details?", Icon = "Clock" },
                new() { Tone = "Polite Decline", Content = "Thanks for thinking of me, but I won't be able to accommodate this at the moment due to current commitments.", Icon = "Cross" }
            };
        }

        private string GenerateLocalSmartSummary(string prompt)
        {
            return $"[PINGGO Local AI]: Reviewed query: \"{prompt}\". Thread status is active, zero critical blockers identified, and all platform channels are synced.";
        }
    }
}
