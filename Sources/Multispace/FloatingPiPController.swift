import AppKit
import SwiftUI
import WebKit

@MainActor
final class FloatingPiPController: ObservableObject {
    static let shared = FloatingPiPController()

    private var pipPanel: NSPanel?
    @Published var isPiPActive: Bool = false
    @Published var currentMediaTitle: String = ""

    func showPiP(videoURL: URL, title: String) {
        currentMediaTitle = title

        if let existing = pipPanel {
            if let webView = existing.contentView as? WKWebView {
                webView.load(URLRequest(url: videoURL))
            }
            existing.title = "PINGGO PiP: \(title)"
            existing.orderFront(nil)
            isPiPActive = true
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 120, y: 120, width: 480, height: 280),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.title = "PINGGO PiP: \(title)"
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 280), configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.load(URLRequest(url: videoURL))

        panel.contentView = webView
        panel.center()
        panel.orderFront(nil)

        self.pipPanel = panel
        self.isPiPActive = true
    }

    func closePiP() {
        pipPanel?.close()
        pipPanel = nil
        isPiPActive = false
    }
}
