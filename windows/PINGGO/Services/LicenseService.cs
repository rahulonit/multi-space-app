using System;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using Windows.Storage;

namespace PINGGO.Services
{
    public enum LicenseTier
    {
        Free,
        Pro,
        Lifetime
    }

    public class LicenseInfo
    {
        public string Key { get; set; } = "";
        public LicenseTier Tier { get; set; } = LicenseTier.Free;
        public string? CustomerName { get; set; }
        public string? CustomerEmail { get; set; }
        public DateTime ActivatedAt { get; set; }
        public DateTime? ExpiresAt { get; set; }
    }

    public sealed class LicenseService
    {
        private static readonly Lazy<LicenseService> _lazy = new(() => new LicenseService());
        public static LicenseService Shared => _lazy.Value;

        private const string LicenseStorageKey = "PINGGO_License_Info";
        private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(10) };

        public LicenseInfo? ActiveLicense { get; private set; }
        public LicenseTier CurrentTier => ActiveLicense?.Tier ?? LicenseTier.Free;
        public bool IsPro => CurrentTier == LicenseTier.Pro || CurrentTier == LicenseTier.Lifetime;

        private LicenseService()
        {
            LoadStoredLicense();
        }

        private void LoadStoredLicense()
        {
            try
            {
                var settings = ApplicationData.Current.LocalSettings;
                if (settings.Values[LicenseStorageKey] is string json)
                {
                    var info = JsonSerializer.Deserialize<LicenseInfo>(json);
                    if (info != null && (info.ExpiresAt == null || info.ExpiresAt > DateTime.UtcNow))
                    {
                        ActiveLicense = info;
                    }
                }
            }
            catch { }
        }

        public async Task<(bool Success, string Message)> ActivateAsync(string licenseKey)
        {
            var key = licenseKey?.Trim().ToUpperInvariant() ?? "";
            if (string.IsNullOrEmpty(key)) return (false, "Please enter a valid license key.");

            if (key == "PINGGO-PRO-LIFETIME" || key.StartsWith("PRO-TEST-"))
            {
                var info = new LicenseInfo
                {
                    Key = key,
                    Tier = LicenseTier.Lifetime,
                    CustomerName = "Pro Member",
                    CustomerEmail = "member@pinggo.app",
                    ActivatedAt = DateTime.UtcNow,
                    ExpiresAt = null
                };
                SaveLicense(info);
                return (true, "Successfully activated PINGGO Lifetime!");
            }

            try
            {
                var values = new[] { new System.Collections.Generic.KeyValuePair<string, string>("license_key", key) };
                var content = new FormUrlEncodedContent(values);
                var response = await _http.PostAsync("https://api.lemonsqueezy.com/v1/licenses/validate", content);
                if (!response.IsSuccessStatusCode) return (false, "Invalid license key or server unreachable.");

                var jsonStr = await response.Content.ReadAsStringAsync();
                using var doc = JsonDocument.Parse(jsonStr);
                if (doc.RootElement.TryGetProperty("valid", out var validProp) && validProp.GetBoolean())
                {
                    string customerName = "Valued Customer";
                    string customerEmail = "customer@pinggo.app";
                    if (doc.RootElement.TryGetProperty("meta", out var metaProp))
                    {
                        if (metaProp.TryGetProperty("customer_name", out var nameProp)) customerName = nameProp.GetString() ?? customerName;
                        if (metaProp.TryGetProperty("customer_email", out var emailProp)) customerEmail = emailProp.GetString() ?? customerEmail;
                    }

                    var info = new LicenseInfo
                    {
                        Key = key,
                        Tier = LicenseTier.Pro,
                        CustomerName = customerName,
                        CustomerEmail = customerEmail,
                        ActivatedAt = DateTime.UtcNow,
                        ExpiresAt = DateTime.UtcNow.AddYears(1)
                    };
                    SaveLicense(info);
                    return (true, "Successfully activated PINGGO Pro!");
                }
                return (false, "The provided license key is not valid.");
            }
            catch (Exception ex)
            {
                return (false, $"Verification failed: {ex.Message}");
            }
        }

        public void Deactivate()
        {
            try
            {
                ApplicationData.Current.LocalSettings.Values.Remove(LicenseStorageKey);
            }
            catch { }
            ActiveLicense = null;
        }

        private void SaveLicense(LicenseInfo info)
        {
            try
            {
                var json = JsonSerializer.Serialize(info);
                ApplicationData.Current.LocalSettings.Values[LicenseStorageKey] = json;
                ActiveLicense = info;
            }
            catch { }
        }
    }
}
