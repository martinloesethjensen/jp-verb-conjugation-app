import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class SwiftDataCountersPersistingTests: XCTestCase {
    static func file(ids: [String]) -> CountersDataFile {
        let counters = ids.map {
            Counter(id: $0, counter: "本", reading: "ほん", meaning: "m", jlpt: .n5, sound: "h-b", symbol: "pencil",
                    readings: ["1": ["いっぽん"]], changed: ["1"])
        }
        let group = CounterGroup(id: "g", title: "G", symbol: "pencil", summary: "s",
                                 members: ids.map { CounterGroupMember(counter: $0, note: "n") })
        return CountersDataFile(version: "1.0.0", description: "d", counters: counters, groups: [group])
    }

    func testRoundTripKeepsCountersAndGroupsAndReplaces() throws {
        let container = try VerbModelContainer.makeInMemory()
        let persisting = SwiftDataCountersPersisting(modelContext: ModelContext(container))
        XCTAssertNil(try persisting.loadCounters())
        let first = Self.file(ids: ["a", "b"])
        try persisting.replaceCounters(with: first)
        XCTAssertEqual(try persisting.loadCounters(), first)
        let second = Self.file(ids: ["c"])
        try persisting.replaceCounters(with: second)
        XCTAssertEqual(try persisting.loadCounters(), second)
    }
}
