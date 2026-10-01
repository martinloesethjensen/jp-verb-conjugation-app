import XCTest
@testable import VerbKit

final class VerbPickTests: XCTestCase {
    private func verb(_ dict: String) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "m", description: "d",
            forms: VerbForms(
                masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"
            ),
            examples: []
        )
    }

    private var verbs: [Verb] { ["a", "b", "c"].map(verb) }

    private func date(_ day: Int) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = day; components.hour = 15
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private let calendar = Calendar(identifier: .gregorian)

    func testSameDayGivesSameVerb() {
        var morning = DateComponents(); morning.year = 2026; morning.month = 10; morning.day = 5; morning.hour = 1
        var night = morning; night.hour = 23
        let a = VerbPick.verbOfTheDay(verbs: verbs, on: calendar.date(from: morning)!, calendar: calendar)
        let b = VerbPick.verbOfTheDay(verbs: verbs, on: calendar.date(from: night)!, calendar: calendar)
        XCTAssertEqual(a, b)
    }

    func testNextDayGivesNextVerbAndWraps() throws {
        let first = try XCTUnwrap(VerbPick.verbOfTheDay(verbs: verbs, on: date(1), calendar: calendar))
        let second = try XCTUnwrap(VerbPick.verbOfTheDay(verbs: verbs, on: date(2), calendar: calendar))
        let third = try XCTUnwrap(VerbPick.verbOfTheDay(verbs: verbs, on: date(3), calendar: calendar))
        let fourth = try XCTUnwrap(VerbPick.verbOfTheDay(verbs: verbs, on: date(4), calendar: calendar))
        XCTAssertEqual(Set([first.dict, second.dict, third.dict]).count, 3)
        XCTAssertEqual(fourth, first)
    }

    func testEmptyListGivesNil() {
        XCTAssertNil(VerbPick.verbOfTheDay(verbs: [], on: date(1), calendar: calendar))
        var generator = SystemRandomNumberGenerator()
        XCTAssertNil(VerbPick.randomVerb(verbs: [], using: &generator))
    }

    func testSingleVerbIsAlwaysChosen() {
        let only = [verb("x")]
        XCTAssertEqual(VerbPick.verbOfTheDay(verbs: only, on: date(9), calendar: calendar), only[0])
        var generator = SystemRandomNumberGenerator()
        XCTAssertEqual(VerbPick.randomVerb(verbs: only, using: &generator), only[0])
    }

    func testRandomVerbComesFromTheList() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let picked = VerbPick.randomVerb(verbs: verbs, using: &generator)
            XCTAssertNotNil(picked.flatMap { verbs.contains($0) ? $0 : nil })
        }
    }
}
