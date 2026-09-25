import SwiftUI
import WebKit
@preconcurrency import AVFoundation
import AppKit
import UniformTypeIdentifiers

// MARK: - Video Quality Option
public struct VideoQualityOption: Identifiable, Equatable, Hashable, Sendable {
    public let id: String // "full", "1080p", "720p", "480p", "360p", "audio"
    public let label: String // "🌟 Full Quality (Best Available)", "📺 1080p Full HD", etc.
    public let resolution: String // "1080p", "720p", "480p", "360p", "Audio"
    public let url: String // Direct URL or source URL or blob URL
    public let format: String // "mp4", "webm", "m4a"
    public let isTranscode: Bool // True if derived via AVAssetExportSession
    public let exportPreset: String? // Preset name if transcoding

    public init(
        id: String,
        label: String,
        resolution: String,
        url: String,
        format: String = "mp4",
        isTranscode: Bool = false,
        exportPreset: String? = nil
    ) {
        self.id = id
        self.label = label
        self.resolution = resolution
        self.url = url
        self.format = format
        self.isTranscode = isTranscode
        self.exportPreset = exportPreset
    }
}

// MARK: - Detected Video Media Model
public struct DetectedVideoMedia: Identifiable, Equatable, Sendable {
    public let id: String // Video source URL or unique hash
    public var title: String
    public var pageURL: URL?
    public var thumbnailURL: URL?
    public var duration: Double // In seconds
    public var qualities: [VideoQualityOption]
    public var isBlob: Bool
    public var detectedAt: Date = Date()

    public var bestQuality: VideoQualityOption? {
        qualities.first(where: { $0.id == "full" }) ?? qualities.first
    }

    /// Generates full suite of selectable quality options including original stream and standard AVFoundation presets
    public var availableOptions: [VideoQualityOption] {
        var options: [VideoQualityOption] = []

        // 1. Direct qualities detected from page
        for q in qualities {
            options.append(q)
        }

        // 2. If qualities only contains "full" (or single stream like Instagram / WhatsApp / TikTok),
        // complement with standard downscaled resolutions & Audio-Only
        let existingIDs = Set(options.map { $0.id })
        let baseDirectURL = qualities.first?.url ?? id

        if !existingIDs.contains("1080p") && qualities.count <= 2 {
            options.append(VideoQualityOption(
                id: "1080p",
                label: "📺 1080p Full HD",
                resolution: "1080p",
                url: baseDirectURL,
                format: "mp4",
                isTranscode: true,
                exportPreset: AVAssetExportPreset1920x1080
            ))
        }

        if !existingIDs.contains("720p") {
            options.append(VideoQualityOption(
                id: "720p",
                label: "📺 720p HD",
                resolution: "720p",
                url: baseDirectURL,
                format: "mp4",
                isTranscode: true,
                exportPreset: AVAssetExportPreset1280x720
            ))
        }

        if !existingIDs.contains("480p") {
            options.append(VideoQualityOption(
                id: "480p",
                label: "📺 480p SD",
                resolution: "480p",
                url: baseDirectURL,
                format: "mp4",
                isTranscode: true,
                exportPreset: AVAssetExportPreset640x480
            ))
        }

        if !existingIDs.contains("audio") {
            options.append(VideoQualityOption(
                id: "audio",
                label: "🎵 Audio Only (.m4a)",
                resolution: "Audio",
                url: baseDirectURL,
                format: "m4a",
                isTranscode: true,
                exportPreset: AVAssetExportPresetAppleM4A
            ))
        }

        return options
    }
}

// MARK: - Download Item Tracking
public struct VideoDownloadItem: Identifiable, Equatable, Sendable {
    public let id: UUID = UUID()
    public let videoId: String
    public let title: String
    public let qualityLabel: String
    public var progress: Double // 0.0 to 1.0
    public var statusText: String
    public var isComplete: Bool = false
    public var savedFileURL: URL? = nil
    public var error: String? = nil
}

