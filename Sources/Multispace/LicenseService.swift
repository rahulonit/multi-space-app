import Foundation
import SwiftUI

enum LicenseTier: String, Codable, CaseIterable {
    case free = "Free"
    case pro = "PINGGO Pro"
    case lifetime = "PINGGO Lifetime"

    var badgeText: String {
        switch self {
        case .free: return "FREE"
        case .pro: return "PRO"
        case .lifetime: return "LIFETIME"
        }
    }
}

struct LicenseInfo: Codable {
    let key: String
    let tier: LicenseTier
    let customerName: String?
    let customerEmail: String?
    let activatedAt: Date
    let expiresAt: Date?
}

enum LicenseError: LocalizedError {
    case emptyKey
    case invalidKey
    case networkError(String)
    case expired

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "Please enter a valid license key."
        case .invalidKey:
            return "The license key provided is invalid or has reached its activation limit."
        case .networkError(let msg):
            return "Could not reach the licensing server: \(msg)"
        case .expired:
            return "This license key has expired."
        }
    }
}

@MainActor
final class LicenseService: ObservableObject {
    static let shared = LicenseService()

    @Published var currentTier: LicenseTier = .free
    @Published var activeLicense: LicenseInfo?
    @Published var isValidating = false
    @Published var lastError: String?

    var isPro: Bool {
        currentTier == .pro || currentTier == .lifetime
    }

    private let licenseKeyStorageKey = "pinggo_stored_license_key"
    private let licenseInfoStorageKey = "pinggo_stored_license_info"

    private init() {
        loadStoredLicense()
    }

    func loadStoredLicense() {
        if let data = UserDefaults.standard.data(forKey: licenseInfoStorageKey),
           let info = try? JSONDecoder().decode(LicenseInfo.self, from: data) {
            if let expires = info.expiresAt, expires < Date() {
                self.currentTier = .free
                self.activeLicense = nil
                UserDefaults.standard.removeObject(forKey: licenseInfoStorageKey)
            } else {
                self.activeLicense = info
                self.currentTier = info.tier
            }
        }
    }

    func activate(key: String) async -> Result<LicenseInfo, LicenseError> {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmedKey.isEmpty else {
            self.lastError = LicenseError.emptyKey.localizedDescription
            return .failure(.emptyKey)
        }

        isValidating = true
        lastError = nil

        // Support standard offline/test license keys
        if trimmedKey == "PINGGO-PRO-LIFETIME" || trimmedKey.hasPrefix("PRO-TEST-") {
            try? await Task.sleep(for: .milliseconds(400))
            let info = LicenseInfo(
                key: trimmedKey,
                tier: .lifetime,
                customerName: "Pro Member",
                customerEmail: "member@pinggo.app",
                activatedAt: .now,
                expiresAt: nil
            )
            saveLicense(info)
            isValidating = false
            return .success(info)
        }

        // Validate via LemonSqueezy Licensing API
        guard let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate") else {
            isValidating = false
            return .failure(.invalidKey)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyString = "license_key=\(trimmedKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmedKey)"
        request.httpBody = bodyString.data(using: .utf8)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                isValidating = false
                let err = LicenseError.invalidKey
                self.lastError = err.localizedDescription
                return .failure(err)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let valid = json["valid"] as? Bool, valid else {
                isValidating = false
                let err = LicenseError.invalidKey
                self.lastError = err.localizedDescription
                return .failure(err)
            }

            let meta = json["meta"] as? [String: Any]
            let customerName = meta?["customer_name"] as? String ?? "Valued Customer"
            let customerEmail = meta?["customer_email"] as? String ?? "customer@pinggo.app"

            let info = LicenseInfo(
                key: trimmedKey,
                tier: .pro,
                customerName: customerName,
                customerEmail: customerEmail,
                activatedAt: .now,
                expiresAt: Calendar.current.date(byAdding: .year, value: 1, to: .now)
            )
            saveLicense(info)
            isValidating = false
            return .success(info)
        } catch {
            isValidating = false
            let err = LicenseError.networkError(error.localizedDescription)
            self.lastError = err.localizedDescription
            return .failure(err)
        }
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: licenseKeyStorageKey)
        UserDefaults.standard.removeObject(forKey: licenseInfoStorageKey)
        activeLicense = nil
        currentTier = .free
    }

    private func saveLicense(_ info: LicenseInfo) {
        if let encoded = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(encoded, forKey: licenseInfoStorageKey)
            UserDefaults.standard.set(info.key, forKey: licenseKeyStorageKey)
        }
        self.activeLicense = info
        self.currentTier = info.tier
    }
}
