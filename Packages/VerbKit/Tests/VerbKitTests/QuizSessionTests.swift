import XCTest
@testable import VerbKit

final class QuizSessionTests: XCTestCase {
    private func verb(_ dict: String, masuPos: String) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "m", description: "d",
            forms: VerbForms(masuPos: masuPos, masuNeg: "x", masuPast: "y", masuPastNeg: "z", te: "t", shortPos: "s", shortNeg: "sn", shortPast: "sp", shortPastNeg: "spn"),
            examples: []
        )
    }

    private let masuPos = QuizForm.all.first { $0.id == "masu_pos" }!

    private var verbs: [Verb] { [verb("たべる", masuPos: "たべます"), verb("みる", masuPos: "みます")] }

    private func questions(_ verbs: [Verb]) -> [QuizQuestion] {
        [
            QuizQuestion(verb: verbs[0], form: masuPos, kind: .conjugate, formString: "たべます", correct: "たべます", choices: ["みます", "たべます"]),
            QuizQuestion(verb: verbs[1], form: masuPos, kind: .identify, formString: "みます", correct: masuPos.label, choices: [masuPos.label, "Plain"]),
        ]
    }

    private func session(progress: QuizProgressState = QuizProgressState()) -> QuizSession {
        QuizSession(topic: .topics([.basic]), questions: questions(verbs), progress: progress, savedAt: Date(timeIntervalSince1970: 100))
    }

    func testRoundTripsThroughJSONAndRestoresTheQuestions() throws {
        let vm = QuizViewModel(questions: questions(verbs))
        vm.choose("みます")
        vm.advance()
        let saved = QuizSession(topic: .weakSpots, questions: vm.questions, progress: vm.progress, savedAt: Date(timeIntervalSince1970: 5))
        let decoded = try JSONDecoder().decode(QuizSession.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded, saved)

        let restored = try XCTUnwrap(decoded.restore(verbs: verbs))
        XCTAssertEqual(restored.questions, vm.questions)
        XCTAssertEqual(restored.progress, vm.progress)
        XCTAssertEqual(restored.progress.index, 1)
        XCTAssertEqual(restored.progress.results.count, 1)
        XCTAssertFalse(restored.progress.results[0].ok)
    }

    func testViewModelPicksUpTheSavedProgressWithoutRecordingAgain() {
        var recorded = 0
        let progress = QuizProgressState(
            index: 1, selected: nil, timedOut: false, timeLeft: 7, score: 1,
            results: [QuizResult(verb: "たべる", formLabel: masuPos.label, formID: "masu_pos", formString: "たべます",
                                 kind: .conjugate, correct: "たべます", chosen: "たべます", ok: true)]
        )
        let vm = QuizViewModel(questions: questions(verbs), progress: progress, recorder: { _ in recorded += 1 })
        XCTAssertEqual(vm.index, 1)
        XCTAssertEqual(vm.score, 1)
        XCTAssertEqual(vm.timeLeft, 7)
        XCTAssertFalse(vm.isAnswered)
        XCTAssertEqual(recorded, 0)
        XCTAssertEqual(vm.progress, progress)
        vm.choose(masuPos.label)
        XCTAssertEqual(recorded, 1)
        vm.advance()
        XCTAssertTrue(vm.finished)
        XCTAssertEqual(vm.score, 2)
    }

    func testAnAnsweredQuestionIsRestoredAnswered() throws {
        let vm = QuizViewModel(questions: questions(verbs))
        vm.markTimedOut()
        let restored = try XCTUnwrap(QuizSession(topic: .weakSpots, questions: vm.questions, progress: vm.progress, savedAt: Date()).restore(verbs: verbs))
        let again = QuizViewModel(questions: restored.questions, progress: restored.progress)
        XCTAssertTrue(again.timedOut)
        XCTAssertTrue(again.isAnswered)
        again.advance()
        XCTAssertEqual(again.index, 1)
    }

    func testTheLastQuestionAnsweredCanStillBeResumedToItsResults() throws {
        let vm = QuizViewModel(questions: questions(verbs))
        vm.choose("たべます"); vm.advance(); vm.choose(masuPos.label)
        let restored = try XCTUnwrap(QuizSession(topic: .weakSpots, questions: vm.questions, progress: vm.progress, savedAt: Date()).restore(verbs: verbs))
        let again = QuizViewModel(questions: restored.questions, progress: restored.progress)
        again.advance()
        XCTAssertTrue(again.finished)
        XCTAssertEqual(again.score, 2)
    }

    func testAGoneVerbOrChangedFormStringCannotBeResumed() {
        XCTAssertNil(session().restore(verbs: [verbs[0]]))
        XCTAssertNil(session().restore(verbs: [verbs[0], verb("みる", masuPos: "みまする")]))
        XCTAssertNil(session().restore(verbs: []))
        XCTAssertNotNil(session().restore(verbs: verbs.reversed()))
    }

    func testAChangedFormSetOrVersionCannotBeResumed() {
        var other = session()
        other.catalogue = "something else"
        XCTAssertNil(other.restore(verbs: verbs))
        var newer = session()
        newer.version = QuizSession.currentVersion + 1
        XCTAssertNil(newer.restore(verbs: verbs))
        var unknownForm = session()
        unknownForm.questions[0].formID = "no_such_form"
        XCTAssertNil(unknownForm.restore(verbs: verbs))
        var relabelled = session()
        relabelled.questions[1].correct = "Old label"
        relabelled.questions[1].choices[0] = "Old label"
        XCTAssertNil(relabelled.restore(verbs: verbs))
    }

    func testInconsistentProgressCannotBeResumed() {
        XCTAssertNil(session(progress: QuizProgressState(index: 2)).restore(verbs: verbs))
        XCTAssertNil(session(progress: QuizProgressState(index: 1)).restore(verbs: verbs))  // no result for question 1
        XCTAssertNil(session(progress: QuizProgressState(index: 0, score: 1)).restore(verbs: verbs))
        XCTAssertNil(session(progress: QuizProgressState(index: 0, timeLeft: 99)).restore(verbs: verbs))
    }

    func testOnlyVerbQuizKindsAreResumed() {
        var counter = session()
        counter.questions[0].kind = .counterChoice
        XCTAssertNil(counter.restore(verbs: verbs))
    }

    func testTitleAndSummary() {
        XCTAssertEqual(QuizSessionTopic.weakSpots.title, "Weak spots")
        XCTAssertEqual(QuizSessionTopic.topics([.potential]).title, "Potential")
        XCTAssertEqual(QuizSessionTopic.topics([.basic, .potential]).title, "Everything")
        let vm = QuizViewModel(questions: questions(verbs))
        vm.choose("たべます")
        XCTAssertEqual(QuizSession(topic: .weakSpots, questions: vm.questions, progress: vm.progress, savedAt: Date()).summary,
                       "1 of 2 answered · 1 correct")
    }

    func testCatalogueFingerprintIsStable() {
        XCTAssertEqual(QuizForm.catalogueFingerprint.count, 64)
        XCTAssertEqual(QuizForm.catalogueFingerprint, QuizForm.catalogueFingerprint)
    }
}

