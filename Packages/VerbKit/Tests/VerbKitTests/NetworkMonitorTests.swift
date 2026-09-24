import XCTest
@testable import VerbKit

final class NetworkMonitorTests: XCTestCase {
    func testStartAndStopDoesNotCrash() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.stop()
    }

    func testOnChangeCanBeAssignedWithoutCrashing() {
        // Real transitions can't be forced in-process (no fake network
        // stack) — this only confirms wiring the callback compiles and
        // doesn't crash; actual reconnect behavior is verified manually
        // in Task 11 via Simulator airplane mode.
        let monitor = NetworkMonitor()
        monitor.onChange = { _ in }
        monitor.start()
        monitor.stop()
    }
}
