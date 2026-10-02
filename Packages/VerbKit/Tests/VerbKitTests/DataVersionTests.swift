import XCTest
@testable import VerbKit

final class DataVersionTests: XCTestCase {
    func testOrdersNumericallyNotAsText() {
        XCTAssertTrue(DataVersion.isOlder("1.9.0", than: "1.10.0"))
        XCTAssertFalse(DataVersion.isOlder("1.10.0", than: "1.9.0"))
    }

    func testEqualIsNotOlder() {
        XCTAssertFalse(DataVersion.isOlder("1.4.0", than: "1.4.0"))
        XCTAssertFalse(DataVersion.isOlder("1.4", than: "1.4.0"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertTrue(DataVersion.isOlder("1.4", than: "1.4.1"))
    }

    func testUnreadableVersionsCountAsOlder() {
        XCTAssertTrue(DataVersion.isOlder("latest", than: "1.0.0"))
        XCTAssertTrue(DataVersion.isOlder("1.0.0", than: "garbage"))
        XCTAssertTrue(DataVersion.isOlder("", than: "1.0.0"))
        XCTAssertTrue(DataVersion.isOlder("-1.0.0", than: "1.0.0"))
    }
}
