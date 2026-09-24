import Network
import Observation

@Observable
public final class NetworkMonitor: @unchecked Sendable {
    public private(set) var isConnected: Bool
    /// Fires on every transition (including the initial status reported
    /// right after `start()`). `VerbStore` (Task 9) uses this to retry
    /// the first-launch fetch automatically once connectivity returns.
    public var onChange: ((Bool) -> Void)?
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "VerbKit.NetworkMonitor")

    public init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        self.isConnected = monitor.currentPath.status == .satisfied
    }

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = connected
                self?.onChange?(connected)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}
