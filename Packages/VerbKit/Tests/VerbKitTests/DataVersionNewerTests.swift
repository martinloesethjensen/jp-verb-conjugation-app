import XCTest
@testable import VerbKit

/// `isNewer` decides whether a bundled copy is installed: only when it is readable and strictly newer than
/// the rollback floor the device recorded.
final class DataVersionNewerTests: XCTestCase {
    func testNoFloorInstallsAReadableVersion() {
        XCTAssertTrue(DataVersion.isNewer("1.0.0", than: nil))
    }

    func testAnOlderFloorInstalls() {
        XCTAssertTrue(DataVersion.isNewer("1.5.0", than: "1.4.9"))
        XCTAssertTrue(DataVersion.isNewer("2.0.0", than: "1.99.0"))
        XCTAssertTrue(DataVersion.isNewer("1.2", than: "1.1.9"))
    }

    func testAnEqualFloorDoesNotInstall() {
        XCTAssertFalse(DataVersion.isNewer("1.4.0", than: "1.4.0"))
        XCTAssertFalse(DataVersion.isNewer("1.4", than: "1.4.0"))
    }

    func testANewerFloorNeverInstalls() {
        XCTAssertFalse(DataVersion.isNewer("1.3.0", than: "1.4.0"))
        XCTAssertFalse(DataVersion.isNewer("0.9.0", than: "1.0.0"))
    }

    func testAnUnreadableBundledVersionNeverInstalls() {
        XCTAssertFalse(DataVersion.isNewer("garbage", than: nil))
        XCTAssertFalse(DataVersion.isNewer("", than: "1.0.0"))
        XCTAssertFalse(DataVersion.isNewer("1.x.0", than: "0.0.1"))
    }

    func testAnUnreadableFloorIsReplaced() {
        XCTAssertTrue(DataVersion.isNewer("1.0.0", than: "garbage"))
    }
}
