import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var hasRequestedPermission = false
    private var lastNotifiedMessageIDs: Set<String> = []

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NotificationService] Authorization error: \(error.localizedDescription)")
            }
        }
    }

    func notifyNewMessage(
        platformName: String,
        platformID: String,
        accountName: String,
        sender: String,
        previewText: String,
        messageID: String
    ) {
        // Do not spam notifications if user is actively in the app
        guard !NSApp.isActive else { return }
        guard !lastNotifiedMessageIDs.contains(messageID) else { return }
        lastNotifiedMessageIDs.insert(messageID)
        if lastNotifiedMessageIDs.count > 200 {
            lastNotifiedMessageIDs.removeFirst()
        }

        let content = UNMutableNotificationContent()
        content.title = "\(sender) (\(platformName))"
        content.subtitle = accountName
        content.body = previewText.isEmpty ? "New message received" : previewText
        content.sound = .default
        content.userInfo = ["platformID": platformID]

        let request = UNNotificationRequest(
            identifier: "msg_\(messageID)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationService] Notification delivery error: \(error.localizedDescription)")
            }
        }
    }

    // Handle user clicking the notification banner
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let platformID = userInfo["platformID"] as? String {
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(
                    name: Notification.Name("NavigateToPlatform"),
                    object: platformID
                )
            }
        }
        completionHandler()
    }

    // Display banner even if app becomes active mid-delivery
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
