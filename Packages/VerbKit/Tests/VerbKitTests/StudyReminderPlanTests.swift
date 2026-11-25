import XCTest
@testable import VerbKit

final class StudyReminderPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// One answered attempt on each given day of November, at noon.
    private func practised(on days: [Int]) -> [QuizAttempt] {
        days.map { QuizAttempt(subject: "taberu", formID: "te", kind: .conjugate, outcome: .correct, date: date($0, 12)) }
    }

    private let both = StudyReminderSettings(reviewEnabled: true, reviewMinutes: 18 * 60, streakEnabled: true, streakMinutes: 20 * 60)
    private let reviewOnly = StudyReminderSettings(reviewEnabled: true, reviewMinutes: 18 * 60, streakEnabled: false, streakMinutes: 20 * 60)

    private func reviews(_ items: [StudyReminderItem]) -> [StudyReminderItem] {
        items.filter { if case .review = $0.kind { true } else { false } }
    }

    private func streaks(_ items: [StudyReminderItem]) -> [StudyReminderItem] {
        items.filter { if case .streak = $0.kind { true } else { false } }
    }

    func testReviewIsDailyWhileThereAreWeakSpots() {
        // 19:00 on the 25th: today's 18:00 has passed, so the rest of the 14-day window, the 26th to 8 December.
        let items = StudyReminderPlan.items(attempts: practised(on: [24]), weakCount: 8, settings: reviewOnly, now: date(25, 19), calendar: calendar)
        XCTAssertEqual(items.count, 13, "the 26th…8th Dec: 14 days from today minus today")
        XCTAssertEqual(items.first?.kind, .review(count: 8))
        XCTAssertEqual(items.first?.fireDate.day, 26)
        XCTAssertEqual(items.first?.fireDate.hour, 18)
        XCTAssertEqual(items.first?.identifier, "review-20261126")
        XCTAssertEqual(items.first?.url, QuizLink.weakSpots.url)
    }

    func testNoWeakSpotsMeansNoReview() {
        let items = StudyReminderPlan.items(attempts: practised(on: [24]), weakCount: 0, settings: reviewOnly, now: date(25, 9), calendar: calendar)
        XCTAssertTrue(items.isEmpty)
    }

    func testReviewSkipsAPractisedDay() {
        let items = StudyReminderPlan.items(attempts: practised(on: [25]), weakCount: 3, settings: reviewOnly, now: date(25, 9), calendar: calendar)
        XCTAssertEqual(items.first?.fireDate.day, 26, "today is already practised")
    }

    func testStreakTodayWhenNotPractised() {
        let items = StudyReminderPlan.items(attempts: practised(on: [20, 21, 22, 23, 24]), weakCount: 8, settings: both, now: date(25, 17), calendar: calendar)
        let streak = streaks(items)
        XCTAssertEqual(streak.count, 1)
        XCTAssertEqual(streak.first?.kind, .streak(days: 5))
        XCTAssertEqual(streak.first?.fireDate.day, 25)
        XCTAssertEqual(streak.first?.fireDate.hour, 20)
        XCTAssertEqual(streak.first?.identifier, "streak-20261125")
        XCTAssertFalse(reviews(items).contains { $0.fireDate.day == 25 }, "never both on one day")
        XCTAssertEqual(reviews(items).first?.fireDate.day, 26)
    }

    func testStreakTomorrowWhenPractisedToday() {
        let items = StudyReminderPlan.items(attempts: practised(on: [23, 24, 25]), weakCount: 2, settings: both, now: date(25, 13), calendar: calendar)
        let streak = streaks(items)
        XCTAssertEqual(streak.map(\.kind), [.streak(days: 3)])
        XCTAssertEqual(streak.first?.fireDate.day, 26)
        XCTAssertFalse(reviews(items).contains { $0.fireDate.day == 25 || $0.fireDate.day == 26 })
        XCTAssertEqual(reviews(items).first?.fireDate.day, 27)
    }

    func testPractisedYesterdayOnlySchedulesToday() {
        // An answer late yesterday, then a refresh just after midnight.
        let late = [QuizAttempt(subject: "taberu", formID: "te", kind: .conjugate, outcome: .correct, date: date(24, 23, 59))]
        let items = StudyReminderPlan.items(attempts: late, weakCount: 0, settings: both, now: date(25, 0, 1), calendar: calendar)
        XCTAssertEqual(streaks(items).map(\.kind), [.streak(days: 1)])
        XCTAssertEqual(streaks(items).first?.fireDate.day, 25)
    }

    func testTimesThatHavePassedAreSkipped() {
        let items = StudyReminderPlan.items(attempts: practised(on: [24]), weakCount: 1, settings: both, now: date(25, 21), calendar: calendar)
        XCTAssertTrue(streaks(items).isEmpty, "today's 20:00 passed and today isn't practised")
        XCTAssertEqual(reviews(items).first?.fireDate.day, 26)
    }

    func testSwitchesOffScheduleNothing() {
        let off = StudyReminderSettings(reviewEnabled: false, reviewMinutes: 18 * 60, streakEnabled: false, streakMinutes: 20 * 60)
        XCTAssertTrue(StudyReminderPlan.items(attempts: practised(on: [24]), weakCount: 5, settings: off, now: date(25, 9), calendar: calendar).isEmpty)
    }

    func testNoHistoryMeansNoStudyReminders() {
        XCTAssertTrue(StudyReminderPlan.items(attempts: [], weakCount: 0, settings: both, now: date(25, 9), calendar: calendar).isEmpty)
    }

    func testTimedOutAnswersDoNotCountAsPractice() {
        let timedOut = [QuizAttempt(subject: "taberu", formID: "te", kind: .conjugate, outcome: .timedOut, date: date(25, 8))]
        let items = StudyReminderPlan.items(attempts: practised(on: [24]) + timedOut, weakCount: 1, settings: both, now: date(25, 9), calendar: calendar)
        XCTAssertEqual(streaks(items).first?.fireDate.day, 25)
    }

    func testWeakQuizLinkRoundTrips() {
        XCTAssertEqual(QuizLink.weakSpots.url.absoluteString, "verbtable://quiz/weak")
        XCTAssertEqual(QuizLink(url: URL(string: "verbtable://quiz/weak")!), .weakSpots)
        XCTAssertEqual(QuizLink(url: URL(string: "verbtable://quiz/basic")!), QuizLink(topic: .basic))
        XCTAssertEqual(QuizLink(url: URL(string: "verbtable://quiz")!), QuizLink(topic: nil))
        XCTAssertNil(QuizLink(url: URL(string: "verbtable://quiz/nope")!))
        XCTAssertFalse(QuizLink(topic: .basic).weakSpots)
    }
}
