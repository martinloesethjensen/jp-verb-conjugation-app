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

    func testRoutesOfDifferentKindsWithTheSameIDAreDistinct() {
        XCTAssertNotEqual(Route.verb("x"), Route.grammar("x"))
    }
}
