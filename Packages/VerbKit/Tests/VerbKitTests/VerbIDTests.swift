import XCTest
import SwiftData
@testable import VerbKit

/// Two verbs can be spelled the same in kana (着る and 切る are both きる). The older one keeps the
/// bare `きる`; the newer carries an explicit `きる:切る`. Everything that stores or links a verb
/// uses `Verb.id`, so the two stay apart. See docs/superpowers/specs/2026-10-17-verb-id-scheme-design.md.
@MainActor
final class VerbIDTests: XCTestCase {
    private func makeVerb(dict: String, kanji: String, masuPos: String, id: String? = nil) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: kanji, meaning: "to \(kanji)", description: "d",
            forms: VerbForms(
                masuPos: masuPos, masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"
            ),
            examples: [],
            id: id
        )
    }

    private var kiru: Verb { makeVerb(dict: "きる", kanji: "着る", masuPos: "きます") }
    private var kiruCut: Verb { makeVerb(dict: "きる", kanji: "切る", masuPos: "きります", id: "きる:切る") }

    // MARK: The id

    func testIDIsTheDictionaryFormUnlessThereIsAnExplicitOne() {
        XCTAssertEqual(kiru.id, "きる")
        XCTAssertNil(kiru.explicitID)
        XCTAssertEqual(kiruCut.id, "きる:切る")
        XCTAssertEqual(kiruCut.dict, "きる")
    }

    func testEveryShippedVerbHasAUniqueID() throws {
        let verbs = try RealVerbs.load()
        XCTAssertEqual(Set(verbs.map(\.id)).count, verbs.count)
        for verb in verbs {
            XCTAssertEqual(verb.id, verb.explicitID ?? verb.dict, verb.dict)
            // An explicit id is `dict:` followed by something, so it can never equal another verb's bare dict.
            if let explicitID = verb.explicitID {
                XCTAssertTrue(explicitID.hasPrefix(verb.dict + ":"), explicitID)
            }
        }
    }

    func testBothKirusAreInTheShippedDataAsSeparateVerbs() throws {
        let verbs = try RealVerbs.load().filter { $0.dict == "きる" }
        XCTAssertEqual(verbs.map(\.id), ["きる", "きる:切る"])
        XCTAssertEqual(verbs.map(\.kanji), ["着る", "切る"])
        XCTAssertEqual(verbs.map(\.type), [.ru, .u])
        // Same kana, different conjugation: the て-forms tell them apart.
        XCTAssertEqual(verbs.map(\.forms.te), ["きて", "きって"])
        XCTAssertEqual(verbs.map(\.meaning), ["to wear (on the upper body)", "to cut"])
    }

    // MARK: JSON

    func testTheIDIsLeftOutOfTheJSONWhenThereIsNone() throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(kiru)) as? [String: Any]
        )
        XCTAssertNil(object["id"])
        XCTAssertEqual(object["dict"] as? String, "きる")
    }

    func testAnExplicitIDRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(kiruCut)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "きる:切る")
        XCTAssertEqual(try JSONDecoder().decode(Verb.self, from: data), kiruCut)
    }

    // MARK: Storage

    func testTwoHomophonesAreBothStoredAndComeBackApart() throws {
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory()))
        try persisting.replaceAllVerbs(with: [kiru, kiruCut])

        let loaded = try persisting.loadAllVerbs()
        XCTAssertEqual(loaded, [kiru, kiruCut])
        XCTAssertEqual(loaded.map(\.id), ["きる", "きる:切る"])
        XCTAssertEqual(loaded.map(\.dict), ["きる", "きる"])
    }

    func testTheUniqueColumnHoldsTheIDAndKanaHoldsTheRealDictionaryForm() {
        let cut = VerbEntity(kiruCut)
        XCTAssertEqual(cut.dict, "きる:切る")
        XCTAssertEqual(cut.kana, "きる")

        let plain = VerbEntity(kiru)
        XCTAssertEqual(plain.dict, "きる")
        XCTAssertNil(plain.kana)
    }

    func testARowSavedBeforeExplicitIDsExistedStillLoadsAsItself() throws {
        // Such a row has no `kana`, and its `dict` column is the dictionary form.
        let legacy = VerbEntity(kiru)
        legacy.kana = nil
        let verb = try XCTUnwrap(legacy.toVerb())
        XCTAssertEqual(verb.dict, "きる")
        XCTAssertEqual(verb.id, "きる")
        XCTAssertNil(verb.explicitID)
    }

    // MARK: Everything that links or stores a verb

    func testRoutesFindEachHomophoneAndSurviveAURL() throws {
        let verbs = [kiru, kiruCut]
        XCTAssertEqual(Route.verb("きる").resolve(verbs: verbs, grammarPoints: []), .verb(kiru))
        XCTAssertEqual(Route.verb("きる:切る").resolve(verbs: verbs, grammarPoints: []), .verb(kiruCut))

        let url = Route.verb(kiruCut.id).url
        XCTAssertEqual(Route(url: url), .verb("きる:切る"))
    }

    func testFavouritesKeepHomophonesApart() {
        var favourites = FavouriteVerbs()
        favourites.toggle(kiruCut)
        XCTAssertTrue(favourites.contains(kiruCut))
        XCTAssertFalse(favourites.contains(kiru))
        XCTAssertEqual(FavouriteVerbs(rawValue: favourites.rawValue).ids, ["きる:切る"])
    }

    func testQuizHistoryRecordsTheID() {
        let form = QuizForm.all.first { $0.id == "masu_pos" }!
        let question = QuizQuestion(
            verb: kiruCut, form: form, kind: .conjugate, formString: "きります", correct: "きります",
            choices: ["きります", "きます"]
        )
        var recorded: [QuizAttempt] = []
        let viewModel = QuizViewModel(questions: [question], recorder: { recorded.append($0) })
        viewModel.choose("きります")

        XCTAssertEqual(recorded.map(\.verb), ["きる:切る"])
        // The results screen still shows the kana.
        XCTAssertEqual(viewModel.results.map(\.verb), ["きる"])
    }

    func testTheWordBridgeKeepsTheID() {
        XCTAssertEqual(Word(kiru).id, "verb:きる")
        XCTAssertEqual(Word(kiruCut).id, "verb:きる:切る")
        XCTAssertEqual(Word(kiruCut).dict, "きる")
    }

    func testAWordWithAnExplicitIDRoundTripsThroughJSON() throws {
        let word = Word(kiruCut)
        let data = try JSONEncoder().encode(word)
        let decoded = try JSONDecoder().decode(Word.self, from: data)
        XCTAssertEqual(decoded.explicitID, "きる:切る")
        XCTAssertEqual(decoded.id, word.id)
    }

    func testAStoredWordKeepsItsExplicitID() throws {
        let word = Word(wordClass: .noun, dict: "はし", kanji: "橋", meaning: "bridge", description: "",
                        forms: Conjugations(), id: "はし:橋")
        let stored = StoredWord(word)
        XCTAssertEqual(stored.word.id, "noun:はし:橋")
        let decoded = try JSONDecoder().decode(StoredWord.self, from: JSONEncoder().encode(stored))
        XCTAssertEqual(decoded, stored)
    }
}
