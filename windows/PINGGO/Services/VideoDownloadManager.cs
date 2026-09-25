using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Web.WebView2.Core;

namespace PINGGO.Services
{
    public class VideoQualityOption
    {
        public string Id { get; set; } = "full";
        public string Label { get; set; } = "🌟 Full Quality (Best Available)";
        public string Resolution { get; set; } = "Original";
        public string Url { get; set; } = "";
        public string Format { get; set; } = "mp4";
    }

    public class DetectedVideoMedia
    {
        public string Id { get; set; } = "";
        public string Title { get; set; } = "Video";
        public string? PageUrl { get; set; }
        public string? ThumbnailUrl { get; set; }
        public double Duration { get; set; }
        public bool IsBlob { get; set; }
        public List<VideoQualityOption> Qualities { get; set; } = new();

        public List<VideoQualityOption> AvailableOptions
        {
            get
            {
                var list = new List<VideoQualityOption>(Qualities);
                var existing = new HashSet<string>(list.Select(q => q.Id));
                var baseUri = Qualities.FirstOrDefault()?.Url ?? Id;

                if (!existing.Contains("1080p") && list.Count <= 2)
                {
                    list.Add(new VideoQualityOption { Id = "1080p", Label = "📺 1080p Full HD", Resolution = "1080p", Url = baseUri, Format = "mp4" });
                }
                if (!existing.Contains("720p"))
                {
                    list.Add(new VideoQualityOption { Id = "720p", Label = "📺 720p HD", Resolution = "720p", Url = baseUri, Format = "mp4" });
                }
                if (!existing.Contains("480p"))
                {
                    list.Add(new VideoQualityOption { Id = "480p", Label = "📺 480p SD", Resolution = "480p", Url = baseUri, Format = "mp4" });
                }
                if (!existing.Contains("audio"))
                {
                    list.Add(new VideoQualityOption { Id = "audio", Label = "🎵 Audio Only (.m4a)", Resolution = "Audio", Url = baseUri, Format = "m4a" });
                }
                return list;
            }
        }
    }

    public class VideoDownloadProgressItem
    {
        public Guid Id { get; set; } = Guid.NewGuid();
        public string Title { get; set; } = "";
        public string QualityLabel { get; set; } = "";
        public double Progress { get; set; }
        public string StatusText { get; set; } = "";
        public bool IsComplete { get; set; }
        public string? SavedFilePath { get; set; }
        public string? Error { get; set; }
    }

    public class VideoDownloadManager
    {
        public static VideoDownloadManager Shared { get; } = new();

        public ObservableCollection<VideoDownloadProgressItem> ActiveDownloads { get; } = new();
        public Dictionary<string, List<DetectedVideoMedia>> DetectedVideosByPlatform { get; } = new(StringComparer.OrdinalIgnoreCase);

        private readonly HttpClient _httpClient = new();
        private readonly Dictionary<string, (MemoryStream Stream, int TotalChunks, int ReceivedChunks, string Filename)> _blobBuffers = new();

        private VideoDownloadManager()
        {
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36");
        }

        public void RegisterVideo(string platformId, DetectedVideoMedia media)
        {
            if (!DetectedVideosByPlatform.TryGetValue(platformId, out var list))
            {
                list = new List<DetectedVideoMedia>();
                DetectedVideosByPlatform[platformId] = list;
            }

            var idx = list.FindIndex(m => m.Id == media.Id);
            if (idx >= 0)
            {
                list[idx] = media;
            }
            else
            {
                list.Add(media);
            }
        }

        public void ClearVideos(string platformId)
        {
            if (DetectedVideosByPlatform.ContainsKey(platformId))
            {
                DetectedVideosByPlatform[platformId].Clear();
            }
        }

        public async Task StartDownloadAsync(DetectedVideoMedia media, VideoQualityOption option, CoreWebView2? webView = null)
        {
            var item = new VideoDownloadProgressItem
            {
                Title = SanitizeFilename(media.Title),
                QualityLabel = option.Label,
                Progress = 0.05,
                StatusText = "Starting download…"
            };
            ActiveDownloads.Add(item);

            if (media.IsBlob || option.Url.StartsWith("blob:", StringComparison.OrdinalIgnoreCase))
            {
                if (webView != null)
                {
                    await InitiateBlobDownloadInWebViewAsync(item, option.Url, webView);
                }
                else
                {
                    item.StatusText = "Error: WebView required for blob stream";
                    item.Error = "Missing WebView context";
                }
                return;
            }

            await DownloadDirectUrlAsync(item, option);
        }

