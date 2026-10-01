import XCTest
@testable import VerbKit

final class RouteURLTests: XCTestCase {
    func testVerbRoundTrip() {
        let route = Route.verb("たべる")
        XCTAssertEqual(Route(url: route.url), route)
        XCTAssertEqual(route.url.scheme, "verbtable")
        XCTAssertEqual(route.url.host, "verb")
    }

    func testGrammarRoundTrip() {
        let route = Route.grammar("n-desu")
        XCTAssertEqual(Route(url: route.url), route)
    }

    func testIdWithSpaceAndSlashRoundTrips() {
        for id in ["to eat", "a/b", "100%"] {
            XCTAssertEqual(Route(url: Route.verb(id).url), .verb(id))
        }
    }

    func testParsesPercentEncodedLink() throws {
        let url = try XCTUnwrap(URL(string: "verbtable://verb/%E3%81%9F%E3%81%B9%E3%82%8B"))
        XCTAssertEqual(Route(url: url), .verb("たべる"))
    }

    func testRejectsOtherLinks() throws {
        for text in ["https://verb/たべる", "verbtable://other/x", "verbtable://verb", "verbtable://verb/", "verbtable:///x"] {
            let url = try XCTUnwrap(URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text))
            XCTAssertNil(Route(url: url), text)
        }
    }
}
