import XCTest
@testable import VerbKit

final class ParticleQuestionTests: XCTestCase {
    private func point(
        _ id: String = "teiru", jlpt: JLPTLevel? = .n5, examples: [GrammarExample], pitfalls: [GrammarExample] = [],
        contrasts: [GrammarExample] = []
    ) -> GrammarPoint {
        GrammarPoint(
            id: id, title: "Title \(id)", summary: "s", jlpt: jlpt,
            usages: [GrammarUsage(heading: "h", explanation: "e", examples: examples)],
            attachment: [], conjugations: [],
            pitfalls: [GrammarPitfall(heading: "p", explanation: "e", examples: pitfalls)],
            related: [], contrasts: contrasts.isEmpty ? [] : [GrammarContrast(pattern: "c", explanation: "e", examples: contrasts)]
        )
    }

    private func example(_ id: String?, _ jp: String, _ blanks: ParticleBlank...) -> GrammarExample {
        GrammarExample(id: id, jp: jp, en: "en \(jp)", particleBlanks: blanks)
    }

    private func verb(_ dict: String, jlpt: JLPTLevel? = .n5, examples: [VerbExample]) -> Verb {
        Verb(
            type: .u, label: "U-verb", dict: dict, kanji: "乗る", meaning: "ride", description: "d", jlpt: jlpt,
            forms: VerbForms(masuPos: "のります", masuNeg: "", masuPast: "", masuPastNeg: "", te: "", shortPos: "",
                             shortNeg: "", shortPast: "", shortPastNeg: ""),
            examples: examples
        )
    }

    // MARK: Blanks

    func testSplitCountsCodePoints() throws {
        let blank = ParticleBlank(particle: "に", at: 4)
        let parts = try XCTUnwrap(blank.split("私は京都に住んでいます。"))
        XCTAssertEqual(parts.before, "私は京都")
        XCTAssertEqual(parts.after, "住んでいます。")
        let long = try XCTUnwrap(ParticleBlank(particle: "から", at: 1).split("駅から歩きます。"))
        XCTAssertEqual(long.before, "駅")
        XCTAssertEqual(long.after, "歩きます。")
    }

    func testSplitRejectsADriftedBlank() {
        XCTAssertNil(ParticleBlank(particle: "に", at: 3).split("私は京都に住んでいます。"))
        XCTAssertNil(ParticleBlank(particle: "に", at: 40).split("私は京都に住んでいます。"))
        XCTAssertNil(ParticleBlank(particle: "が", at: 0).split("がんばります。"))
        XCTAssertNil(ParticleBlank(particle: "", at: 2).split("私は京都"))
    }

    func testBlanksDecodeFromTheDataShape() throws {
        let json = """
        { "id": "abcdef", "jp": "水が飲みたいです。", "en": "I want water.",
          "particle_blanks": [{ "particle": "が", "at": 1, "accept_also": ["を"] }, { "particle": "が", "at": 1 }] }
        """
        let example = try JSONDecoder().decode(GrammarExample.self, from: Data(json.utf8))
        XCTAssertEqual(example.id, "abcdef")
        XCTAssertEqual(example.particleBlanks, [
            ParticleBlank(particle: "が", at: 1, acceptAlso: ["を"]), ParticleBlank(particle: "が", at: 1),
        ])
        let roundTrip = try JSONDecoder().decode(GrammarExample.self, from: JSONEncoder().encode(example))
        XCTAssertEqual(roundTrip, example)
    }

