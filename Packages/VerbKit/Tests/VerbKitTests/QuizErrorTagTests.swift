import XCTest
import SwiftData
@testable import VerbKit

final class QuizErrorTagTests: XCTestCase {
    private func verb(_ dict: String, kanji: String? = nil) throws -> Verb {
        try XCTUnwrap(try RealVerbs.load().first { $0.dict == dict && (kanji == nil || $0.kanji == kanji) })
    }

    private func form(_ id: String) throws -> QuizForm {
        try XCTUnwrap(QuizForm.all.first { $0.id == id })
    }

    private func questions(_ verb: Verb, _ formID: String, kind: QuizQuestionKind = .conjugate, among: [Verb]? = nil) throws -> [QuizQuestion] {
        let pairs = Array(repeating: (verb: verb, form: try form(formID)), count: 60)
        return buildQuestions(pairs: pairs, among: among ?? [verb], count: 60, kinds: [kind])
    }

    private func tags(_ questions: [QuizQuestion]) -> Set<QuizErrorTag> {
        Set(questions.flatMap { Array($0.errors.values) })
    }

    // MARK: categories

    func testWrongTeGroupForAGroupedVerb() throws {
        let nomu = try verb("のむ")
        let all = try questions(nomu, "te")
        XCTAssertTrue(all.contains { $0.errors["のって"] == .wrongTeGroup(.tte) })
        XCTAssertTrue(all.allSatisfy { !$0.choices.contains("のんで") || $0.correct == "のんで" })
    }

    func testTheIkuExceptionOffersTheRegularRuleMistake() throws {
        let iku = try verb("いく")
        let all = try questions(iku, "te")
        XCTAssertTrue(all.contains { $0.errors["いいて"] == .wrongTeGroup(.ite) })
        XCTAssertTrue(all.allSatisfy { $0.correct == "いって" })
    }

    func testRuVerbTreatedAsUVerb() throws {
        let taberu = try verb("たべる")
        let all = try questions(taberu, "short_neg")
        XCTAssertTrue(all.contains { $0.errors["たべらない"] == .ruUConfusion })
        let masu = try questions(taberu, "masu_pos")
        XCTAssertTrue(masu.contains { $0.errors["たべります"] == .ruUConfusion })
    }

    func testULookalikeTreatedAsRuVerb() throws {
        let kaeru = try verb("かえる", kanji: "帰る")
        let all = try questions(kaeru, "short_neg")
        XCTAssertTrue(all.contains { $0.errors["かえない"] == .ruUConfusion })
    }

    func testAruNegative() throws {
        let aru = try verb("ある")
        let all = try questions(aru, "short_neg")
        XCTAssertTrue(all.contains { $0.errors["あらない"] == .aruNegative })
        XCTAssertTrue(all.allSatisfy { $0.correct == "ない" })
    }

    func testPassiveAndPotentialAreTaggedAsEachOther() throws {
        let nomu = try verb("のむ")
        XCTAssertTrue(try questions(nomu, "passive").contains { $0.errors["のめる"] == .passivePotential })
        XCTAssertTrue(try questions(nomu, "potential").contains { $0.errors["のまれる"] == .passivePotential })
    }

    func testCausativePassiveLongShort() throws {
        let nomu = try verb("のむ")
        let id = "causative_passive"
        let short = nomu.forms[id: FormID(rawValue: "causative_passive_short")]
        try XCTSkipIf(short == nil, "no short causative-passive in the data")
        let all = try questions(nomu, id)
        XCTAssertTrue(all.contains { $0.errors[short!] == .causativePassiveLongShort })
    }

