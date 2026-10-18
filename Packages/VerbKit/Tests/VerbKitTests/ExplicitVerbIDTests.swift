import XCTest
import SwiftData
@testable import VerbKit

/// 着る and 切る are both きる. The older verb keeps the bare id; the newer one carries `きる:切る`.
@MainActor
final class ExplicitVerbIDTests: XCTestCase {
    private func makeVerb(dict: String, kanji: String?, id: String? = nil, masu: String = "x") -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: kanji, meaning: "m", description: "d",
            forms: VerbForms(
                masuPos: masu, masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"
            ),
            examples: [], id: id
        )
    }

    private var kiru: Verb { makeVerb(dict: "きる", kanji: "着る") }
    private var kiruCut: Verb { makeVerb(dict: "きる", kanji: "切る", id: "きる:切る") }

    func testTheIDIsTheDictionaryFormUnlessAnExplicitOneIsSet() {
        XCTAssertEqual(kiru.id, "きる")
        XCTAssertEqual(kiruCut.id, "きる:切る")
        XCTAssertNotEqual(kiru, kiruCut)
    }

    func testAnExplicitIDRoundTripsThroughJSONAndAnAbsentOneStaysAbsent() throws {
        let data = try JSONEncoder().encode([kiru, kiruCut])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertNil(json[0]["id"])
        XCTAssertEqual(json[1]["id"] as? String, "きる:切る")
        let back = try JSONDecoder().decode([Verb].self, from: data)
        XCTAssertEqual(back.map(\.id), ["きる", "きる:切る"])
    }

    func testTheIDRoundTripsThroughAVerbTableURL() throws {
        let route = Route.verb(kiruCut.id)
        XCTAssertEqual(Route(url: route.url), route)
    }

    func testRoutesResolveEachHomophoneSeparately() {
        let verbs = [kiru, kiruCut]
        XCTAssertEqual(Route.verb("きる").resolve(verbs: verbs, grammarPoints: []), .verb(kiru))
        XCTAssertEqual(Route.verb("きる:切る").resolve(verbs: verbs, grammarPoints: []), .verb(kiruCut))
    }

    func testFavouritesKeepTheHomophonesApart() {
        var favourites = FavouriteVerbs()
        favourites.toggle(kiruCut)
        XCTAssertTrue(favourites.contains(kiruCut))
        XCTAssertFalse(favourites.contains(kiru))
        XCTAssertEqual(favourites.filter([kiru, kiruCut]), [kiruCut])
    }

    func testTheCacheStoresBothHomophonesAndTheirIDs() throws {
        let container = try VerbModelContainer.makeInMemory()
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(container))
        try persisting.replaceAllVerbs(with: [kiru, kiruCut])
        XCTAssertEqual(try persisting.loadAllVerbs().map(\.id), ["きる", "きる:切る"])
    }

    func testAWordTakesItsIDFromTheVerbAndKeepsItInJSON() throws {
        let word = Word(kiruCut)
        XCTAssertEqual(word.id, "verb:きる:切る")
        XCTAssertEqual(Word(kiru).id, "verb:きる")
        let back = try JSONDecoder().decode(Word.self, from: JSONEncoder().encode(word))
        XCTAssertEqual(back.id, word.id)
    }

    func testQuizHistoryRecordsTheIDSoHomophonesKeepSeparateHistory() throws {
        var attempts: [QuizAttempt] = []
        let form = try XCTUnwrap(QuizForm.all.first { $0.id == "masu_pos" })
        let questions = [kiru, kiruCut].map {
            QuizQuestion(verb: $0, form: form, kind: .conjugate, formString: "x", correct: "x", choices: ["x", "y"])
        }
        let vm = QuizViewModel(questions: questions, recorder: { attempts.append($0) })
        vm.choose("x")
        vm.advance()
        vm.choose("x")
        XCTAssertEqual(attempts.map(\.verb), ["きる", "きる:切る"])
        // The results screen shows the kana, not the id.
        XCTAssertEqual(vm.results.map(\.verb), ["きる", "きる"])
    }

    func testAHomophoneIsNotDroppedFromTheDistractors() throws {
        // Every form of the first verb is "A", so its only possible distractors are the other
        // verb's forms. Comparing by dict would drop the homophone and leave no question.
        func verb(_ strings: [String], id: String?) -> Verb {
            Verb(
                type: .ru, label: "Ru-verb", dict: "きる", kanji: nil, meaning: "m", description: "d",
                forms: VerbForms(
                    masuPos: strings[0], masuNeg: strings[1], masuPast: strings[2], masuPastNeg: strings[3],
                    te: strings[4], shortPos: strings[5], shortNeg: strings[6], shortPast: strings[7], shortPastNeg: strings[8]
                ),
                examples: [], id: id
            )
        }
        let same = verb(Array(repeating: "A", count: 9), id: nil)
        let other = verb(["B", "C", "D", "E", "F", "G", "H", "I", "J"], id: "きる:切る")
        let form = try XCTUnwrap(QuizForm.all.first { $0.id == "masu_pos" })
        let questions = buildQuestions(pairs: [(same, form)], among: [same, other], count: 1, kinds: [.conjugate])
        XCTAssertEqual(questions.count, 1)
        XCTAssertTrue(Set(questions[0].choices).isSuperset(of: ["A"]))
        XCTAssertGreaterThan(questions[0].choices.count, 1)
    }
}
