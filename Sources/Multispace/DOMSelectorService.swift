import Foundation

struct DOMSelectorsConfig: Codable {
    var version: Int
    var lastUpdated: String
    var inputSelectors: [String]
    var chatItemSelectors: [String]
    var groupMemberRowSelectors: [String]
    var adminKeywords: [String]

    static let `default` = DOMSelectorsConfig(
        version: 1,
        lastUpdated: "2026-10-05",
        inputSelectors: [
            "div[role=\"textbox\"][aria-label*=\"message\" i]",
            "div[role=\"textbox\"][aria-label*=\"type\" i]",
            "div[role=\"textbox\"][aria-label*=\"send\" i]",
            "footer [role=\"textbox\"]",
            "form [role=\"textbox\"]",
            "footer textarea",
            "form textarea"
        ],
        chatItemSelectors: [
            "#main [data-testid=\"cell-frame-container\"]",
            "#main .message-in",
            "#main .message-out"
        ],
        groupMemberRowSelectors: [
            "[data-testid=\"cell-frame-container\"]",
            "div[role=\"listitem\"]",
            ".chatlist-item"
        ],
        adminKeywords: [
            "admin",
            "owner",
            "creator",
            "group admin"
        ]
    )
}

@MainActor
final class DOMSelectorService {
    static let shared = DOMSelectorService()

    private(set) var config: DOMSelectorsConfig = .default
    private let remoteURL = URL(string: "https://raw.githubusercontent.com/rahulonit/multi-space-app/main/Resources/selectors.json")
    private let cacheFileName = "selectors_cache.json"

    private init() {
        loadCachedConfig()
    }

    func fetchLatestRemoteSelectors() {
        guard let remoteURL else { return }
        Task {
            do {
                var request = URLRequest(url: remoteURL)
                request.timeoutInterval = 5
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }
                let downloaded = try JSONDecoder().decode(DOMSelectorsConfig.self, from: data)
                if downloaded.version > self.config.version {
                    self.config = downloaded
                    self.saveCache(data: data)
                    print("[DOMSelectorService] Updated to remote selector config version \(downloaded.version)")
                }
            } catch {
                // Offline or unreachable - silently retain bundled or cached config
            }
        }
    }

    private func loadCachedConfig() {
        guard let cacheURL = cacheFileURL(),
              let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(DOMSelectorsConfig.self, from: data) else {
            return
        }
        self.config = cached
    }

    private func saveCache(data: Data) {
        guard let cacheURL = cacheFileURL() else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    private func cacheFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("Multispace")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(cacheFileName)
    }

    func generateInjectionScript() -> String {
        guard let jsonData = try? JSONEncoder().encode(config),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }
        return "window.__pinggoRemoteSelectors = \(jsonString);"
    }
}
