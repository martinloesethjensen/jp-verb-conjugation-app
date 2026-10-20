import XCTest
@testable import VerbKit

final class RouteTests: XCTestCase {
    private func makeVerb(dict: String) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "m", description: "d",
            forms: VerbForms(
                masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"
            ),
            examples: []
        )
    }

    func testResolvesVerbByDictionaryForm() {
        let taberu = makeVerb(dict: "たべる")
        let target = Route.verb("たべる").resolve(verbs: [makeVerb(dict: "のむ"), taberu], grammarPoints: [])
        XCTAssertEqual(target, .verb(taberu))
    }

    func testResolvesGrammarByID() {
        let points = GrammarFixture.points
        let target = Route.grammar(GrammarPoint.nDesuID).resolve(verbs: [], grammarPoints: points)
        XCTAssertEqual(target, .grammar(points[0]))
    }

    func testUnknownTargetsResolveToNil() {
        XCTAssertNil(Route.verb("ない").resolve(verbs: [makeVerb(dict: "たべる")], grammarPoints: GrammarFixture.points))
        XCTAssertNil(Route.grammar("nope").resolve(verbs: [], grammarPoints: GrammarFixture.points))
    }

    func testGrammarLinkIsHiddenUntilGrammarHasSynced() {
        XCTAssertNil(Route.grammar(GrammarPoint.nDesuID).resolve(verbs: [], grammarPoints: []))
    }

    private var counters: [Counter] {
        [Counter(id: "kai-floor", counter: "階", reading: "かい", meaning: "floors", sound: "k", symbol: "building.2",
                 readings: ["1": ["いっかい"]])]
    }

    private var groups: [CounterGroup] {
        [CounterGroup(id: "times-floors", title: "Times & floors", symbol: "arrow.clockwise", summary: "s",
                      members: [CounterGroupMember(counter: "kai-floor")])]
    }

    func testResolvesCountersAndGroupsByID() {
        XCTAssertEqual(
            Route.counter("kai-floor").resolve(verbs: [], grammarPoints: [], counters: counters, groups: groups),
            .counter(counters[0])
        )
        XCTAssertEqual(
            Route.counterGroup("times-floors").resolve(verbs: [], grammarPoints: [], counters: counters, groups: groups),
            .counterGroup(groups[0])
        )
    }

    func testUnknownCounterTargetsResolveToNil() {
        XCTAssertNil(Route.counter("nope").resolve(verbs: [], grammarPoints: [], counters: counters, groups: groups))
        XCTAssertNil(Route.counterGroup("nope").resolve(verbs: [], grammarPoints: [], counters: counters, groups: groups))
        XCTAssertNil(Route.counter("kai-floor").resolve(verbs: [], grammarPoints: []))   // not synced yet
    }

    func testRoutesOfDifferentKindsWithTheSameIDAreDistinct() {
        XCTAssertNotEqual(Route.counter("x"), Route.counterGroup("x"))
        XCTAssertNotEqual(Route.verb("x"), Route.grammar("x"))
    }
}
