import SwiftUI
import WebKit

struct AILoginProviderItem: Identifiable {
    let id: String
}

struct AILoginWebSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let provider: String // "gemini" or "chatgpt"

    @State private var pageTitle: String = "Connecting..."
    @State private var currentURLString: String = ""
    @State private var isConnected = false

    private var targetURL: URL {
        provider == "gemini" ? AIService.geminiURL : AIService.chatGptURL
    }

    private var providerName: String {
        provider == "gemini" ? "Google Gemini" : "OpenAI ChatGPT"
    }

    private var providerColor: Color {
        provider == "gemini" ? Color(red: 0.26, green: 0.52, blue: 0.96) : Color(red: 0.06, green: 0.65, blue: 0.53)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(providerColor.opacity(0.14)).frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(providerColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Connect \(providerName)")
                            .font(.system(size: 14, weight: .bold))
                        if isConnected {
                            HStack(spacing: 3) {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("Active Session")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                        }
                    }
                    Text("Log in with your personal account. Cookies are isolated to PINGGO's secure partition.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }

                Spacer()

                Button {
                    if provider == "gemini" {
                        store.preferences.isGeminiLoggedIn = true
                    } else {
                        store.preferences.isChatGptLoggedIn = true
                    }
                    store.showToast("\(providerName) connected successfully!")
                    dismiss()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Done / Connected")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(providerColor)
                .controlSize(.small)

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Palette.panel)

            Divider()

            // WebKit View
            AIWebLoginView(
                url: targetURL,
                dataStore: provider == "gemini" ? AIService.shared.geminiDataStore : AIService.shared.chatGptDataStore,
                onTitleChange: { title in pageTitle = title },
                onURLChange: { url in
                    currentURLString = url.absoluteString
                    if provider == "gemini" && url.host?.contains("gemini.google.com") == true && !url.path.contains("signin") {
                        isConnected = true
                        store.preferences.isGeminiLoggedIn = true
                    } else if provider == "chatgpt" && url.host?.contains("chatgpt.com") == true && !url.path.contains("auth") {
                        isConnected = true
                        store.preferences.isChatGptLoggedIn = true
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 900, height: 660)
    }
}

struct AIWebLoginView: NSViewRepresentable {
    let url: URL
    let dataStore: WKWebsiteDataStore
    let onTitleChange: (String) -> Void
    let onURLChange: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 660), configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.2 Safari/605.1.15"
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: AIWebLoginView

        init(_ parent: AIWebLoginView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let title = webView.title { parent.onTitleChange(title) }
            if let current = webView.url { parent.onURLChange(current) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if let targetURL = navigationAction.request.url {
                parent.onURLChange(targetURL)
            }
            decisionHandler(.allow)
        }
    }
}
