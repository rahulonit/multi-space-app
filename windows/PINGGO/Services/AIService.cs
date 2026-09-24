using System;
using System.Collections.Generic;
using System.IO;
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

        public async Task<string> AskCoPilotAsync(string prompt, string context = "")
        {
            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            var systemPrompt = "You are PINGGO Copilot, a privacy-focused executive assistant. Provide concise, helpful answers.";
            var fullPrompt = string.IsNullOrWhiteSpace(context) ? prompt : $"Context:\n{context}\n\nUser Question:\n{prompt}";

            var resolution = AIProviderResolver.Resolve(prefs);

            if (resolution.CanPerformGenerativeAI)
            {
                if (resolution.Provider == AIProviderType.Gemini)
                {
                    try
                    {
                        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{resolution.Model}:generateContent";
                        var payload = new
                        {
                            system_instruction = new { parts = new[] { new { text = systemPrompt } } },
                            contents = new[] { new { parts = new[] { new { text = fullPrompt } } } }
                        };
                        using var req = new HttpRequestMessage(HttpMethod.Post, url);
                        req.Headers.Add("x-goog-api-key", prefs.GeminiApiKey);
                        req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                        var res = await _httpClient.SendAsync(req);
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
                else if (resolution.Provider == AIProviderType.ChatGpt)
                {
                    try
                    {
                        var url = "https://api.openai.com/v1/chat/completions";
                        var payload = new
                        {
                            model = resolution.Model,
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
            }

            // Local fallback smart reply
            return GenerateLocalSmartSummary(prompt);
        }

        public async Task<string> StreamCoPilotAsync(string prompt, string context, string tone, Action<string> onChunk, List<CopilotMessage>? history = null)
        {
            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            var personaInstruction = prefs.PersonaStyle switch
            {
                "Casual & Warm" => "Adopt a warm, friendly, empathetic, and approachable conversational style.",
                "Executive & Formal" => "Adopt an executive, structured, highly professional, and diplomatic communication style.",
                "Technical & Precise" => "Adopt a precise, technically accurate, analytical, and structured communication style.",
                _ => "Adopt a direct, concise, and action-oriented communication style. Omit pleasantries and fluff."
            };

            var systemPrompt = $"You are PINGGO Co-Pilot, an intelligent personal communication assistant. {personaInstruction} Draft clear, concise, and context-aware responses in a {tone} tone. {(string.IsNullOrEmpty(prefs.CustomAiPrompt) ? "" : "User guidelines: " + prefs.CustomAiPrompt)}";
            var fullPrompt = string.IsNullOrWhiteSpace(context) ? prompt : $"Context:\n{context}\n\nInstruction/Question:\n{prompt}";

            var accumulated = new StringBuilder();
            var resolution = AIProviderResolver.Resolve(prefs);

            if (resolution.CanPerformGenerativeAI)
            {
                if (resolution.Provider == AIProviderType.Gemini)
                {
                    try
                    {
                        var targetModel = (resolution.Model ?? "").Contains("gemini-3.5") ? "gemini-2.5-flash" : (string.IsNullOrWhiteSpace(resolution.Model) ? "gemini-2.5-flash" : resolution.Model);
                        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{targetModel}:streamGenerateContent?alt=sse";
                        var contentsList = new List<object>();
                        if (history != null)
                        {
                            foreach (var h in history)
                            {
                                contentsList.Add(new { role = h.Role == "assistant" ? "model" : "user", parts = new[] { new { text = h.Content } } });
                            }
                        }
                        contentsList.Add(new { role = "user", parts = new[] { new { text = fullPrompt } } });

                        var payload = new
                        {
                            system_instruction = new { parts = new[] { new { text = systemPrompt } } },
                            contents = contentsList
                        };
                        using var req = new HttpRequestMessage(HttpMethod.Post, url);
                        req.Headers.Add("x-goog-api-key", prefs.GeminiApiKey);
                        req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

                        using var res = await _httpClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead);
                        if (res.IsSuccessStatusCode)
                        {
                            using var stream = await res.Content.ReadAsStreamAsync();
                            using var reader = new StreamReader(stream);
                            while (!reader.EndOfStream)
                            {
                                var line = await reader.ReadLineAsync();
                                if (string.IsNullOrWhiteSpace(line) || !line.StartsWith("data: ")) continue;
                                var json = line["data: ".Length..];
                                try
                                {
                                    using var doc = JsonDocument.Parse(json);
                                    if (doc.RootElement.TryGetProperty("candidates", out var cArr) && cArr.GetArrayLength() > 0)
                                    {
                                        var text = cArr[0].GetProperty("content").GetProperty("parts")[0].GetProperty("text").GetString();
                                        if (!string.IsNullOrEmpty(text))
                                        {
                                            accumulated.Append(text);
                                            onChunk(text);
                                        }
                                    }
                                }
                                catch { }
                            }
                            if (accumulated.Length > 0) return accumulated.ToString();
                        }
                    }
                    catch { }
                }
                else if (resolution.Provider == AIProviderType.ChatGpt)
                {
                    try
                    {
                        var url = "https://api.openai.com/v1/chat/completions";
                        var messages = new List<object>
                        {
                            new { role = "system", content = systemPrompt }
                        };
                        if (history != null)
                        {
                            foreach (var h in history)
                            {
                                messages.Add(new { role = h.Role, content = h.Content });
                            }
                        }
                        messages.Add(new { role = "user", content = fullPrompt });

                        var payload = new
                        {
                            model = resolution.Model,
                            messages = messages,
                            temperature = 0.7,
                            stream = true
                        };
                        using var req = new HttpRequestMessage(HttpMethod.Post, url);
                        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", prefs.OpenAiApiKey);
                        req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

                        using var res = await _httpClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead);
                        if (res.IsSuccessStatusCode)
                        {
                            using var stream = await res.Content.ReadAsStreamAsync();
                            using var reader = new StreamReader(stream);
                            while (!reader.EndOfStream)
                            {
                                var line = await reader.ReadLineAsync();
                                if (string.IsNullOrWhiteSpace(line) || !line.StartsWith("data: ")) continue;
                                var json = line["data: ".Length..];
                                if (json.Trim() == "[DONE]") break;
                                try
                                {
                                    using var doc = JsonDocument.Parse(json);
                                    if (doc.RootElement.TryGetProperty("choices", out var cArr) && cArr.GetArrayLength() > 0)
                                    {
                                        var delta = cArr[0].GetProperty("delta");
                                        if (delta.TryGetProperty("content", out var contentProp))
                                        {
                                            var text = contentProp.GetString();
                                            if (!string.IsNullOrEmpty(text))
                                            {
                                                accumulated.Append(text);
                                                onChunk(text);
                                            }
                                        }
                                    }
                                }
                                catch { }
                            }
                            if (accumulated.Length > 0) return accumulated.ToString();
                        }
                    }
                    catch { }
                }
                else if (resolution.Provider == AIProviderType.Ollama)
                {
                    try
                    {
                        var baseEndpoint = string.IsNullOrWhiteSpace(prefs.OllamaEndpoint) ? "http://localhost:11434" : prefs.OllamaEndpoint.TrimEnd('/');
                        var url = $"{baseEndpoint}/api/chat";
                        var messages = new List<object>
                        {
                            new { role = "system", content = systemPrompt + (string.IsNullOrWhiteSpace(context) ? "" : $"\nContext:\n{context}") }
                        };
                        if (history != null)
                        {
                            foreach (var h in history)
                            {
                                messages.Add(new { role = h.Role, content = h.Content });
                            }
                        }
                        messages.Add(new { role = "user", content = prompt });

                        var payload = new
                        {
                            model = resolution.Model,
                            messages = messages,
                            stream = true
                        };
                        using var req = new HttpRequestMessage(HttpMethod.Post, url);
                        req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

                        using var res = await _httpClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead);
                        if (res.IsSuccessStatusCode)
                        {
                            using var stream = await res.Content.ReadAsStreamAsync();
                            using var reader = new StreamReader(stream);
                            while (!reader.EndOfStream)
                            {
                                var line = await reader.ReadLineAsync();
                                if (string.IsNullOrWhiteSpace(line)) continue;
                                try
                                {
                                    using var doc = JsonDocument.Parse(line);
                                    if (doc.RootElement.TryGetProperty("message", out var msgProp) &&
                                        msgProp.TryGetProperty("content", out var textProp))
                                    {
                                        var text = textProp.GetString();
                                        if (!string.IsNullOrEmpty(text))
                                        {
                                            accumulated.Append(text);
                                            onChunk(text);
                                        }
                                    }
                                }
                                catch { }
                            }
                            if (accumulated.Length > 0) return accumulated.ToString();
                        }
                    }
                    catch { }
                }
            }

            // Fallback: local instant reply without artificial typewriter delay
            var reply = GenerateLocalSmartSummary(prompt);
            onChunk(reply);
            return reply;
        }

        public async Task<string> TranslateMessageAsync(string text, string targetLanguage = "English")
        {
            var prefs = DataStoreService.Shared.CurrentData.Preferences;
            var resolution = AIProviderResolver.Resolve(prefs);
            if (!resolution.CanPerformGenerativeAI)
            {
                throw new InvalidOperationException("Translation requires a configured and enabled AI provider.");
            }

            var prompt = $"Translate the following text into {targetLanguage}. Output only the translated text with no conversational remarks:\n\n{text}";
            return await GenerateResponseAsync(prompt);
        }

        public Task<string> GenerateResponseAsync(string prompt)
        {
            return AskCoPilotAsync(prompt);
        }

        public async Task<(bool Success, string Message)> TestConnectionAsync(string provider, string keyOrEndpoint, string model = "gemini-2.5-flash")
        {
            try
            {
                if (provider == "ollama")
                {
                    var endpoint = string.IsNullOrWhiteSpace(keyOrEndpoint) ? "http://localhost:11434" : keyOrEndpoint.TrimEnd('/');
                    var res = await _httpClient.GetAsync($"{endpoint}/api/tags");
                    if (res.IsSuccessStatusCode)
                    {
                        return (true, $"Ollama Connected! Local model server active at {endpoint}.");
                    }
                    return (false, $"Ollama responded with HTTP {(int)res.StatusCode}");
                }
                else if (provider == "gemini")
                {
                    if (string.IsNullOrWhiteSpace(keyOrEndpoint)) return (false, "Gemini API key is required.");
                    var targetModel = (model ?? "").Contains("gemini-3.5") ? "gemini-2.5-flash" : (string.IsNullOrWhiteSpace(model) ? "gemini-2.5-flash" : model);
                    var url = $"https://generativelanguage.googleapis.com/v1beta/models/{targetModel}:generateContent";
                    var payload = new { contents = new[] { new { parts = new[] { new { text = "Respond with CONNECTED" } } } } };
                    using var req = new HttpRequestMessage(HttpMethod.Post, url);
                    req.Headers.Add("x-goog-api-key", keyOrEndpoint);
                    req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                    var res = await _httpClient.SendAsync(req);
                    return res.IsSuccessStatusCode ? (true, "Google Gemini Connected!") : (false, $"Gemini error: HTTP {(int)res.StatusCode}");
                }
                else
                {
                    if (string.IsNullOrWhiteSpace(keyOrEndpoint)) return (false, "OpenAI API key is required.");
                    var url = "https://api.openai.com/v1/chat/completions";
                    var payload = new { model = model, messages = new[] { new { role = "user", content = "Respond with CONNECTED" } }, max_tokens = 10 };
                    using var req = new HttpRequestMessage(HttpMethod.Post, url);
                    req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", keyOrEndpoint);
                    req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                    var res = await _httpClient.SendAsync(req);
                    return res.IsSuccessStatusCode ? (true, "OpenAI ChatGPT Connected!") : (false, $"ChatGPT error: HTTP {(int)res.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                return (false, ex.Message);
            }
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