@MainActor
final class QuizSessionStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "QuizSessionStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private let verbs = [Verb(
        type: .ru, label: "Ru-verb", dict: "たべる", kanji: nil, meaning: "m", description: "d",
        forms: VerbForms(masuPos: "たべます", masuNeg: "たべません", masuPast: "x", masuPastNeg: "y", te: "t", shortPos: "s", shortNeg: "sn", shortPast: "sp", shortPastNeg: "spn"),
        examples: []
    )]

    private var session: QuizSession {
        let form = QuizForm.all.first { $0.id == "masu_pos" }!
        let question = QuizQuestion(verb: verbs[0], form: form, kind: .conjugate, formString: "たべます", correct: "たべます", choices: ["たべます", "たべません"])
        return QuizSession(topic: .topics([.basic]), questions: [question], progress: QuizProgressState(timeLeft: 12), savedAt: Date(timeIntervalSince1970: 1))
    }

    func testSavesLoadsAndClears() {
        let store = QuizSessionStore(defaults: defaults)
        XCTAssertNil(store.session)
        store.save(session)
        XCTAssertEqual(QuizSessionStore(defaults: defaults).session, session)
        XCTAssertEqual(QuizSessionStore(defaults: defaults).resumable(verbs: verbs)?.progress.timeLeft, 12)
        store.clear()
        XCTAssertNil(store.session)
        XCTAssertNil(QuizSessionStore(defaults: defaults).session)
    }

    func testAnUnreadableValueIsDropped() {
        defaults.set(Data("not json".utf8), forKey: QuizSessionStore.defaultsKey)
        XCTAssertNil(QuizSessionStore(defaults: defaults).session)
        XCTAssertNil(defaults.data(forKey: QuizSessionStore.defaultsKey))
    }

    func testDiscardIfStaleKeepsItUntilTheDataLoadsThenDropsAMismatch() {
        let store = QuizSessionStore(defaults: defaults)
        store.save(session)
        store.discardIfStale(verbs: [])
        XCTAssertNotNil(store.session)
        store.discardIfStale(verbs: verbs)
        XCTAssertNotNil(store.session)
        var changed = verbs[0]
        changed.forms.masuPos = "たべまする"
        store.discardIfStale(verbs: [changed])
        XCTAssertNil(store.session)
        XCTAssertNil(QuizSessionStore(defaults: defaults).session)
    }
}
