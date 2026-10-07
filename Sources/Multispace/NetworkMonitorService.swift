import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitorService: ObservableObject {
    static let shared = NetworkMonitorService()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var isExpensive: Bool = false
    @Published private(set) var connectionDescription: String = "Connected"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.pinggo.networkmonitor")
    private var wasPreviouslyDisconnected = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let connected = (path.status == .satisfied)
                let expensive = path.isExpensive

                let desc: String
                if !connected {
                    desc = "No Internet Connection"
                } else if path.usesInterfaceType(.wifi) {
                    desc = "Wi-Fi"
                } else if path.usesInterfaceType(.cellular) {
                    desc = "Cellular"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    desc = "Ethernet"
                } else {
                    desc = "Connected"
                }

                let reconnected = (!self.isConnected && connected) || (self.wasPreviouslyDisconnected && connected)
                self.isConnected = connected
                self.isExpensive = expensive
                self.connectionDescription = desc

                if reconnected {
                    self.wasPreviouslyDisconnected = false
                    print("[NetworkMonitorService] Internet restored. Notifying portals...")
                    NotificationCenter.default.post(name: Notification.Name("NetworkDidReconnect"), object: nil)
                } else if !connected {
                    self.wasPreviouslyDisconnected = true
                    print("[NetworkMonitorService] Internet disconnected.")
                    NotificationCenter.default.post(name: Notification.Name("NetworkDidDisconnect"), object: nil)
                }
            }
        }
        monitor.start(queue: queue)
    }

    func start() {
        // Initializes singleton instance
        _ = isConnected
    }
}