    func testOtherFormAndOtherVerb() throws {
        let verbs = try RealVerbs.load()
        let nomu = try verb("のむ")
        let all = try questions(nomu, "short_pos")
        XCTAssertTrue(tags(all).contains { if case .otherForm = $0 { true } else { false } })
        // Another verb's form is only used when the verb has too few distinct forms of its own.
        var sparse = nomu
        sparse.forms = try JSONDecoder().decode(VerbForms.self, from: Data(
            """
            {"masu_pos":"のみます","masu_neg":"のみます","masu_past":"のみます","masu_past_neg":"のみます",
             "te":"のんで","short_pos":"のむ","short_neg":"のむ","short_past":"のむ","short_past_neg":"のむ"}
            """.utf8))
        let borrowed = buildQuestions(
            pairs: Array(repeating: (verb: sparse, form: try form("short_pos")), count: 30),
            among: verbs, count: 30, kinds: [.conjugate])
        XCTAssertTrue(tags(borrowed).contains { if case .otherVerb = $0 { true } else { false } })
        let identify = try questions(nomu, "short_pos", kind: .identify)
        XCTAssertTrue(tags(identify).allSatisfy { if case .otherForm = $0 { true } else { false } })
    }

    // MARK: invariants

    func testEveryDistractorIsTaggedAndNoSyntheticIsARealForm() throws {
        let verbs = try RealVerbs.load()
        for _ in 0..<3 {
            for question in buildQuestions(verbs: verbs, topics: Set(QuizTopic.allCases), count: 150, kinds: QuizQuestionKind.verbKinds) {
                let wrong = Set(question.choices).subtracting([question.correct])
                XCTAssertEqual(Set(question.errors.keys), wrong, "\(question.verb.dict) \(question.form.id)")
                XCTAssertNil(question.errors[question.correct])
                XCTAssertEqual(Set(question.choices).count, question.choices.count)
                XCTAssertGreaterThanOrEqual(question.choices.count, 2)
                let real = Set(QuizForm.available(in: question.verb.forms, topics: Set(QuizTopic.allCases)).map(\.value))
                for (choice, tag) in question.errors {
                    switch tag {
                    case .wrongTeGroup, .ruUConfusion, .aruNegative:
                        XCTAssertFalse(real.contains(choice), "\(choice) is a real form")
                    default: break
                    }
                }
            }
        }
    }

    func testEveryTagExplains() throws {
        let taberu = try verb("たべる")
        let te = try form("te")
        let tags: [QuizErrorTag] = [
            .otherForm("te"), .wrongTeGroup(.tte), .ruUConfusion, .aruNegative, .passivePotential,
            .causativePassiveLongShort, .otherVerb("のむ"), .generic,
        ]
        for tag in tags {
            XCTAssertFalse(tag.explanation(verb: taberu, form: te, kind: .conjugate, chosen: "たべない").isEmpty)
            XCTAssertFalse(tag.explanation(verb: taberu, form: te, kind: .identify, chosen: "Plain · negative").isEmpty)
        }
        let iku = try verb("いく")
        XCTAssertTrue(QuizErrorTag.wrongTeGroup(.ite).explanation(verb: iku, form: te, kind: .conjugate, chosen: "いいて").contains("exception"))
    }

    // MARK: raw values and storage

    func testRawValuesRoundTripAndUnknownReadsAsGeneric() {
        let tags: [QuizErrorTag] = [.otherForm("te"), .wrongTeGroup(.shite), .ruUConfusion, .aruNegative,
                                    .passivePotential, .causativePassiveLongShort, .otherVerb("きる:切る"), .generic]
        for tag in tags { XCTAssertEqual(QuizErrorTag(rawValue: tag.rawValue), tag) }
        XCTAssertEqual(QuizErrorTag(rawValue: "something_new:x"), .generic)
        XCTAssertEqual(QuizErrorTag(rawValue: "wrong_te_group:nope"), .generic)
    }

    func testALegacyResultWithoutATagDecodes() throws {
        let json = """
        {"verb":"たべる","formLabel":"て","formID":"te","formString":"たべて","kind":"conjugate",
         "correct":"たべて","chosen":"たべ","ok":false,"timedOut":false}
        """
        let result = try JSONDecoder().decode(QuizResult.self, from: Data(json.utf8))
        XCTAssertNil(result.error)
    }

