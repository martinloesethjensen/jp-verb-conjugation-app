import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class JLPTLevelTests: XCTestCase {
    func testRawValuesRoundTripThroughJSON() throws {
        for level in JLPTLevel.allCases {
            let data = try JSONEncoder().encode([level])
            XCTAssertEqual(String(data: data, encoding: .utf8), "[\"\(level.rawValue)\"]")
            XCTAssertEqual(try JSONDecoder().decode([JLPTLevel].self, from: data), [level])
        }
    }

    func testOrderingPutsN5First() {
        XCTAssertTrue(JLPTLevel.n5 < .n4)
        XCTAssertTrue(JLPTLevel.n2 < .n1)
        XCTAssertFalse(JLPTLevel.n1 < .n5)
        XCTAssertEqual(JLPTLevel.allCases, [.n5, .n4, .n3, .n2, .n1])
        XCTAssertEqual(JLPTLevel.allCases.sorted(), JLPTLevel.allCases)
    }

    private func verbJSON(jlpt: String?) -> String {
        let key = jlpt.map { "\"jlpt\": \"\($0)\"," } ?? ""
        return """
        {
          "type": "ru", "label": "Ru-verb", "dict": "たべる", "kanji": "食べる",
          "meaning": "to eat", "description": "d", \(key)
          "forms": {
            "masu_pos": "a", "masu_neg": "b", "masu_past": "c", "masu_past_neg": "d",
            "te": "e", "short_pos": "f", "short_neg": "g", "short_past": "h",
            "short_past_neg": "i"
          },
          "examples": []
        }
        """
    }

    func testVerbDecodesJLPTWhenPresentAndNilWhenMissing() throws {
        let with = try JSONDecoder().decode(Verb.self, from: Data(verbJSON(jlpt: "N4").utf8))
        XCTAssertEqual(with.jlpt, .n4)
        let without = try JSONDecoder().decode(Verb.self, from: Data(verbJSON(jlpt: nil).utf8))
        XCTAssertNil(without.jlpt)
    }

    private func grammarJSON(jlpt: String?) -> String {
        let key = jlpt.map { "\"jlpt\": \"\($0)\"," } ?? ""
        return """
        {
          "id": "x", "title": "t", "summary": "s", \(key)
          "usages": [], "attachment": [], "conjugations": [], "pitfalls": [], "related": []
        }
        """
    }

    func testGrammarPointDecodesJLPTWhenPresentAndNilWhenMissing() throws {
        let with = try JSONDecoder().decode(GrammarPoint.self, from: Data(grammarJSON(jlpt: "N3").utf8))
        XCTAssertEqual(with.jlpt, .n3)
        let without = try JSONDecoder().decode(GrammarPoint.self, from: Data(grammarJSON(jlpt: nil).utf8))
        XCTAssertNil(without.jlpt)
    }

    private func makeVerb(jlpt: JLPTLevel?) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: "たべる", kanji: nil,
            meaning: "m", description: "d", jlpt: jlpt,
            forms: VerbForms(
                masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"
            ),
            examples: []
        )
    }

    func testVerbEntityRoundTripKeepsJLPT() throws {
        let container = try VerbModelContainer.makeInMemory()
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(container))
        try persisting.replaceAllVerbs(with: [makeVerb(jlpt: .n4)])
        XCTAssertEqual(try persisting.loadAllVerbs().first?.jlpt, .n4)
        try persisting.replaceAllVerbs(with: [makeVerb(jlpt: nil)])
        XCTAssertNil(try persisting.loadAllVerbs().first?.jlpt)
    }

    func testVerbEntityWithUnknownJLPTRawValueLoadsAsNil() throws {
        let entity = VerbEntity(makeVerb(jlpt: .n3))
        entity.jlpt = "N0"
        XCTAssertNil(entity.toVerb()?.jlpt)
    }
}
