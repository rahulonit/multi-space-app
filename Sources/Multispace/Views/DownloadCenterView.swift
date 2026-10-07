import SwiftUI
import AppKit

// MARK: - Universal Download Center Popover / View
public struct DownloadCenterView: View {
    @ObservedObject private var manager = VideoDownloadManager.shared
    @State private var pastedURLText: String = ""
    @State private var customTitleText: String = ""
    @State private var showingURLInput: Bool = false
    @State private var showCopiedAlert: Bool = false

    public init() {}

    private var ongoingDownloads: [VideoDownloadItem] {
        manager.activeDownloads.filter { !$0.isComplete }
    }

    private var completedDownloads: [VideoDownloadItem] {
        manager.activeDownloads.filter { $0.isComplete && $0.savedFileURL != nil }.reversed()
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if showingURLInput {
                urlInputSection
                Divider()
            }

            ScrollView {
                VStack(spacing: 14) {
                    if !ongoingDownloads.isEmpty {
                        activeSection
                    }

                    if !completedDownloads.isEmpty {
                        completedSection
                    }

                    if ongoingDownloads.isEmpty && completedDownloads.isEmpty {
                        emptyStateView
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 460)

            footerBar
        }
        .frame(width: 390)
        .background(Palette.panel)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.accent)

            Text("Downloads & Media")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.text)

            if !ongoingDownloads.isEmpty {
                Text("\(ongoingDownloads.count) active")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.accent.opacity(0.12), in: Capsule())
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showingURLInput.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showingURLInput ? "xmark" : "plus.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(showingURLInput ? "Close" : "Paste Link")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Palette.accent.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Download video from a direct URL or streaming link")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - URL Input Section
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DOWNLOAD VIDEO FROM URL")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Palette.muted)

            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)

                TextField("Paste MP4, M3U8, or media stream URL…", text: $pastedURLText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Palette.border, lineWidth: 1))

            HStack {
                TextField("Optional Title (e.g. Tutorial Video)", text: $customTitleText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Palette.border, lineWidth: 0.8))

                Button("Start Download") {
                    let urlStr = pastedURLText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !urlStr.isEmpty else { return }
                    manager.downloadFromDirectURL(urlString: urlStr, customTitle: customTitleText.isEmpty ? nil : customTitleText)
                    pastedURLText = ""
                    customTitleText = ""
                    withAnimation { showingURLInput = false }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Palette.accent)
                .disabled(pastedURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(Palette.card.opacity(0.5))
    }

    // MARK: - Active Section
    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("IN PROGRESS (\(ongoingDownloads.count))")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Spacer()
            }

            ForEach(ongoingDownloads) { item in
                activeDownloadCard(item: item)
            }
        }
    }

    // MARK: - Active Download Card
    private func activeDownloadCard(item: VideoDownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.isPaused ? "pause.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(item.error != nil ? Color.red : (item.isPaused ? Color.orange : Palette.accent))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(item.qualityLabel)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Palette.muted)

                        if item.error != nil {
                            Text("• Error")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Color.red)
                        } else if item.isPaused {
                            Text("• Paused")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Color.orange)
                        }
                    }
                }

                Spacer()

                // Actions: Pause / Resume / Cancel / Retry
                HStack(spacing: 6) {
                    if item.error != nil {
                        Button {
                            manager.retryDownload(id: item.id)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Retry download")
                    } else if item.isPaused {
                        Button {
                            manager.resumeDownload(id: item.id)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.green)
                        }
                        .buttonStyle(.plain)
                        .help("Resume download")
                    } else {
                        Button {
                            manager.pauseDownload(id: item.id)
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Palette.muted)
                        }
                        .buttonStyle(.plain)
                        .help("Pause download")
                    }

                    Button {
                        manager.cancelDownload(id: item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Cancel download")
                }
            }

            // Linear Progress Bar
            ProgressView(value: max(0.02, item.progress))
                .progressViewStyle(.linear)
                .tint(item.error != nil ? Color.red : (item.isPaused ? Color.orange : Palette.accent))

            // Metrics row: bytes, speed, ETA, status
            HStack(spacing: 5) {
                if item.totalBytes > 0 {
                    Text("\(VideoDownloadManager.formatBytes(item.bytesWritten)) / \(VideoDownloadManager.formatBytes(item.totalBytes))")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)

                    if item.speedBytesPerSecond > 0 && !item.isPaused {
                        Text("•")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.muted.opacity(0.6))
                        Text(VideoDownloadManager.formatSpeed(item.speedBytesPerSecond))
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Palette.text)
                    }

                    if let eta = item.estimatedTimeRemaining, eta > 0 && !item.isPaused {
                        Text("•")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.muted.opacity(0.6))
                        Text(VideoDownloadManager.formatTimeRemaining(eta))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.muted)
                    }
                } else {
                    Text(item.error ?? item.statusText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(item.error != nil ? Color.red : Palette.muted)
                }

                Spacer()

                Text("\(Int(item.progress * 100))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.text)
            }
        }
        .padding(10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
    }

    // MARK: - Completed Section
    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("COMPLETED VIDEOS (\(completedDownloads.count))")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Palette.muted)

                Spacer()

                Button("Clear") {
                    withAnimation { manager.clearCompletedDownloads() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.muted)
            }

            ForEach(completedDownloads) { item in
                completedDownloadCard(item: item)
            }
        }
    }

    // MARK: - Completed Download Card
    private func completedDownloadCard(item: VideoDownloadItem) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.accent.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "film.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.qualityLabel)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.muted)

                    if let fileURL = item.savedFileURL,
                       let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                       let size = attrs[.size] as? Int64 {
                        Text("• \(VideoDownloadManager.formatBytes(size))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.muted)
                    }
                }
            }

            Spacer()

            if let fileURL = item.savedFileURL {
                HStack(spacing: 8) {
                    // Play
                    Button {
                        VideoDownloadManager.openSavedFile(fileURL)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Play video")

                    // Floating Picture-in-Picture
                    Button {
                        FloatingPiPController.shared.showPiP(videoURL: fileURL, title: item.title)
                    } label: {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Watch in floating Picture-in-Picture window")

                    // Show in Finder
                    Button {
                        VideoDownloadManager.revealSavedFileInFinder(fileURL)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")

                    // Remove from list
                    Button {
                        manager.removeDownload(id: item.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Remove from list")
                }
            }
        }
        .padding(8)
        .background(Palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.border, lineWidth: 0.8))
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28))
                .foregroundStyle(Palette.muted.opacity(0.5))
                .padding(.top, 16)

            Text("No Downloads Yet")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.text)

            Text("Videos detected on WhatsApp Status, Instagram, TikTok, LinkedIn, or web pages will appear here. You can also paste any video link.")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack {
            let folderURL = manager.createUniqueDestination(baseName: "test", ext: "tmp").deletingLastPathComponent()
            Text("Saving to: \(folderURL.lastPathComponent)")
                .font(.system(size: 10))
                .foregroundStyle(Palette.muted)

            Spacer()

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([folderURL])
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder")
                        .font(.system(size: 9.5))
                    Text("Open Folder")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Palette.panel)
    }
}
