import XCTest
@testable import VerbKit

final class VerbPairQuestionTests: XCTestCase {
    private let forms = VerbForms(
        masuPos: "a", masuNeg: "a", masuPast: "a", masuPastNeg: "a", te: "a",
        shortPos: "a", shortNeg: "a", shortPast: "a", shortPastNeg: "a"
    )

    private func verb(_ dict: String, _ kanji: String?, jlpt: JLPTLevel? = .n5, pair: VerbPair?) -> Verb {
        Verb(type: .ru, label: "Ru-verb", dict: dict, kanji: kanji, meaning: "m", description: "d", jlpt: jlpt,
             forms: forms, examples: [], pair: pair)
    }

    private var hajimeru: Verb {
        verb("はじめる", "始める", pair: VerbPair(verb: "はじまる", transitivity: .transitive, jp: "会議を始める", en: "start the meeting"))
    }

    private func hajimaru(jlpt: JLPTLevel? = .n5) -> Verb {
        verb("はじまる", "始まる", jlpt: jlpt,
             pair: VerbPair(verb: "はじめる", transitivity: .intransitive, jp: "会議が始まる", en: "the meeting starts"))
    }

    func testThePhraseSplitsAtItsParticleAndVerb() throws {
        let parts = try XCTUnwrap(PairPhraseParts(verb: hajimeru, pair: try XCTUnwrap(hajimeru.pair)))
        XCTAssertEqual(parts, PairPhraseParts(head: "会議", particle: "を", verb: "始める"))
        let ireru = verb("いれる", "入れる", pair: VerbPair(verb: "はいる", transitivity: .transitive, jp: "箱に本を入れる", en: "e"))
        XCTAssertEqual(PairPhraseParts(verb: ireru, pair: try XCTUnwrap(ireru.pair))?.head, "箱に本")
        let kana = verb("つける", nil, pair: VerbPair(verb: "つく", transitivity: .transitive, jp: "電気をつける", en: "e"))
        XCTAssertEqual(PairPhraseParts(verb: kana, pair: try XCTUnwrap(kana.pair))?.verb, "つける")
    }

    func testAPhraseWithoutTheParticleBeforeTheVerbIsSkipped() {
        let odd = verb("あける", "開ける", pair: VerbPair(verb: "あく", transitivity: .transitive, jp: "ドアをそっと開ける", en: "e"))
        XCTAssertNil(PairPhraseParts(verb: odd, pair: odd.pair!))
    }

    func testEachHalfMakesAVerbAndAParticleQuestion() throws {
        let questions = buildVerbPairQuestions(verbs: [hajimeru, hajimaru()], count: .max)
        XCTAssertEqual(questions.count, 4)
        let verbQuestion = try XCTUnwrap(questions.first { $0.verbID == "はじまる" && $0.blank == .verb })
        XCTAssertEqual(verbQuestion.blanked, "会議が" + QuizQuestion.blank)
        XCTAssertEqual(verbQuestion.answer, "はじまる")
        XCTAssertEqual(Set(verbQuestion.choices), ["はじまる", "はじめる"])
        XCTAssertEqual(verbQuestion.choiceVerbs["はじめる"]?.kanji, "始める", "so the quiz can write it in its script")
        XCTAssertEqual(verbQuestion.partnerPhrase, "会議を始める")
        let particleQuestion = try XCTUnwrap(questions.first { $0.verbID == "はじめる" && $0.blank == .particle })
        XCTAssertEqual(particleQuestion.blanked, "会議" + QuizQuestion.blank + "始める")
        XCTAssertEqual(particleQuestion.answer, "を")
        XCTAssertEqual(Set(particleQuestion.choices), ["を", "が"])
        XCTAssertEqual(particleQuestion.choiceVerbs, [:])
    }

    func testBothHalvesMustBeVisible() {
        let onlyN5 = LevelSettings(hidden: [.n4, .n3, .n2, .n1])
        XCTAssertEqual(buildVerbPairQuestions(verbs: [hajimeru, hajimaru(jlpt: .n4)], levels: onlyN5, count: .max), [])
        XCTAssertEqual(buildVerbPairQuestions(verbs: [hajimeru], count: .max), [], "no partner, no questions")
        XCTAssertEqual(buildVerbPairQuestions(verbs: [hajimeru, hajimaru()], count: 3).count, 3)
        XCTAssertEqual(buildVerbPairQuestions(verbs: [hajimeru, hajimaru()], count: 0), [])
    }

    func testRealDataMakesFourQuestionsPerPair() throws {
        let questions = buildVerbPairQuestions(verbs: try RealVerbs.load(), count: .max)
        XCTAssertEqual(questions.count, 28, "14 halves, a verb and a particle question each")
        for question in questions {
            XCTAssertTrue(question.choices.contains(question.answer))
            XCTAssertEqual(Set(question.choices).count, 2, question.phrase)
            if question.blank == .particle {
                XCTAssertEqual(question.blanked.replacingOccurrences(of: QuizQuestion.blank, with: question.answer), question.phrase)
            } else {
                XCTAssertEqual(Set(question.choiceVerbs.keys), Set(question.choices), question.phrase)
                XCTAssertTrue(question.phrase.hasPrefix(question.before), question.phrase)
            }
        }
    }

    // MARK: The quiz

    func testAnswersAreRecordedAsVerbPairAttempts() throws {
        var attempts: [QuizAttempt] = []
        let questions = buildVerbPairQuestions(verbs: [hajimeru, hajimaru()], count: .max)
            .sorted { ($0.verbID, $0.blank.rawValue) < ($1.verbID, $1.blank.rawValue) }
        let model = VerbPairQuizModel(questions: questions, recorder: { attempts.append($0) })
        // はじまる/particle, はじまる/verb, はじめる/particle, はじめる/verb
        model.choose("を")
        XCTAssertEqual(model.answeredCorrectly, false)
        model.advance()
        model.choose("はじまる")
        model.advance()
        model.choose("を")
        model.advance()
        model.choose("はじまる")
        model.advance()
        XCTAssertTrue(model.finished)
        XCTAssertEqual(model.score, 2)
        XCTAssertEqual(attempts.map(\.kind), Array(repeating: .verbPair, count: 4))
        XCTAssertEqual(attempts.map(\.subject), ["はじまる", "はじまる", "はじめる", "はじめる"])
        XCTAssertEqual(attempts.map(\.formID), ["particle", "verb", "particle", "verb"])
        XCTAssertEqual(attempts[0].errorTag, .wrongParticle("を"))
        XCTAssertEqual(attempts[3].errorTag, .otherVerb("はじまる"))
        XCTAssertNil(attempts[1].errorTag)
        XCTAssertEqual(model.missedQuestions.map(\.verbID), ["はじまる", "はじめる"])
    }

    func testTheNewKindIsNotAVerbQuestion() {
        XCTAssertFalse(QuizQuestionKind.verbPair.isVerbQuestion)
        XCTAssertFalse(QuizQuestionKind.verbPair.isCounter)
    }
}
