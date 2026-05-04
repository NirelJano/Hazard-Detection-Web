import Foundation
import Network

final class ReachabilityMonitor {
    static let shared = ReachabilityMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.hazarddetection.reachability", qos: .utility)

    /// Fires on the main queue whenever the network transitions from offline to online.
    var onReachable: (() -> Void)?

    /// Synchronous check against the monitor's current path. Safe to call from any thread.
    var isOnline: Bool {
        monitor.currentPath.status == .satisfied
    }

    private init() {
        var wasReachable = false
        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            DispatchQueue.main.async { [weak self] in
                if reachable && !wasReachable {
                    self?.onReachable?()
                }
                wasReachable = reachable
            }
        }
        monitor.start(queue: queue)
    }
}
