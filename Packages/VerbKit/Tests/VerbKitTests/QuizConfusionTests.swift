import XCTest
@testable import VerbKit

final class QuizConfusionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var tick = 0

    /// Each call is one minute after the previous, so call order is chronological order.
    private func wrong(_ tag: QuizErrorTag?, outcome: QuizOutcome = .wrong) -> QuizAttempt {
        tick += 1
        return QuizAttempt(subject: "食べる", formID: "te", kind: .conjugate, outcome: outcome,
                           date: start.addingTimeInterval(Double(tick) * 60), errorTag: tag)
    }

    func testEmptyHistoryShowsNothing() {
        XCTAssertNil(QuizConfusion.dominant(in: []))
    }

    func testBelowThresholdShowsNothing() {
        let attempts = (0..<(QuizConfusion.minimumCount - 1)).map { _ in wrong(.ruUConfusion) }
        XCTAssertNil(QuizConfusion.dominant(in: attempts))
    }

    func testAtThresholdShows() {
        let attempts = (0..<QuizConfusion.minimumCount).map { _ in wrong(.ruUConfusion) }
        let result = QuizConfusion.dominant(in: attempts)
        XCTAssertEqual(result?.category, .ruUConfusion)
        XCTAssertEqual(result?.count, QuizConfusion.minimumCount)
        XCTAssertEqual(result?.windowSize, QuizConfusion.minimumCount)
    }

    func testUntaggedOldHistoryNeverShows() {
        let attempts = (0..<30).map { _ in wrong(nil) }
        XCTAssertNil(QuizConfusion.dominant(in: attempts))
    }

    func testGenericIsIgnoredAndDoesNotFillTheWindow() {
        var attempts = (0..<QuizConfusion.minimumCount).map { _ in wrong(.aruNegative) }
        attempts += (0..<50).map { _ in wrong(.generic) }
        XCTAssertEqual(QuizConfusion.dominant(in: attempts)?.category, .aruNegative)
        XCTAssertNil(QuizConfusion.dominant(in: (0..<10).map { _ in wrong(.generic) }))
    }

    func testCorrectAndTimedOutAttemptsAreIgnored() {
        let attempts = [wrong(.passivePotential, outcome: .correct), wrong(.passivePotential, outcome: .timedOut),
                        wrong(.passivePotential), wrong(.passivePotential)]
        XCTAssertNil(QuizConfusion.dominant(in: attempts))
    }

    func testOnlyTheMostRecentWindowCounts() {
        // Five old ru/u mistakes, then twenty newer ones with only two ru/u: the old ones fall out.
        var attempts = (0..<5).map { _ in wrong(.ruUConfusion) }
        attempts += (0..<18).map { _ in wrong(.passivePotential) }
        attempts += (0..<2).map { _ in wrong(.ruUConfusion) }
        let result = QuizConfusion.dominant(in: attempts)
        XCTAssertEqual(result?.category, .passivePotential)
        XCTAssertEqual(result?.count, 18)
        XCTAssertEqual(result?.windowSize, QuizConfusion.windowSize)
    }

    func testDatesDecideRecencyNotArrayOrder() {
        // Twenty recent aru mistakes, plus three ru/u mistakes dated long ago but listed last.
        var attempts = (0..<QuizConfusion.windowSize).map { _ in wrong(.aruNegative) }
        attempts += (0..<3).map { _ in
            QuizAttempt(subject: "食べる", formID: "te", kind: .conjugate, outcome: .wrong,
                        date: start.addingTimeInterval(-86_400 * 30), errorTag: .ruUConfusion)
        }
        let result = QuizConfusion.dominant(in: attempts)
        XCTAssertEqual(result?.category, .aruNegative)
        XCTAssertEqual(result?.count, QuizConfusion.windowSize)
    }

    func testTeGroupPayloadsGroupTogether() {
        let attempts = [wrong(.wrongTeGroup(.tte)), wrong(.wrongTeGroup(.nde)), wrong(.wrongTeGroup(.shite))]
        XCTAssertEqual(QuizConfusion.dominant(in: attempts)?.category, .wrongTeGroup)
    }

    func testOtherFormAndOtherVerbPayloadsGroupTogether() {
        let forms = [wrong(.otherForm("nai")), wrong(.otherForm("masu")), wrong(.otherForm("ta"))]
        XCTAssertEqual(QuizConfusion.dominant(in: forms)?.category, .otherForm)
        let verbs = [wrong(.otherVerb("のむ")), wrong(.otherVerb("よむ")), wrong(.otherVerb("かく"))]
        XCTAssertEqual(QuizConfusion.dominant(in: verbs)?.category, .otherVerb)
    }

    func testBiggestCategoryWins() {
        let attempts = [wrong(.aruNegative), wrong(.ruUConfusion), wrong(.ruUConfusion), wrong(.aruNegative),
                        wrong(.ruUConfusion), wrong(.aruNegative), wrong(.ruUConfusion)]
        let result = QuizConfusion.dominant(in: attempts)
        XCTAssertEqual(result?.category, .ruUConfusion)
        XCTAssertEqual(result?.count, 4)
        XCTAssertEqual(result?.windowSize, 7)
    }

    func testTieGoesToTheMoreRecentMistake() {
        let attempts = [wrong(.aruNegative), wrong(.aruNegative), wrong(.aruNegative),
                        wrong(.passivePotential), wrong(.passivePotential), wrong(.passivePotential)]
        XCTAssertEqual(QuizConfusion.dominant(in: attempts)?.category, .passivePotential)
    }

    func testEveryCategoryHasWordingAndGuideLinksMatchTheQuiz() {
        for category in QuizConfusion.Category.allCases {
            XCTAssertFalse(category.headline.isEmpty)
            XCTAssertFalse(category.advice.isEmpty)
        }
        XCTAssertEqual(QuizConfusion.Category.ruUConfusion.opensVerbGuide, QuizErrorTag.ruUConfusion.opensVerbGuide)
        XCTAssertEqual(QuizConfusion.Category.wrongTeGroup.opensVerbGuide, QuizErrorTag.wrongTeGroup(.tte).opensVerbGuide)
        XCTAssertEqual(QuizConfusion.Category.aruNegative.opensVerbGuide, QuizErrorTag.aruNegative.opensVerbGuide)
        XCTAssertEqual(QuizConfusion.Category.passivePotential.opensVerbGuide, QuizErrorTag.passivePotential.opensVerbGuide)
        XCTAssertEqual(QuizConfusion.Category.otherForm.opensVerbGuide, QuizErrorTag.otherForm("ta").opensVerbGuide)
    }

    func testQuizProgressExposesIt() {
        let attempts = (0..<3).map { _ in wrong(.ruUConfusion) }
        XCTAssertEqual(QuizProgress(attempts: attempts).confusion?.category, .ruUConfusion)
        XCTAssertNil(QuizProgress(attempts: []).confusion)
    }
}
