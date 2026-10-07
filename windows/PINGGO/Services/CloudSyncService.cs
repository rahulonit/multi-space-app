using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace PINGGO.Services
{
    public class CloudSyncService
    {
        public static CloudSyncService Shared { get; } = new();

        private readonly HttpClient _httpClient = new();
        public bool IsSyncing { get; private set; }
        public DateTime? LastSyncedAt { get; private set; }
        public string SyncStatusMessage { get; private set; } = "Not Connected";
        public string? SyncError { get; private set; }
        public bool IsCloudConnected { get; private set; }
        public string CurrentUserEmail { get; private set; } = "";

        private CloudSyncService()
        {
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("PINGGO-Windows/1.0");
        }

        public async Task<bool> LoginOrRegisterAsync(string email, string password, string serverUrl)
        {
            try
            {
                IsSyncing = true;
                SyncError = null;
                SyncStatusMessage = "Authenticating…";

                var baseUrl = serverUrl.Trim().TrimEnd('/');
                var url = $"{baseUrl}/api/v1/auth/login";

                var payload = new
                {
                    email = email.Trim().ToLowerInvariant(),
                    password = password,
                    deviceId = $"win-{Guid.NewGuid().ToString()[..8]}",
                    platform = "Windows"
                };

                var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                var response = await _httpClient.PostAsync(url, content);

                if (response.IsSuccessStatusCode)
                {
                    var json = await response.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    var token = doc.RootElement.GetProperty("token").GetString() ?? "";

                    IsCloudConnected = true;
                    CurrentUserEmail = email;
                    SyncStatusMessage = $"Connected as {email}";
                    IsSyncing = false;
                    return true;
                }
                else
                {
                    // Try registration
                    var regUrl = $"{baseUrl}/api/v1/auth/register";
                    var regResponse = await _httpClient.PostAsync(regUrl, content);
                    if (regResponse.IsSuccessStatusCode)
                    {
                        IsCloudConnected = true;
                        CurrentUserEmail = email;
                        SyncStatusMessage = $"Connected as {email}";
                        IsSyncing = false;
                        return true;
                    }

                    SyncError = "Authentication failed";
                    SyncStatusMessage = "Login failed";
                    IsSyncing = false;
                    return false;
                }
            }
            catch (Exception ex)
            {
                SyncError = ex.Message;
                SyncStatusMessage = "Connection failed";
                IsSyncing = false;
                return false;
            }
        }

        public async Task SyncNowAsync(string token, string serverUrl, object spacesPayload)
        {
            if (IsSyncing || string.IsNullOrEmpty(token)) return;

            try
            {
                IsSyncing = true;
                SyncStatusMessage = "Syncing with MongoDB…";

                var baseUrl = serverUrl.Trim().TrimEnd('/');
                var url = $"{baseUrl}/api/v1/sync/push";

                var request = new HttpRequestMessage(HttpMethod.Post, url);
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                var body = new
                {
                    deviceId = $"win-{Guid.NewGuid().ToString()[..8]}",
                    platform = "Windows",
                    timestamp = DateTime.UtcNow,
                    spaces = spacesPayload
                };
                request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");

                var response = await _httpClient.SendAsync(request);
                if (response.IsSuccessStatusCode)
                {
                    LastSyncedAt = DateTime.Now;
                    SyncStatusMessage = $"Synced at {DateTime.Now:t}";
                    SyncError = null;
                }
                else
                {
                    SyncError = $"Server error {response.StatusCode}";
                    SyncStatusMessage = "Sync failed";
                }
            }
            catch (Exception ex)
            {
                SyncError = ex.Message;
                SyncStatusMessage = "Sync failed";
            }
            finally
            {
                IsSyncing = false;
            }
        }
    }
}
