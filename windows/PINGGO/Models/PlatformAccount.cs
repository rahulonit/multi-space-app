using System;
using System.Text.Json.Serialization;

namespace PINGGO.Models
{
    public class PlatformAccount
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [JsonPropertyName("platformID")]
        public string PlatformID { get; set; } = string.Empty;

        [JsonPropertyName("accountName")]
        public string AccountName { get; set; } = "Primary";

        [JsonPropertyName("color")]
        public string Color { get; set; } = "blue";

        [JsonPropertyName("symbol")]
        public string Symbol { get; set; } = "person.fill";

        [JsonPropertyName("usesLegacyStore")]
        public bool UsesLegacyStore { get; set; } = false;

        [JsonPropertyName("customURL")]
        public string? CustomURL { get; set; }

        [JsonPropertyName("launchMode")]
        public string LaunchMode { get; set; } = "embedded";

        [JsonIgnore]
        public string UserDataFolderName => $"Profile_{Id}";
    }
}