// MARK: - Video Download Manager (Singleton)
@MainActor
public final class VideoDownloadManager: NSObject, ObservableObject {
    public static let shared = VideoDownloadManager()

    @Published public var activeDownloads: [VideoDownloadItem] = []
    @Published public var detectedVideosByTab: [UUID: [DetectedVideoMedia]] = [:]
    @Published public var detectedVideosByPlatform: [String: [DetectedVideoMedia]] = [:]
    @Published public var notificationMessage: String? = nil

    private var activeSessions: [UUID: URLSessionDownloadTask] = [:]
    private var blobBuffers: [String: (data: Data, totalChunks: Int, receivedChunks: Int, filename: String, quality: VideoQualityOption)] = [:]

    private override init() {
        super.init()
    }

    // MARK: - Detection Registration
    public func registerDetectedVideo(_ media: DetectedVideoMedia, forTabID tabID: UUID) {
        var list = detectedVideosByTab[tabID] ?? []
        if let idx = list.firstIndex(where: { $0.id == media.id }) {
            list[idx] = media
        } else {
            list.append(media)
        }
        // Keep most recent 20
        if list.count > 20 { list.removeFirst(list.count - 20) }
        detectedVideosByTab[tabID] = list
    }

    public func clearDetectedVideos(forTabID tabID: UUID) {
        detectedVideosByTab.removeValue(forKey: tabID)
    }

    public func registerDetectedVideo(_ media: DetectedVideoMedia, forPlatformID platformID: String) {
        var list = detectedVideosByPlatform[platformID] ?? []
        if let idx = list.firstIndex(where: { $0.id == media.id }) {
            list[idx] = media
        } else {
            list.append(media)
        }
        if list.count > 20 { list.removeFirst(list.count - 20) }
        detectedVideosByPlatform[platformID] = list
    }

    public func clearDetectedVideos(forPlatformID platformID: String) {
        detectedVideosByPlatform.removeValue(forKey: platformID)
    }

    // MARK: - Sanitizing File Names
    private func sanitizeFilename(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        var clean = name.components(separatedBy: invalidCharacters).joined(separator: "_")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { clean = "Video" }
        if clean.count > 80 { clean = String(clean.prefix(80)) }
        return clean
    }

    // MARK: - Destination Path Creation
    private func createUniqueDestination(baseName: String, ext: String) -> URL {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        
        let fileManager = FileManager.default
        var dest = downloadsDir.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while fileManager.fileExists(atPath: dest.path) {
            dest = downloadsDir.appendingPathComponent("\(baseName) (\(counter)).\(ext)")
            counter += 1
        }
        return dest
    }

    // MARK: - Download Action
    public func startDownload(media: DetectedVideoMedia, quality: VideoQualityOption, webView: WKWebView? = nil) {
        let cleanTitle = sanitizeFilename(media.title)
        let ext = quality.format
        let filename = "\(cleanTitle)_\(quality.resolution)"

        let downloadItem = VideoDownloadItem(
            videoId: media.id,
            title: cleanTitle,
            qualityLabel: quality.label,
            progress: 0.05,
            statusText: "Starting download…"
        )
        activeDownloads.append(downloadItem)
        let downloadID = downloadItem.id

        // Case A: Blob Video (e.g. WhatsApp status)
        if media.isBlob || quality.url.hasPrefix("blob:") {
            if let webView = webView {
                initiateBlobDownloadInBrowser(blobURL: quality.url, videoId: media.id, filename: filename, quality: quality, webView: webView, downloadID: downloadID)
            } else {
                updateDownload(id: downloadID, progress: 0, status: "Error: WebKit view required for blob", error: "Missing webView context")
            }
            return
        }

        // Case B: Direct HTTP/HTTPS Media URL (Instagram, TikTok, LinkedIn, YouTube, Twitter)
        guard let url = URL(string: quality.url) else {
            updateDownload(id: downloadID, progress: 0, status: "Invalid URL", error: "Cannot parse URL")
            return
        }

        downloadDirectURL(url: url, quality: quality, downloadID: downloadID, filename: filename, ext: ext)
    }

