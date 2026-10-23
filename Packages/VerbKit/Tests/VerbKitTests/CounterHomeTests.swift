import XCTest
@testable import VerbKit

final class CounterHomeTests: XCTestCase {
    private func counter(_ id: String) -> Counter {
        Counter(id: id, counter: id, reading: id, meaning: id, sound: "plain", symbol: "pencil", readings: [:])
    }

    private let drinks = CounterSection(id: "drinks", title: "Drinks", counters: ["hai", "hon"])
    private let things = CounterSection(id: "things", title: "Things", counters: ["mai", "hon"])
    private var all: [Counter] { ["hai", "hon", "mai"].map(counter) }

    func testACounterInTwoSectionsGetsTwoRowsWithDifferentIDs() {
        let home = homeSections([drinks, things], counters: all)
        let hon = home.flatMap(\.rows).filter { $0.counter.id == "hon" }
        XCTAssertEqual(hon.count, 2)
        XCTAssertEqual(Set(hon.map(\.id)).count, 2)
        XCTAssertEqual(Set(home.flatMap(\.rows).map(\.id)).count, 4)
    }

    func testRowsFollowTheSectionsOrderAndSkipHiddenCounters() {
        let home = homeSections([drinks, things], counters: all.filter { $0.id != "hai" })
        XCTAssertEqual(home.map(\.id), ["drinks", "things"])
        XCTAssertEqual(home[0].rows.map(\.counter.id), ["hon"])
        XCTAssertEqual(home[1].rows.map(\.counter.id), ["mai", "hon"])
    }

    func testASectionWithEveryCounterHiddenIsDropped() {
        let home = homeSections([drinks, things], counters: [counter("mai")])
        XCTAssertEqual(home.map(\.id), ["things"])
    }

    func testOnlyASectionWithSeveralCountersCanCompare() {
        let home = homeSections([drinks, things], counters: all.filter { $0.id != "mai" })
        XCTAssertTrue(home[0].canCompare)
        XCTAssertFalse(home[1].canCompare)
    }

    func testNothingVisibleGivesNoSections() {
        XCTAssertTrue(homeSections([drinks, things], counters: []).isEmpty)
    }
}
