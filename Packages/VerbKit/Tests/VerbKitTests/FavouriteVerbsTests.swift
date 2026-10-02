import XCTest
@testable import VerbKit

final class FavouriteVerbsTests: XCTestCase {
    private func verbs() throws -> [Verb] { try RealVerbs.load() }

    func testRoundTripsThroughTheStoredString() {
        let favourites = FavouriteVerbs(ids: ["たべる", "いく"])
        XCTAssertEqual(favourites.rawValue, "いく\nたべる".split(separator: "\n").sorted().joined(separator: "\n"))
        XCTAssertEqual(FavouriteVerbs(rawValue: favourites.rawValue), favourites)
    }

    func testEmptyAndNilParseToNoFavourites() {
        XCTAssertTrue(FavouriteVerbs(rawValue: nil).isEmpty)
        XCTAssertTrue(FavouriteVerbs(rawValue: "").isEmpty)
        XCTAssertTrue(FavouriteVerbs(rawValue: "\n\n").isEmpty)
    }

    func testToggleAddsThenRemoves() throws {
        let taberu = try XCTUnwrap(try verbs().first { $0.dict == "たべる" })
        var favourites = FavouriteVerbs()
        favourites.toggle(taberu)
        XCTAssertTrue(favourites.contains(taberu))
        favourites.toggle(taberu)
        XCTAssertFalse(favourites.contains(taberu))
    }

    func testFilterKeepsOriginalOrderAndIgnoresUnknownIds() throws {
        let all = try verbs()
        let favourites = FavouriteVerbs(ids: ["かく", "する", "no-such-verb"])
        XCTAssertEqual(favourites.filter(all).map(\.dict), all.map(\.dict).filter { ["かく", "する"].contains($0) })
        XCTAssertEqual(favourites.count(in: all), 2)
    }
}
