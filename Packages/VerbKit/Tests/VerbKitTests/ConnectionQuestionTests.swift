import XCTest
@testable import VerbKit

final class ConnectionQuestionTests: XCTestCase {
    private func word(_ cls: WordClass, _ dict: String, _ forms: [FormID: String]) -> Word {
        Word(wordClass: cls, dict: dict, meaning: "m", description: "", forms: Conjugations(forms))
    }

    private var shizuka: Word {
        word(.naAdjective, "しずか", [
            "short_pos": "しずかだ", "short_neg": "しずかじゃない", "short_past": "しずかだった",
            "short_past_neg": "しずかじゃなかった", "stem": "しずか", "te": "しずかで",
        ])
    }

    private var takai: Word {
        word(.iAdjective, "たかい", [
            "short_pos": "たかい", "short_neg": "たかくない", "short_past": "たかかった",
            "short_past_neg": "たかくなかった", "stem": "たか", "te": "たかくて",
        ])
    }

    private func verb(_ dict: String, _ stem: String, te: String, neg: String, past: String, pastNeg: String) -> Verb {
        let forms = VerbForms(
            masuPos: stem + "ます", masuNeg: stem + "ません", masuPast: stem + "ました", masuPastNeg: stem + "ませんでした",
            te: te, shortPos: dict, shortNeg: neg, shortPast: past, shortPastNeg: pastNeg
        )
        return Verb(type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "m",
                    description: "", forms: forms, examples: [])
    }

    private var taberu: Verb { verb("たべる", "たべ", te: "たべて", neg: "たべない", past: "たべた", pastNeg: "たべなかった") }
    private var neru: Verb { verb("ねる", "ね", te: "ねて", neg: "ねない", past: "ねた", pastNeg: "ねなかった") }

    private func point(_ id: String, _ rules: [AttachmentRule]) -> GrammarPoint {
        GrammarPoint(id: id, title: id, summary: "", usages: [], attachment: rules,
                     conjugations: [], pitfalls: [], related: [])
    }

    private let allPlain: [GrammarSlot] = [.plain, .plainNeg, .plainPast, .plainPastNeg]

    private var node: GrammarPoint {
        point("node", [
            AttachmentRule(wordClass: .naAdjective, pattern: "p", example: "e", slots: allPlain, daToNa: true, then: "ので"),
            AttachmentRule(wordClass: .iAdjective, pattern: "p", example: "e", slots: allPlain, then: "ので"),
        ])
    }

    private var hou: GrammarPoint {
        point("hou-ga-ii", [
            AttachmentRule(wordClass: .verb, pattern: "p", example: "e", slots: [.plainPast], then: "ほうがいいです"),
            AttachmentRule(wordClass: .verb, pattern: "p", example: "e", slots: [.plainNeg], then: "ほうがいいです"),
        ])
    }

    func testTheCueNamesOnlyWhatTellsTheFormsApart() {
        let four = Set(allPlain)
        XCTAssertEqual(ConnectionCue(for: .plain, among: four).label, "positive · present")
        XCTAssertEqual(ConnectionCue(for: .plainPastNeg, among: four).label, "negative · past")
        XCTAssertEqual(ConnectionCue(for: .plainPast, among: [.plainPast, .plainNeg]).label, "positive",
                       "ほうがいい: which tense to use is the lesson, so the cue leaves it out")
        XCTAssertNil(ConnectionCue(for: .stem, among: [.stem]).label)
        XCTAssertNil(ConnectionCue(for: .plain, among: [.plain]).label)
    }

    func testEachSlotOfAPatternIsAskedWithItsAnswerAmongTheChoices() throws {
        let questions = buildConnectionQuestions(points: [node], verbs: [], words: [shizuka], count: 4)
        XCTAssertEqual(Set(questions.map(\.slot)), Set(allPlain))
        let wrongPool: Set<String> = [
            "しずかなので", "しずかだので", "しずかじゃないので", "しずかだったので",
            "しずかじゃなかったので", "しずかので", "しずかでので",
        ]
        for question in questions {
            XCTAssertTrue(question.choices.contains(question.correct))
            XCTAssertEqual(Set(question.choices).count, question.choices.count, "no duplicate choices")
            XCTAssertTrue((2...4).contains(question.choices.count))
            XCTAssertTrue(Set(question.choices).isSubset(of: wrongPool), "\(question.choices)")
        }
        let plain = try XCTUnwrap(questions.first { $0.slot == .plain })
        XCTAssertEqual(plain.correct, "しずかなので")
        XCTAssertEqual(plain.cue.label, "positive · present")
        XCTAssertEqual(plain.explanation, "な-adjectives take the plain form with だ → な before ので: しずかなので")
        XCTAssertEqual(plain.attemptFormID, "connect:node:plain")
        XCTAssertEqual(plain.grammarTitle, "node")
        let past = try XCTUnwrap(questions.first { $0.slot == .plainPast })
        XCTAssertEqual(past.correct, "しずかだったので", "the な switch touches only the plain slot")
    }