    // MARK: - Direct URL Download Execution
    private func downloadDirectURL(url: URL, quality: VideoQualityOption, downloadID: UUID, filename: String, ext: String) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        let delegate = DownloadProgressDelegate(
            onProgress: { [weak self] progress in
                Task { @MainActor in
                    self?.updateDownload(id: downloadID, progress: progress * 0.85, status: "Downloading \(Int(progress * 100))%…")
                }
            },
            onCompletion: { [weak self] tempURL, response, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.updateDownload(id: downloadID, progress: 0, status: "Download failed", error: error.localizedDescription)
                    return
                }
                guard let tempURL = tempURL else {
                    self.updateDownload(id: downloadID, progress: 0, status: "No data received", error: "Empty response")
                    return
                }

                // If quality requires transcoding/conversion (e.g. 720p downscale or audio-only extraction)
                if quality.isTranscode, let preset = quality.exportPreset {
                    self.updateDownload(id: downloadID, progress: 0.90, status: "Processing audio & video quality…")
                    self.transcodeVideo(sourceURL: tempURL, presetName: preset, baseName: filename, ext: ext, downloadID: downloadID)
                } else {
                    // Save file directly with complete audio and original full quality
                    let finalDestination = self.createUniqueDestination(baseName: filename, ext: ext)
                    do {
                        try FileManager.default.moveItem(at: tempURL, to: finalDestination)
                        self.finishDownloadSuccess(id: downloadID, fileURL: finalDestination)
                    } catch {
                        self.updateDownload(id: downloadID, progress: 0, status: "Save failed", error: error.localizedDescription)
                    }
                }
            }
        })

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        activeSessions[downloadID] = task
        task.resume()
    }

    // MARK: - JavaScript Blob Download Bridge
    private func initiateBlobDownloadInBrowser(blobURL: String, videoId: String, filename: String, quality: VideoQualityOption, webView: WKWebView, downloadID: UUID) {
        updateDownload(id: downloadID, progress: 0.15, status: "Fetching status stream…")

        let escapedBlob = blobURL.replacingOccurrences(of: "'", with: "\\'")
        let escapedID = videoId.replacingOccurrences(of: "'", with: "\\'")
        let escapedFilename = filename.replacingOccurrences(of: "'", with: "\\'")
        let escapedQualityID = quality.id.replacingOccurrences(of: "'", with: "\\'")

        let script = """
        (async function() {
            try {
                const resp = await fetch('\(escapedBlob)');
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
                        window.webkit.messageHandlers.pinggoVideoDownload.postMessage({
                            action: 'blobChunk',
                            downloadID: '\(downloadID.uuidString)',
                            videoId: '\(escapedID)',
                            filename: '\(escapedFilename)',
                            qualityId: '\(escapedQualityID)',
                            chunk: chunk,
                            chunkIndex: chunkIndex++,
                            totalChunks: totalChunks,
                            isLast: isLast
                        });
                    }
                };
                reader.readAsDataURL(blob);
            } catch (err) {
                window.webkit.messageHandlers.pinggoVideoDownload.postMessage({
                    action: 'blobError',
                    downloadID: '\(downloadID.uuidString)',
                    error: err.toString()
                });
            }
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error = error {
                Task { @MainActor in
                    self?.updateDownload(id: downloadID, progress: 0, status: "Blob fetch error", error: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Blob Chunks Handling
    public func handleBlobChunkMessage(_ dict: [String: Any]) {
        guard let downloadIDString = dict["downloadID"] as? String,
              let downloadID = UUID(uuidString: downloadIDString) else { return }

        if let error = dict["error"] as? String {
            updateDownload(id: downloadID, progress: 0, status: "Status fetch failed", error: error)
            return
        }

        guard let chunk = dict["chunk"] as? String,
              let chunkData = Data(base64Encoded: chunk),
              let totalChunks = dict["totalChunks"] as? Int,
              let isLast = dict["isLast"] as? Bool,
              let filename = dict["filename"] as? String,
              let qualityId = dict["qualityId"] as? String else { return }

        var current = blobBuffers[downloadIDString] ?? (data: Data(), totalChunks: totalChunks, receivedChunks: 0, filename: filename, quality: VideoQualityOption(id: qualityId, label: qualityId, resolution: qualityId, url: ""))
        current.data.append(chunkData)
        current.receivedChunks += 1
        blobBuffers[downloadIDString] = current

        let progress = Double(current.receivedChunks) / Double(max(1, totalChunks))
        updateDownload(id: downloadID, progress: progress * 0.90, status: "Saving status video (\(Int(progress * 100))%)…")

        if isLast || current.receivedChunks >= totalChunks {
            blobBuffers.removeValue(forKey: downloadIDString)
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("\(UUID().uuidString).mp4")
            do {
                try current.data.write(to: tempFile)
                // If quality transcode requested
                let targetOption = current.quality
                if targetOption.isTranscode, let preset = targetOption.exportPreset {
                    updateDownload(id: downloadID, progress: 0.92, status: "Processing audio/video quality…")
                    transcodeVideo(sourceURL: tempFile, presetName: preset, baseName: filename, ext: targetOption.format, downloadID: downloadID)
                } else {
                    let finalDestination = createUniqueDestination(baseName: filename, ext: "mp4")
                    try FileManager.default.moveItem(at: tempFile, to: finalDestination)
                    finishDownloadSuccess(id: downloadID, fileURL: finalDestination)
                }
            } catch {
                updateDownload(id: downloadID, progress: 0, status: "Save failed", error: error.localizedDescription)
            }
        }
    }

    // MARK: - AVFoundation Transcoding / Quality Converter
    public func transcodeVideo(sourceURL: URL, presetName: String, baseName: String, ext: String, downloadID: UUID) {
        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            // Fallback: save source directly
            let finalDestination = createUniqueDestination(baseName: baseName, ext: "mp4")
            do {
                try FileManager.default.moveItem(at: sourceURL, to: finalDestination)
                finishDownloadSuccess(id: downloadID, fileURL: finalDestination)
            } catch {
                updateDownload(id: downloadID, progress: 0, status: "Export fallback failed", error: error.localizedDescription)
            }
            return
        }

        let finalDestination = createUniqueDestination(baseName: baseName, ext: ext)
        exportSession.outputURL = finalDestination
        if ext == "m4a" {
            exportSession.outputFileType = .m4a
        } else {
            exportSession.outputFileType = .mp4
        }
        exportSession.shouldOptimizeForNetworkUse = true

        nonisolated(unsafe) let session = exportSession
        session.exportAsynchronously { [weak self] in
            let status = session.status
            let errorMsg = session.error?.localizedDescription
            Task { @MainActor in
                guard let self = self else { return }
                switch status {
                case .completed:
                    self.finishDownloadSuccess(id: downloadID, fileURL: finalDestination)
                    try? FileManager.default.removeItem(at: sourceURL)
                case .failed, .cancelled:
                    // If export failed, copy original file so user never loses their download
                    let fallbackDestination = self.createUniqueDestination(baseName: baseName, ext: "mp4")
                    do {
                        try FileManager.default.moveItem(at: sourceURL, to: fallbackDestination)
                        self.finishDownloadSuccess(id: downloadID, fileURL: fallbackDestination)
                    } catch {
                        self.updateDownload(id: downloadID, progress: 0, status: "Processing error", error: errorMsg ?? "Transcode failed")
                    }
                default:
                    break
                }
            }
        }
    }

    // MARK: - State Updaters
    private func updateDownload(id: UUID, progress: Double, status: String, error: String? = nil) {
        guard let idx = activeDownloads.firstIndex(where: { $0.id == id }) else { return }
        activeDownloads[idx].progress = progress
        activeDownloads[idx].statusText = status
        if let error = error {
            activeDownloads[idx].error = error
        }
    }

    private func finishDownloadSuccess(id: UUID, fileURL: URL) {
        guard let idx = activeDownloads.firstIndex(where: { $0.id == id }) else { return }
        activeDownloads[idx].progress = 1.0
        activeDownloads[idx].statusText = "Completed"
        activeDownloads[idx].isComplete = true
        activeDownloads[idx].savedFileURL = fileURL
        activeSessions.removeValue(forKey: id)

        notificationMessage = "Downloaded: \(fileURL.lastPathComponent)"
        NSSound(named: "Glass")?.play()

        // Clear notification message after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            if self?.notificationMessage == "Downloaded: \(fileURL.lastPathComponent)" {
                self?.notificationMessage = nil
            }
        }
    }

    // MARK: - Universal Injected Sniffer Script
    public static let snifferScript: String = #"""
    (() => {
        if (window.__pinggo_sniffer_injected) return;
        window.__pinggo_sniffer_injected = true;

        const detectedMap = new Map();

        function getCleanTitle() {
            // Platform 1: Instagram
            const igCaption = document.querySelector('article h1, article div[data-ad-preview] span, article h2, header div span[dir="auto"]');
            if (igCaption && igCaption.innerText.trim()) {
                return igCaption.innerText.trim().slice(0, 70);
            }

            // Platform 2: TikTok
            const ttCaption = document.querySelector('h1[data-e2e="browse-video-desc"], [data-e2e="user-post-item-desc"]');
            if (ttCaption && ttCaption.innerText.trim()) {
                return ttCaption.innerText.trim().slice(0, 70);
            }

            // Platform 3: LinkedIn
            const liPost = document.querySelector('.feed-shared-update-v2__description, .update-components-text, .update-components-actor__title');
            if (liPost && liPost.innerText.trim()) {
                return liPost.innerText.trim().slice(0, 70);
            }

            // Platform 4: WhatsApp Status & Chat
            if (window.location.hostname.includes('web.whatsapp.com')) {
                const waStatusName = document.querySelector('[data-testid="status-viewer"] header span, header span[dir="auto"]');
                if (waStatusName && waStatusName.innerText.trim()) {
                    return 'WhatsApp_Status_' + waStatusName.innerText.trim().slice(0, 30);
                }
                return 'WhatsApp_Status';
            }

            // Platform 5: YouTube
            const ytTitle = document.querySelector('h1.ytd-watch-metadata, #title > h1, yt-formatted-string.ytd-watch-metadata');
            if (ytTitle && ytTitle.innerText.trim()) {
                return ytTitle.innerText.trim().slice(0, 90);
            }

            // Platform 6: Twitter / X
            const xText = document.querySelector('article div[data-testid="tweetText"]');
            if (xText && xText.innerText.trim()) {
                return 'X_' + xText.innerText.trim().slice(0, 60);
            }

            // Fallback: document.title
            let docTitle = document.title ? document.title.trim() : 'Video';
            return docTitle.replace(/[\r\n\t]/g, ' ').slice(0, 80);
        }

        function extractQualities(video) {
            const list = [];
            const seen = new Set();

            // 1. Inspect <source> tags
            const sources = video.querySelectorAll('source');
            sources.forEach(s => {
                const url = s.src || s.getAttribute('src');
                if (!url || seen.has(url)) return;
                seen.add(url);

                let res = 'Original Quality';
                const label = s.getAttribute('label') || s.getAttribute('title') || s.getAttribute('size') || '';
                if (label.includes('1080') || url.includes('1080p') || url.includes('mp4-1080')) res = '1080p';
                else if (label.includes('720') || url.includes('720p') || url.includes('mp4-720')) res = '720p';
                else if (label.includes('480') || url.includes('480p') || url.includes('mp4-480')) res = '480p';
                else if (label.includes('360') || url.includes('360p') || url.includes('mp4-360')) res = '360p';
                else if (label) res = label;

                list.push({
                    id: res.toLowerCase().replace(/\s+/g, '_'),
                    label: res === 'Original Quality' ? '🌟 Full Quality (Best Available)' : '📺 ' + res,
                    resolution: res,
                    url: url,
                    format: (s.type && s.type.includes('webm')) ? 'webm' : 'mp4'
                });
            });

            // 2. Inspect video.currentSrc and video.src
            const mainSrc = video.currentSrc || video.src;
            if (mainSrc && !seen.has(mainSrc) && !mainSrc.startsWith('data:')) {
                seen.add(mainSrc);
                let res = 'Full Quality';
                if (mainSrc.includes('1080p')) res = '1080p';
                else if (mainSrc.includes('720p')) res = '720p';
                else if (mainSrc.includes('480p')) res = '480p';

                list.unshift({
                    id: 'full',
                    label: '🌟 Full Quality (Original / Best Available)',
                    resolution: res,
                    url: mainSrc,
                    format: mainSrc.includes('.webm') ? 'webm' : 'mp4'
                });
            }

            return list;
        }

        function inspectVideoElement(video) {
            if (!video) return;
            const src = video.currentSrc || video.src;
            if (!src || src.length < 5 || src.startsWith('data:')) return;

            const isBlob = src.startsWith('blob:');
            const id = src;
            if (detectedMap.has(id)) return;

            const qualities = extractQualities(video);
            if (qualities.length === 0 && !isBlob) return;

            if (isBlob && qualities.length === 0) {
                qualities.push({
                    id: 'full',
                    label: '🌟 Full Quality (Original / Best Available)',
                    resolution: 'Original',
                    url: src,
                    format: 'mp4'
                });
            }

            const payload = {
                id: id,
                title: getCleanTitle(),
                pageURL: window.location.href,
                thumbnailURL: video.poster || '',
                duration: isFinite(video.duration) ? video.duration : 0,
                isBlob: isBlob,
                qualities: qualities
            };

            detectedMap.set(id, payload);

            // Notify Swift Host
            try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pinggoVideoSniffer) {
                    window.webkit.messageHandlers.pinggoVideoSniffer.postMessage(payload);
                }
            } catch (err) {}

            // Attach on-video floating hover badge
            attachFloatingPill(video, payload);
        }

        function attachFloatingPill(video, payload) {
            if (video.__pinggo_dl_pill) return;
            video.__pinggo_dl_pill = true;

            const rect = video.getBoundingClientRect();
            if (rect.width > 0 && rect.width < 140 && rect.height < 100) return; // Ignore small previews

            const pill = document.createElement('div');
            pill.className = 'pinggo-video-download-floating-pill';
            pill.style.position = 'absolute';
            pill.style.zIndex = '2147483647';
            pill.style.top = '12px';
            pill.style.right = '12px';
            pill.style.background = 'rgba(15, 17, 23, 0.88)';
            pill.style.backdropFilter = 'blur(12px)';
            pill.style.color = '#FFFFFF';
            pill.style.border = '1px solid rgba(255, 255, 255, 0.22)';
            pill.style.borderRadius = '20px';
            pill.style.padding = '6px 14px';
            pill.style.fontSize = '12px';
            pill.style.fontWeight = '600';
            pill.style.cursor = 'pointer';
            pill.style.display = 'none';
            pill.style.alignItems = 'center';
            pill.style.gap = '6px';
            pill.style.boxShadow = '0 4px 16px rgba(0,0,0,0.5)';
            pill.style.transition = 'all 0.18s cubic-bezier(0.16, 1, 0.3, 1)';
            pill.style.fontFamily = '-apple-system, BlinkMacSystemFont, "SF Pro", "Segoe UI", Roboto, sans-serif';
            pill.innerHTML = '<span style="color:#00B4D8;font-size:13px;">⬇</span> Download Video';

            pill.addEventListener('mouseenter', () => {
                pill.style.transform = 'scale(1.05)';
                pill.style.background = 'rgba(25, 30, 42, 0.96)';
                pill.style.borderColor = 'rgba(0, 180, 216, 0.6)';
            });
            pill.addEventListener('mouseleave', () => {
                pill.style.transform = 'scale(1.0)';
                pill.style.background = 'rgba(15, 17, 23, 0.88)';
                pill.style.borderColor = 'rgba(255, 255, 255, 0.22)';
            });

            pill.addEventListener('click', (e) => {
                e.stopPropagation();
                e.preventDefault();
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pinggoVideoDownload) {
                        window.webkit.messageHandlers.pinggoVideoDownload.postMessage({
                            action: 'triggerVideoDownload',
                            videoId: payload.id
                        });
                    }
                } catch (err) {}
            });

            const parent = video.parentElement || video;
            if (parent) {
                if (getComputedStyle(parent).position === 'static') {
                    parent.style.position = 'relative';
                }
                parent.appendChild(pill);

                parent.addEventListener('mouseenter', () => { pill.style.display = 'flex'; });
                parent.addEventListener('mouseleave', () => { pill.style.display = 'none'; });
            }
        }

        // 1. Scan current DOM
        function scanAllVideos() {
            const videos = document.querySelectorAll('video');
            videos.forEach(v => inspectVideoElement(v));
        }

        // 2. Intercept video play & src mutations
        const originalPlay = HTMLMediaElement.prototype.play;
        HTMLMediaElement.prototype.play = function() {
            if (this instanceof HTMLVideoElement) {
                inspectVideoElement(this);
            }
            return originalPlay.apply(this, arguments);
        };

        // 3. Mutation Observer for infinite scroll feeds (Instagram, TikTok, LinkedIn, WhatsApp Status)
        const observer = new MutationObserver(mutations => {
            for (const m of mutations) {
                if (m.type === 'childList') {
                    m.addedNodes.forEach(node => {
                        if (node.nodeType === 1) {
                            if (node.tagName === 'VIDEO') {
                                inspectVideoElement(node);
                            } else if (node.querySelectorAll) {
                                const vids = node.querySelectorAll('video');
                                vids.forEach(v => inspectVideoElement(v));
                            }
                        }
                    });
                } else if (m.type === 'attributes' && (m.attributeName === 'src' || m.attributeName === 'currentSrc')) {
                    if (m.target && m.target.tagName === 'VIDEO') {
                        inspectVideoElement(m.target);
                    }
                }
            }
        });

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['src']
        });

        // Run scans
        scanAllVideos();
        setTimeout(scanAllVideos, 1000);
        setTimeout(scanAllVideos, 3000);
    })();
    """#
}

// MARK: - URLSession Download Delegate Helper
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let onCompletion: @Sendable (URL?, URLResponse?, Error?) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void, onCompletion: @escaping @Sendable (URL?, URLResponse?, Error?) -> Void) {
        self.onProgress = onProgress
        self.onCompletion = onCompletion
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            onProgress(progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move to temporary location before system removes original download temp file
        let tempDestination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_" + (downloadTask.response?.suggestedFilename ?? "video.mp4"))
        do {
            try FileManager.default.moveItem(at: location, to: tempDestination)
            onCompletion(tempDestination, downloadTask.response, nil)
        } catch {
            onCompletion(nil, downloadTask.response, error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onCompletion(nil, task.response, error)
        }
    }
}