    @MainActor
    func testAnAttemptKeepsItsTagAndAnUntaggedRowLoads() throws {
        let context = ModelContext(try VerbModelContainer.makeInMemory())
        let store = SwiftDataQuizHistoryPersisting(modelContext: context)
        let tagged = QuizAttempt(subject: "いく", formID: "te", kind: .conjugate, outcome: .wrong,
                                 date: Date(timeIntervalSince1970: 1), errorTag: .wrongTeGroup(.ite))
        try store.append(tagged)
        context.insert(QuizAttemptEntity(id: UUID(), subject: "みる", formID: "te", kindRaw: "conjugate",
                                         outcomeRaw: "wrong", date: Date(timeIntervalSince1970: 2)))
        try context.save()
        let loaded = try store.loadAll()
        XCTAssertEqual(loaded.first?.errorTag, .wrongTeGroup(.ite))
        XCTAssertNil(loaded.last?.errorTag)
    }

    func testTheViewModelRecordsTheTagOfAWrongPick() throws {
        let iku = try verb("いく")
        let question = try XCTUnwrap(try questions(iku, "te").first { $0.errors["いいて"] != nil })
        var recorded: [QuizAttempt] = []
        let model = QuizViewModel(questions: [question], recorder: { recorded.append($0) })
        model.choose("いいて")
        XCTAssertEqual(recorded.first?.errorTag, .wrongTeGroup(.ite))
        XCTAssertNotNil(model.results.first?.errorExplanation)

        let right = QuizViewModel(questions: [question], recorder: { recorded.append($0) })
        right.choose(question.correct)
        XCTAssertNil(recorded.last?.errorTag)
        XCTAssertNil(right.results.first?.error)
    }

    func testIdentifyExplanationDescribesTheAskedFormNotTheChosenOneAsAString() throws {
        let wakaru = try verb("わかる")
        let asked = try form("masu_pos")
        let chosen = try form("short_past_neg")
        let text = QuizErrorTag.otherForm(chosen.id).explanation(
            verb: wakaru, form: asked, kind: .identify, chosen: chosen.label)
        XCTAssertEqual(text, "わかります is the \(asked.label) form. \(chosen.label) would be わからなかった.")
        XCTAssertFalse(text.contains("The question asked"))
    }

    func testIdentifyExplanationOmitsTheSecondSentenceWhenTheVerbLacksThatForm() throws {
        let aru = try verb("ある")
        let potential = try form("potential")
        let text = QuizErrorTag.otherForm(potential.id).explanation(
            verb: aru, form: try form("masu_pos"), kind: .identify, chosen: potential.label)
        XCTAssertEqual(text, "あります is the \(try form("masu_pos").label) form.")
    }

    func testConjugateExplanationNamesTheChosenFormAndNotTheAnswer() throws {
        let wakaru = try verb("わかる")
        let asked = try form("masu_pos")
        let chosen = try form("short_past_neg")
        let text = QuizErrorTag.otherForm(chosen.id).explanation(
            verb: wakaru, form: asked, kind: .conjugate, chosen: "わからなかった")
        XCTAssertEqual(text, "わからなかった is the \(chosen.label) form.")
        XCTAssertFalse(text.contains("わかります"))
    }

    func testPassivePotentialKeepsTheMixUpSentenceOnly() throws {
        let nomu = try verb("のむ")
        let text = QuizErrorTag.passivePotential.explanation(
            verb: nomu, form: try form("passive"), kind: .conjugate, chosen: "のめる")
        XCTAssertTrue(text.hasPrefix("のめる is the "))
        XCTAssertTrue(text.contains("easy to mix up"))
        XCTAssertFalse(text.contains("のまれる"))
    }
}