    func testQuestionsCarryTheStableKeySoHomophonesStayApart() {
        let kiru = verb("きる", "き", te: "きて", neg: "きない", past: "きた", pastNeg: "きなかった")
        var cut = verb("きる", "きり", te: "きって", neg: "きらない", past: "きった", pastNeg: "きらなかった")
        cut.explicitID = "きる:切る"
        let questions = buildConnectionQuestions(points: [hou], verbs: [kiru, cut], words: [], count: 10)
        XCTAssertEqual(Set(questions.map(\.wordID)), ["きる", "きる:切る"])
        XCTAssertTrue(questions.allSatisfy { $0.word == "きる" })

        XCTAssertEqual(kiru.stableKey, "きる")
        XCTAssertEqual(cut.stableKey, "きる:切る")
        XCTAssertEqual(Word(wordClass: .noun, dict: "はし", kanji: "橋", meaning: "m", description: "",
                            forms: Conjugations(), id: "はし:橋").stableKey, "はし:橋")
        XCTAssertEqual(shizuka.stableKey, "しずか")
    }

    func testAPatternWithFewSlotsFillsTheQuizWithOtherWordsButNeverRepeatsAnAnswer() throws {
        let questions = buildConnectionQuestions(points: [hou], verbs: [taberu, neru], words: [], count: 10)
        XCTAssertEqual(Set(questions.map(\.correct)),
                       ["たべたほうがいいです", "たべないほうがいいです", "ねたほうがいいです", "ねないほうがいいです"])
        XCTAssertEqual(questions.count, 4)
        let past = try XCTUnwrap(questions.first { $0.correct == "たべたほうがいいです" })
        XCTAssertEqual(past.cue.label, "positive")
        XCTAssertEqual(past.explanation, "Verbs take the plain past (た) form before ほうがいいです: たべたほうがいいです")
        XCTAssertTrue(Set(past.choices).isSubset(of: [
            "たべたほうがいいです", "たべないほうがいいです",
            "たべなかったほうがいいです", "たべてほうがいいです", "たべほうがいいです",
        ]), "\(past.choices)")
        XCTAssertFalse(past.choices.contains("たべるほうがいいです"),
                       "the dictionary form is fine as a general statement, so it is never marked wrong")
        let negative = try XCTUnwrap(questions.first { $0.correct == "たべないほうがいいです" })
        XCTAssertTrue(Set(negative.choices).isSubset(of: [
            "たべないほうがいいです", "たべたほうがいいです", "たべるほうがいいです",
            "たべなかったほうがいいです", "たべてほうがいいです", "たべほうがいいです",
        ]), "\(negative.choices)")
    }

    func testAStemPatternHasNoCueAndUsesTheWordsOtherBlocksAsTraps() throws {
        let sugiru = point("sugiru", [
            AttachmentRule(wordClass: .iAdjective, pattern: "p", example: "e", slots: [.stem], then: "すぎる"),
        ])
        let question = try XCTUnwrap(buildConnectionQuestions(points: [sugiru], verbs: [], words: [takai], count: 1).first)
        XCTAssertEqual(question.correct, "たかすぎる")
        XCTAssertNil(question.cue.label)
        XCTAssertEqual(question.choices.count, 4)
        XCTAssertTrue(Set(question.choices).isSubset(of: [
            "たかすぎる", "たかいすぎる", "たかくないすぎる", "たかかったすぎる", "たかくなかったすぎる", "たかくてすぎる",
        ]))
        XCTAssertEqual(question.explanation, "い-adjectives take the stem before すぎる: たかすぎる")
    }

    func testNothingIsAskedWithoutAnEndingOrWordsOfTheRulesClass() {
        let tagOnly = point("teiru", [AttachmentRule(wordClass: .verb, pattern: "p", example: "e", slots: [.te])])
        XCTAssertFalse(tagOnly.hasConnections)
        XCTAssertTrue(node.hasConnections)
        XCTAssertTrue(buildConnectionQuestions(points: [tagOnly], verbs: [taberu], words: [], count: 5).isEmpty)
        XCTAssertTrue(buildConnectionQuestions(points: [node], verbs: [taberu], words: [], count: 5).isEmpty,
                      "no adjectives to ask about")
        XCTAssertTrue(buildConnectionQuestions(points: [node], verbs: [], words: [takai], count: 0).isEmpty)
    }
}
