import XCTest
@testable import VerbKit

/// Guards the real `data/counters.json` the app fetches.
final class RealCountersDataTests: XCTestCase {
    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private func load() throws -> CountersDataFile {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("data/counters.json"))
        return try JSONDecoder().decode(CountersDataFile.self, from: data)
    }

    private func counter(_ id: String, in file: CountersDataFile) throws -> Counter {
        try XCTUnwrap(file.counters.first { $0.id == id }, id)
    }

    func testEveryCounterHasAllElevenReadings() throws {
        for counter in try load().counters {
            for number in CounterNumber.allCases {
                XCTAssertFalse(counter.readings(for: number).isEmpty, "\(counter.id) \(number.key)")
                XCTAssertFalse(counter.readings(for: number).contains(""), "\(counter.id) \(number.key)")
            }
        }
    }

    func testIdsAreUniqueAndRelatedResolve() throws {
        let file = try load()
        let ids = file.counters.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.count, 18)
        for counter in file.counters {
            for related in counter.related { XCTAssertTrue(ids.contains(related), "\(counter.id) → \(related)") }
        }
    }

    func testChangedKeysAreValid() throws {
        let keys = Set(CounterNumber.allCases.map(\.key))
        for counter in try load().counters {
            XCTAssertTrue(Set(counter.changed).isSubset(of: keys), counter.id)
        }
    }

    func testDistractorsAreWrongReadingsNeverAcceptedOnes() throws {
        let file = try load()
        XCTAssertEqual(try counter("hon", in: file).distractors(for: .n(3)), ["さんほん", "さんぽん", "さっぽん"])
        for counter in file.counters {
            for number in CounterNumber.allCases {
                let wrong = counter.distractors(for: number)
                XCTAssertLessThanOrEqual(wrong.count, 3, "\(counter.id) \(number.key)")
                XCTAssertTrue(Set(wrong).isDisjoint(with: counter.readings(for: number)), "\(counter.id) \(number.key)")
            }
        }
    }

    func testKnownReadings() throws {
        let file = try load()
        XCTAssertEqual(try counter("hon", in: file).readings(for: .n(3)).first, "さんぼん")
        XCTAssertEqual(try counter("nin", in: file).readings(for: .n(1)).first, "ひとり")
        XCTAssertEqual(try counter("ji", in: file).readings(for: .n(4)).first, "よじ")
        XCTAssertEqual(try counter("nichi-date", in: file).readings(for: .n(1)).first, "ついたち")
        XCTAssertEqual(try counter("nichi-days", in: file).readings(for: .n(1)).first, "いちにち")
    }

    func testGroupsAreUniqueResolveAndCoverEveryCounter() throws {
        let file = try load()
        let ids = Set(file.counters.map(\.id))
        let groupIDs = file.groups.map(\.id)
        XCTAssertEqual(Set(groupIDs).count, groupIDs.count)
        XCTAssertEqual(groupIDs.count, 13)
        var grouped = Set<String>()
        for group in file.groups {
            for member in group.members {
                XCTAssertTrue(ids.contains(member.counter), "\(group.id) → \(member.counter)")
                grouped.insert(member.counter)
            }
        }
        XCTAssertEqual(grouped, ids)
    }

    func testTheHomeSectionsCoverEveryCounterInTheChosenOrder() throws {
        let file = try load()
        let home = homeSections(file.sections, counters: file.counters)
        XCTAssertEqual(home.map(\.id), ["drinks", "people-animals", "things", "time-dates-age", "money-events"])
        XCTAssertEqual(home.map(\.rows.count), [3, 2, 6, 6, 3])
        XCTAssertEqual(Set(home.flatMap(\.rows).map(\.counter.id)), Set(file.counters.map(\.id)))
    }
}
