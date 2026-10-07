import Foundation
import AVFoundation
import AppKit

@MainActor
final class MediaHardwareService: ObservableObject {
    static let shared = MediaHardwareService()

    @Published var isCallActive: Bool = false
    @Published var callDuration: Int = 0
    @Published var activePlatformName: String = "Call"
    @Published var isMicMuted: Bool = false
    private var timer: Timer?

    func startCallTracking(platformName: String) {
        isCallActive = true
        activePlatformName = platformName
        callDuration = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.callDuration += 1
            }
        }
    }

    func endCallTracking() {
        isCallActive = false
        callDuration = 0
        timer?.invalidate()
        timer = nil
    }

    var formattedDuration: String {
        let mins = callDuration / 60
        let secs = callDuration % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Ensures system-level TCC permissions for Camera and Microphone are requested
    /// before WebKit attempts WebRTC media capture for WhatsApp/Slack/Discord calls.
    static func ensureMediaAccess() {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("[MediaHardwareService] System camera permission: \(granted ? "granted" : "denied")")
            }
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                print("[MediaHardwareService] System microphone permission: \(granted ? "granted" : "denied")")
            }
        }
    }

    static var isCameraAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    static var isMicrophoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