    func testExamplesWithoutTheNewKeysStillDecode() throws {
        let grammar = try JSONDecoder().decode(GrammarExample.self, from: Data(#"{ "jp": "あ", "en": "a" }"#.utf8))
        XCTAssertNil(grammar.id)
        XCTAssertEqual(grammar.particleBlanks, [])
        let verb = try JSONDecoder().decode(
            VerbExample.self, from: Data(#"{ "form": "masu_pos", "jp": "あ", "en": "a" }"#.utf8))
        XCTAssertNil(verb.id)
        XCTAssertEqual(verb.particleBlanks, [])
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(verb), encoding: .utf8))
        XCTAssertFalse(encoded.contains("particle_blanks"))
        XCTAssertFalse(encoded.contains("\"id\""))
    }

    // MARK: Distractors

    func testDistractorsAreCommonParticlesOtherThanTheAnswer() {
        for _ in 0..<20 {
            let wrong = ParticleQuiz.distractors(for: ParticleBlank(particle: "で", at: 1))
            XCTAssertEqual(wrong.count, 3)
            XCTAssertEqual(Set(wrong).count, 3)
            XCTAssertFalse(wrong.contains("で"))
            XCTAssertTrue(Set(wrong).isSubset(of: ParticleQuiz.commonParticles))
        }
    }

    func testDistractorsNeverIncludeAcceptedOrSubstituteParticles() {
        for _ in 0..<50 {
            let ga = ParticleQuiz.distractors(for: ParticleBlank(particle: "が", at: 1, acceptAlso: ["を"]))
            XCTAssertTrue(Set(ga).isDisjoint(with: ["が", "を", "は", "も"]), "\(ga)")
            let he = ParticleQuiz.distractors(for: ParticleBlank(particle: "へ", at: 1, acceptAlso: ["に"]))
            XCTAssertTrue(Set(he).isDisjoint(with: ["へ", "に", "まで"]), "\(he)")
            let ni = ParticleQuiz.distractors(for: ParticleBlank(particle: "に", at: 1))
            XCTAssertFalse(ni.contains("まで"))
        }
    }

    func testAParticleOutsideTheCommonListStillGetsDistractors() {
        let wrong = ParticleQuiz.distractors(for: ParticleBlank(particle: "の", at: 1))
        XCTAssertEqual(wrong.count, 3)
        XCTAssertFalse(wrong.contains("の"))
    }

    // MARK: Building

    func testOnlyMarkedBlanksMakeQuestions() {
        let grammar = [point(examples: [
            example("aaaaaa", "私は京都に住んでいます。", ParticleBlank(particle: "に", at: 4)),
            example("bbbbbb", "雨が降っています。"),
        ])]
        let questions = buildParticleQuestions(grammar: grammar, verbs: [], count: 10)
        XCTAssertEqual(questions.map(\.blankID), ["aaaaaa#0"])
    }

    func testQuestionCarriesTheSentenceTheAnswerAndTheLink() throws {
        let grammar = [point("teiru", examples: [
            example("aaaaaa", "私は京都に住んでいます。", ParticleBlank(particle: "に", at: 4)),
        ])]
        let question = try XCTUnwrap(buildParticleQuestions(grammar: grammar, verbs: [], count: 5).first)
        XCTAssertEqual(question.sentence, "私は京都に住んでいます。")
        XCTAssertEqual(question.blanked, "私は京都\(QuizQuestion.blank)住んでいます。")
        XCTAssertEqual(question.particle, "に")
        XCTAssertEqual(question.choices.count, 4)
        XCTAssertEqual(question.choices.filter { $0 == "に" }.count, 1)
        XCTAssertEqual(question.translation, "en 私は京都に住んでいます。")
        XCTAssertEqual(question.source, .grammar("teiru"))
        XCTAssertEqual(question.sourceTitle, "Title teiru")
    }

    func testEachBlankOfAnExampleIsItsOwnQuestion() {
        let grammar = [point(examples: [
            example("aaaaaa", "日本へ行こうと思っています。",
                    ParticleBlank(particle: "へ", at: 2, acceptAlso: ["に"]), ParticleBlank(particle: "と", at: 6)),
        ])]
        let questions = buildParticleQuestions(grammar: grammar, verbs: [], count: 10)
        XCTAssertEqual(Set(questions.map(\.blankID)), ["aaaaaa#0", "aaaaaa#1"])
        let to = questions.first { $0.blankID == "aaaaaa#1" }
        XCTAssertEqual(to?.before, "日本へ行こう")
        XCTAssertEqual(to?.after, "思っています。")
    }

    func testAcceptedParticlesAreRightButNeverChoices() throws {
        let grammar = [point(examples: [
            example("aaaaaa", "水が飲みたいです。", ParticleBlank(particle: "が", at: 1, acceptAlso: ["を"])),
        ])]
        for _ in 0..<20 {
            let question = try XCTUnwrap(buildParticleQuestions(grammar: grammar, verbs: [], count: 1).first)
            XCTAssertFalse(question.choices.contains("を"))
            XCTAssertTrue(question.isCorrect("が"))
            XCTAssertTrue(question.isCorrect("を"))
            XCTAssertFalse(question.isCorrect("に"))
        }
    }

    func testPitfallAndContrastExamplesCount() {
        let grammar = [point(
            examples: [],
            pitfalls: [example("pppppp", "雨が降っています。", ParticleBlank(particle: "が", at: 1))],
            contrasts: [example("cccccc", "駅で会いましょう。", ParticleBlank(particle: "で", at: 1))]
        )]
        let ids = Set(buildParticleQuestions(grammar: grammar, verbs: [], count: 10).map(\.blankID))
        XCTAssertEqual(ids, ["pppppp#0", "cccccc#0"])
    }

    func testVerbExamplesLinkToTheVerb() throws {
        let noru = verb("のる", examples: [
            VerbExample(id: "vvvvvv", form: FormID("masu_pos"), jp: "電車に乗ります。", en: "I ride the train.",
                        particleBlanks: [ParticleBlank(particle: "に", at: 2)]),
        ])
        let question = try XCTUnwrap(buildParticleQuestions(grammar: [], verbs: [noru], count: 5).first)
        XCTAssertEqual(question.blankID, "vvvvvv#0")
        XCTAssertEqual(question.source, .verb("のる"))
        XCTAssertEqual(question.sourceTitle, "のる (乗る)")
        XCTAssertEqual(question.before, "電車")
    }

    func testExamplesWithoutAnIdOrWithADriftedBlankAreSkipped() {
        let grammar = [point(examples: [
            example(nil, "雨が降っています。", ParticleBlank(particle: "が", at: 1)),
            example("aaaaaa", "雨が降っています。", ParticleBlank(particle: "を", at: 1)),
        ])]
        XCTAssertEqual(buildParticleQuestions(grammar: grammar, verbs: [], count: 10), [])
    }

    func testHiddenLevelsMakeNoQuestions() {
        let grammar = [
            point("a", jlpt: .n5, examples: [example("aaaaaa", "雨が降る。", ParticleBlank(particle: "が", at: 1))]),
            point("b", jlpt: .n3, examples: [example("bbbbbb", "雨が降る。", ParticleBlank(particle: "が", at: 1))]),
        ]
        let noru = verb("のる", jlpt: .n3, examples: [
            VerbExample(id: "vvvvvv", form: FormID("masu_pos"), jp: "電車に乗ります。", en: "e",
                        particleBlanks: [ParticleBlank(particle: "に", at: 2)]),
        ])
        let visible = buildParticleQuestions(grammar: grammar, verbs: [noru], levels: LevelSettings(hidden: [.n3]), count: 10)
        XCTAssertEqual(visible.map(\.blankID), ["aaaaaa#0"])
        XCTAssertEqual(buildParticleQuestions(grammar: grammar, verbs: [noru], count: 10).count, 3)
    }

    func testCountCapsAndZeroIsEmpty() {
        let examples = (0..<6).map { example("aaaaa\($0 + 2)", "雨が降る。", ParticleBlank(particle: "が", at: 1)) }
        XCTAssertEqual(buildParticleQuestions(grammar: [point(examples: examples)], verbs: [], count: 4).count, 4)
        XCTAssertEqual(buildParticleQuestions(grammar: [point(examples: examples)], verbs: [], count: 0), [])
    }

    // MARK: Model

    private func question(_ id: String = "aaaaaa#0") -> ParticleQuestion {
        ParticleQuestion(
            blankID: id, sentence: "水が飲みたい。", before: "水", after: "飲みたい。", particle: "が", acceptAlso: ["を"],
            choices: ["が", "に", "で", "と"], translation: "I want water.", source: .grammar("tai"), sourceTitle: "〜たい")
    }

    func testRightAnswerRecordsACorrectAttempt() {
        var attempts: [QuizAttempt] = []
        let date = Date(timeIntervalSince1970: 1000)
        let model = ParticleQuizModel(questions: [question()], recorder: { attempts.append($0) }, now: { date })
        model.choose("が")
        XCTAssertEqual(model.score, 1)
        XCTAssertEqual(model.answeredCorrectly, true)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts[0].subject, "aaaaaa#0")
        XCTAssertEqual(attempts[0].formID, "が")
        XCTAssertEqual(attempts[0].kind, .particle)
        XCTAssertEqual(attempts[0].outcome, .correct)
        XCTAssertNil(attempts[0].errorTag)
        XCTAssertEqual(attempts[0].date, date)
    }

    func testWrongAnswerRecordsTheParticlePicked() {
        var attempts: [QuizAttempt] = []
        let model = ParticleQuizModel(questions: [question()], recorder: { attempts.append($0) })
        model.choose("に")
        model.choose("が")  // ignored: already answered
        XCTAssertEqual(model.score, 0)
        XCTAssertEqual(model.answeredCorrectly, false)
        XCTAssertEqual(attempts.map(\.outcome), [.wrong])
        XCTAssertEqual(attempts[0].errorTag, .wrongParticle("に"))
    }

    func testAdvanceFinishesAndMissedQuestionsAreTheWrongOnes() {
        let model = ParticleQuizModel(questions: [question("a#0"), question("b#0")])
        model.advance()  // not answered: stays
        XCTAssertEqual(model.index, 0)
        model.choose("が")
        model.advance()
        XCTAssertEqual(model.index, 1)
        XCTAssertNil(model.selected)
        model.choose("と")
        model.advance()
        XCTAssertTrue(model.finished)
        XCTAssertEqual(model.missedQuestions.map(\.blankID), ["b#0"])
    }

    // MARK: History

    func testParticleIsNeitherAVerbNorACounterKind() {
        XCTAssertFalse(QuizQuestionKind.particle.isVerbQuestion)
        XCTAssertFalse(QuizQuestionKind.particle.isCounter)
        XCTAssertEqual(QuizQuestionKind(rawValue: "particle"), .particle)
    }

    func testWrongParticleTagRoundTrips() {
        XCTAssertEqual(QuizErrorTag.wrongParticle("に").rawValue, "wrong_particle:に")
        XCTAssertEqual(QuizErrorTag(rawValue: "wrong_particle:から"), .wrongParticle("から"))
        XCTAssertEqual(QuizErrorTag(rawValue: "wrong_particle:"), .generic)
        XCTAssertEqual(QuizErrorTag.wrongParticle("に").category, "wrong_particle")
    }

    func testRepeatedWrongParticlesAreTheDominantConfusion() {
        let attempts = (0..<3).map { n in
            QuizAttempt(subject: "a#\(n)", formID: "が", kind: .particle, outcome: .wrong,
                        date: Date(timeIntervalSince1970: Double(n)), errorTag: .wrongParticle(["を", "に", "で"][n]))
        }
        XCTAssertEqual(QuizConfusion.dominant(in: attempts)?.category, .wrongParticle)
    }

    func testParticleAttemptsMakeNoWeakVerbSpots() {
        let attempts = (0..<5).map { n in
            QuizAttempt(subject: "a#0", formID: "が", kind: .particle, outcome: .wrong,
                        date: Date(timeIntervalSince1970: Double(n)), errorTag: .wrongParticle("を"))
        }
        XCTAssertEqual(QuizProgress(attempts: attempts).weakPairs, [])
    }

    // MARK: Real data

    func testEveryMarkedBlankInTheDataMakesAQuestion() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("data")
        let grammar = try JSONDecoder().decode(
            GrammarDataFile.self, from: Data(contentsOf: root.appendingPathComponent("grammar.json"))).grammar
        let verbs = try RealVerbs.load()
        var marked = 0
        for point in grammar {
            let examples: [GrammarExample] = point.usages.flatMap(\.examples) + point.pitfalls.flatMap(\.examples)
                + point.contrasts.flatMap(\.examples)
            marked += examples.map(\.particleBlanks.count).reduce(0, +)
        }
        marked += verbs.flatMap(\.examples).map(\.particleBlanks.count).reduce(0, +)
        XCTAssertGreaterThan(marked, 0)
        let questions = buildParticleQuestions(grammar: grammar, verbs: verbs, count: .max)
        XCTAssertEqual(questions.count, marked)
        for question in questions {
            XCTAssertEqual(question.before + question.particle + question.after, question.sentence)
            XCTAssertEqual(question.choices.count, 4, question.blankID)
        }
    }
}
