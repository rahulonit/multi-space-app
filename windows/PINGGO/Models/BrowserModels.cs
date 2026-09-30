using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace PINGGO.Models
{
    public class BrowserBookmark
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; } = Guid.NewGuid();

        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("urlString")]
        public string UrlString { get; set; } = string.Empty;

        [JsonPropertyName("symbol")]
        public string Symbol { get; set; } = "globe";
    }

    public partial class BrowserTabItem : ObservableObject
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        [ObservableProperty]
        private string _title = "New Tab";

        [ObservableProperty]
        private string _urlString = string.Empty;
        public string PageTitle { get; set; } = string.Empty;
        public bool IsLoading { get; set; } = false;
        public double EstimatedProgress { get; set; } = 0.0;
        public bool CanGoBack { get; set; } = false;
        public bool CanGoForward { get; set; } = false;
        public int BlockedAdsCount { get; set; } = 0;
        public bool IsReaderModeActive { get; set; } = false;
        public string? ReaderContent { get; set; }
        [ObservableProperty]
        private string? _faviconUrl;
    }

    public class SavedBrowserTab
    {
        [JsonPropertyName("id")]
        public Guid Id { get; set; }

        [JsonPropertyName("title")]
        public string Title { get; set; } = string.Empty;

        [JsonPropertyName("urlString")]
        public string UrlString { get; set; } = string.Empty;

        [JsonPropertyName("pageTitle")]
        public string PageTitle { get; set; } = string.Empty;

        [JsonPropertyName("isReaderModeActive")]
        public bool IsReaderModeActive { get; set; }

        [JsonPropertyName("blockedAdsCount")]
        public int BlockedAdsCount { get; set; }

        [JsonPropertyName("faviconUrl")]
        public string? FaviconUrl { get; set; }
    }

    public class SavedBrowserSession
    {
        [JsonPropertyName("tabs")]
        public List<SavedBrowserTab> Tabs { get; set; } = new();

        [JsonPropertyName("activeTabID")]
        public Guid ActiveTabID { get; set; }
    }
}