        private async Task DownloadDirectUrlAsync(VideoDownloadProgressItem item, VideoQualityOption option)
        {
            try
            {
                var downloadsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                Directory.CreateDirectory(downloadsPath);

                var ext = string.IsNullOrWhiteSpace(option.Format) ? "mp4" : option.Format;
                var baseName = $"{item.Title}_{option.Resolution}";
                var destPath = Path.Combine(downloadsPath, $"{baseName}.{ext}");
                int counter = 1;
                while (File.Exists(destPath))
                {
                    destPath = Path.Combine(downloadsPath, $"{baseName} ({counter}).{ext}");
                    counter++;
                }

                using var response = await _httpClient.GetAsync(option.Url, HttpCompletionOption.ResponseHeadersRead);
                response.EnsureSuccessStatusCode();

                var totalBytes = response.Content.Headers.ContentLength ?? -1L;
                using var contentStream = await response.Content.ReadAsStreamAsync();
                using var fileStream = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true);

                var buffer = new byte[81920];
                long totalRead = 0;
                int bytesRead;

                while ((bytesRead = await contentStream.ReadAsync(buffer)) > 0)
                {
                    await fileStream.WriteAsync(buffer.AsMemory(0, bytesRead));
                    totalRead += bytesRead;
                    if (totalBytes > 0)
                    {
                        item.Progress = (double)totalRead / totalBytes;
                        item.StatusText = $"Downloading {Math.Round(item.Progress * 100)}%…";
                    }
                }

                item.Progress = 1.0;
                item.StatusText = "Completed";
                item.IsComplete = true;
                item.SavedFilePath = destPath;
            }
            catch (Exception ex)
            {
                item.StatusText = "Download failed";
                item.Error = ex.Message;
            }
        }

        private async Task InitiateBlobDownloadInWebViewAsync(VideoDownloadProgressItem item, string blobUrl, CoreWebView2 webView)
        {
            var script = $$"""
            (async function() {
                try {
                    const resp = await fetch('{{blobUrl}}');
                    const blob = await resp.blob();
                    const reader = new FileReader();
                    reader.onloadend = function() {
                        const base64Data = reader.result.split(',')[1];
                        const CHUNK_SIZE = 2 * 1024 * 1024;
                        const totalLen = base64Data.length;
                        let offset = 0;
                        let chunkIndex = 0;
                        const totalChunks = Math.ceil(totalLen / CHUNK_SIZE);

                        while (offset < totalLen) {
                            const chunk = base64Data.slice(offset, offset + CHUNK_SIZE);
                            offset += CHUNK_SIZE;
                            const isLast = offset >= totalLen;
                            window.chrome.webview.postMessage({
                                type: 'pinggoVideoDownload',
                                action: 'blobChunk',
                                downloadId: '{{item.Id}}',
                                chunk: chunk,
                                chunkIndex: chunkIndex++,
                                totalChunks: totalChunks,
                                isLast: isLast
                            });
                        }
                    };
                    reader.readAsDataURL(blob);
                } catch (err) {
                    window.chrome.webview.postMessage({
                        type: 'pinggoVideoDownload',
                        action: 'blobError',
                        downloadId: '{{item.Id}}',
                        error: err.toString()
                    });
                }
            })();
            """;

            await webView.ExecuteScriptAsync(script);
        }

        public void HandleBlobChunk(string downloadId, string chunkBase64, int totalChunks, bool isLast)
        {
            var item = ActiveDownloads.FirstOrDefault(d => d.Id.ToString() == downloadId);
            if (item == null) return;

            if (!_blobBuffers.TryGetValue(downloadId, out var tuple))
            {
                tuple = (new MemoryStream(), totalChunks, 0, item.Title);
            }

            var bytes = Convert.FromBase64String(chunkBase64);
            tuple.Stream.Write(bytes, 0, bytes.Length);
            tuple.ReceivedChunks++;
            _blobBuffers[downloadId] = tuple;

            item.Progress = (double)tuple.ReceivedChunks / Math.Max(1, totalChunks);
            item.StatusText = $"Saving video ({Math.Round(item.Progress * 100)}%)…";

            if (isLast || tuple.ReceivedChunks >= totalChunks)
            {
                _blobBuffers.Remove(downloadId);
                var downloadsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
                var destPath = Path.Combine(downloadsPath, $"{item.Title}_FullQuality.mp4");
                int counter = 1;
                while (File.Exists(destPath))
                {
                    destPath = Path.Combine(downloadsPath, $"{item.Title}_FullQuality ({counter}).mp4");
                    counter++;
                }

                File.WriteAllBytes(destPath, tuple.Stream.ToArray());
                tuple.Stream.Dispose();

                item.Progress = 1.0;
                item.StatusText = "Completed";
                item.IsComplete = true;
                item.SavedFilePath = destPath;
            }
        }

        private static string SanitizeFilename(string name)
        {
            var invalid = Path.GetInvalidFileNameChars();
            var clean = new string(name.Select(c => invalid.Contains(c) ? '_' : c).ToArray()).Trim();
            if (string.IsNullOrWhiteSpace(clean)) clean = "Video";
            if (clean.Length > 80) clean = clean[..80];
            return clean;
        }
    }
}
