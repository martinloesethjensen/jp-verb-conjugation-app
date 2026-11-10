import XCTest
@testable import VerbKit

final class QuizScriptTests: XCTestCase {
    private func verb(_ dict: String, kanji: String?, masuPos: String) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: kanji, meaning: "m", description: "d",
            forms: VerbForms(masuPos: masuPos, masuNeg: "x", masuPast: "y", masuPastNeg: "z", te: "t", shortPos: "s", shortNeg: "sn", shortPast: "sp", shortPastNeg: "spn"),
            examples: []
        )
    }

    private var taberu: Verb { verb("たべる", kanji: "食べる", masuPos: "たべます") }
    private var suru: Verb { verb("する", kanji: nil, masuPos: "します") }
    private let masuPos = QuizForm.all.first { $0.id == "masu_pos" }!

    func testKanaKeepsTheQuizAsItWas() {
        XCTAssertEqual(QuizScript.kana.units(for: "たべました", of: taberu), [TextUnit(text: "たべました")])
        XCTAssertFalse(QuizScript.kana.usesKanji)
    }

    func testKanjiWithFuriganaSpellsTheStemWithItsReading() {
        XCTAssertEqual(
            QuizScript.kanjiWithFurigana.units(for: "たべました", of: taberu),
            [TextUnit(text: "食", reading: "た"), TextUnit(text: "べました")]
        )
    }

    func testKanjiOnlyHidesTheReadingUntilRevealed() {
        XCTAssertEqual(
            QuizScript.kanjiOnly.units(for: "たべました", of: taberu),
            [TextUnit(text: "食"), TextUnit(text: "べました")]
        )
        XCTAssertEqual(
            QuizScript.kanjiOnly.units(for: "たべました", of: taberu, revealed: true),
            [TextUnit(text: "食", reading: "た"), TextUnit(text: "べました")]
        )
        XCTAssertEqual(QuizScript.kanjiOnly.text(for: "たべました", of: taberu), "食べました")
    }

    func testAVerbWithoutKanjiStaysInKanaInEveryScript() {
        for script in QuizScript.allCases {
            XCTAssertEqual(script.units(for: "します", of: suru), [TextUnit(text: "します")], "\(script)")
        }
    }

    func testAnUnknownOrMissingStoredValueIsKana() {
        XCTAssertEqual(QuizScript(storedValue: ""), .kana)
        XCTAssertEqual(QuizScript(storedValue: "nonsense"), .kana)
        XCTAssertEqual(QuizScript(storedValue: "kanjiOnly"), .kanjiOnly)
    }

    // MARK: whose form a choice is

    func testAnOtherVerbDistractorIsSpelledWithThatVerbsKanji() throws {
        let nomu = verb("のむ", kanji: "飲む", masuPos: "のみます")
        let question = QuizQuestion(
            verb: taberu, form: masuPos, kind: .conjugate, formString: "たべます", correct: "たべます",
            choices: ["たべます", "のみます"], errors: ["のみます": .otherVerb("のむ")],
            choiceVerbs: ["のみます": nomu]
        )
        XCTAssertEqual(question.verb(of: "のみます"), nomu)
        XCTAssertEqual(question.verb(of: "たべます"), taberu)
        XCTAssertEqual(QuizScript.kanjiOnly.text(for: "のみます", of: question.verb(of: "のみます")), "飲みます")
    }

    func testTheGeneratorRecordsWhichVerbAnOtherVerbDistractorBelongsTo() throws {
        let all = try RealVerbs.load()
        let taberu = try XCTUnwrap(all.first { $0.dict == "たべる" })
        // Every other form collides, so the only distractor is another verb's form.
        let lone = Verb(
            type: .ru, label: "Ru-verb", dict: "lone", kanji: nil, meaning: "m", description: "d",
            forms: VerbForms(masuPos: "uniq", masuNeg: "dup", masuPast: "dup", masuPastNeg: "dup", te: "dup", shortPos: "dup", shortNeg: "dup", shortPast: "dup", shortPastNeg: "dup"),
            examples: []
        )
        let question = try XCTUnwrap(buildQuestions(
            pairs: [(lone, masuPos)], among: [lone, taberu], count: 1, kinds: [.conjugate]
        ).first)
        let theirs = try XCTUnwrap(masuPos.value(in: taberu.forms))
        XCTAssertEqual(question.verb(of: theirs), taberu)
        XCTAssertEqual(question.verb(of: "uniq"), lone)
        XCTAssertEqual(Set(question.choiceVerbs.keys), [theirs])
    }

    func testASavedQuizKeepsWhichVerbEachChoiceBelongsTo() throws {
        let nomu = verb("のむ", kanji: "飲む", masuPos: "のみます")
        let question = QuizQuestion(
            verb: taberu, form: masuPos, kind: .conjugate, formString: "たべます", correct: "たべます",
            choices: ["たべます", "のみます"], choiceVerbs: ["のみます": nomu]
        )
        let saved = QuizSession(topic: .weakSpots, questions: [question], progress: QuizProgressState(), savedAt: Date(timeIntervalSince1970: 5))
        let decoded = try JSONDecoder().decode(QuizSession.self, from: JSONEncoder().encode(saved))
        let restored = try XCTUnwrap(decoded.restore(verbs: [taberu, nomu]))
        XCTAssertEqual(restored.questions.first?.verb(of: "のみます"), nomu)
        // A verb that has gone since only loses its spelling: the quiz still resumes, in kana.
        let without = try XCTUnwrap(decoded.restore(verbs: [taberu]))
        XCTAssertEqual(without.questions.first?.verb(of: "のみます"), taberu)
    }

    func testAQuizWithoutOtherVerbChoicesSavesAsBefore() throws {
        let question = QuizQuestion(
            verb: taberu, form: masuPos, kind: .conjugate, formString: "たべます", correct: "たべます",
            choices: ["たべます", "たべない"]
        )
        let saved = QuizSession(topic: .weakSpots, questions: [question], progress: QuizProgressState(), savedAt: Date(timeIntervalSince1970: 5))
        let data = try JSONEncoder().encode(saved)
        // The same shape an older build wrote and reads, so no version bump is needed.
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("choiceVerbs"))
        XCTAssertNotNil(try JSONDecoder().decode(QuizSession.self, from: data).restore(verbs: [taberu]))
    }
}
