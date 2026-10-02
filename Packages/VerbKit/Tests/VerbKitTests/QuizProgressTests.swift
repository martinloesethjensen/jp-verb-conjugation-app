import XCTest
@testable import VerbKit

final class QuizProgressTests: XCTestCase {
    private func calendar(_ tz: String = "UTC") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: tz)!
        return c
    }

    private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Fixed "now": 2026-06-15 12:00 UTC.
    private var cal: Calendar { calendar() }
    private var now: Date { date(cal, 2026, 6, 15, 12) }

    private func attempt(
        _ verb: String = "食べる", _ form: String = "te", _ outcome: QuizOutcome = .correct,
        daysAgo: Int = 0, hour: Int = 12, minute: Int = 0
    ) -> QuizAttempt {
        let base = cal.startOfDay(for: now)
        let day = cal.date(byAdding: .day, value: -daysAgo, to: base)!
        let d = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return QuizAttempt(verb: verb, formID: form, kind: .conjugate, outcome: outcome, date: d)
    }

    private func attempt(outcome: QuizOutcome, daysAgo: Int = 0, hour: Int = 12) -> QuizAttempt {
        attempt("食べる", "te", outcome, daysAgo: daysAgo, hour: hour)
    }

    private func progress(_ a: [QuizAttempt]) -> QuizProgress {
        QuizProgress(attempts: a, calendar: cal, now: now)
    }

    /// Five-attempt pair, oldest first, with the miss at the given position (0 = oldest).
    private func pairWithMiss(at index: Int, miss: QuizOutcome = .wrong) -> [QuizAttempt] {
        (0..<5).map { i in
            attempt(outcome: i == index ? miss : .correct, daysAgo: 5 - i)
        }
    }

    // MARK: weakness

    func testNewestMissAmongFiveHasWeightFive() {
        let p = progress(pairWithMiss(at: 4))
        XCTAssertEqual(p.weakPairs.count, 1)
        XCTAssertEqual(p.weakPairs[0].weakness, 5.0 / 15.0, accuracy: 1e-9)
    }

    func testOldestMissInWindowHasWeightOne() {
        let p = progress(pairWithMiss(at: 0))
        XCTAssertEqual(p.weakPairs[0].weakness, 1.0 / 15.0, accuracy: 1e-9)
    }

    func testMissOutsideWindowOfFiveIsNotWeak() {
        var a = [attempt(outcome: .wrong, daysAgo: 6)]
        a += (0..<5).map { attempt(outcome: .correct, daysAgo: 5 - $0) }
        XCTAssertTrue(progress(a).weakPairs.isEmpty)
    }

    func testTimeoutCountsAsMiss() {
        let p = progress(pairWithMiss(at: 4, miss: .timedOut))
        XCTAssertEqual(p.weakPairs[0].weakness, 5.0 / 15.0, accuracy: 1e-9)
    }

    func testAllCorrectIsNotWeak() {
        XCTAssertTrue(progress(pairWithMiss(at: 99)).weakPairs.isEmpty)
    }

    func testFewerThanFiveAttemptsUseWeightsFromNewest() {
        let a = [attempt(outcome: .correct, daysAgo: 2), attempt(outcome: .wrong, daysAgo: 1)]
        // newest wrong weight 5, older correct weight 4 -> 5/9
        XCTAssertEqual(progress(a).weakPairs[0].weakness, 5.0 / 9.0, accuracy: 1e-9)
        let single = [attempt(outcome: .wrong)]
        XCTAssertEqual(progress(single).weakPairs[0].weakness, 1.0, accuracy: 1e-9)
    }

    func testIdenticalDatesUseInputOrderLaterIsNewer() {
        let d = now
        let first = QuizAttempt(verb: "a", formID: "te", kind: .conjugate, outcome: .wrong, date: d)
        let second = QuizAttempt(verb: "a", formID: "te", kind: .conjugate, outcome: .correct, date: d)
        // second is newer (weight 5, correct), first older (weight 4, miss) -> 4/9
        XCTAssertEqual(progress([first, second]).weakPairs[0].weakness, 4.0 / 9.0, accuracy: 1e-9)
        // reversed input: wrong is newer -> 5/9
        XCTAssertEqual(progress([second, first]).weakPairs[0].weakness, 5.0 / 9.0, accuracy: 1e-9)
    }

    func testUnsortedInputIsOrderedByDate() {
        let a = pairWithMiss(at: 4)
        XCTAssertEqual(progress(a.reversed()).weakPairs[0].weakness, 5.0 / 15.0, accuracy: 1e-9)
    }

    func testRankingByWeaknessThenRecencyThenIDs() {
        let strong = [attempt("b", "te", .wrong, daysAgo: 3)]                       // 1.0
        let mid1 = [attempt("c", "te", .correct, daysAgo: 5), attempt("c", "te", .wrong, daysAgo: 4)] // 5/9
        let mid2 = [attempt("d", "te", .correct, daysAgo: 3), attempt("d", "te", .wrong, daysAgo: 2)] // 5/9, more recent
        let tieA = [attempt("a", "te", .wrong, daysAgo: 1, hour: 9)]               // 1.0 but most recent
        let p = progress(strong + mid1 + mid2 + tieA)
        XCTAssertEqual(p.weakPairs.map(\.verb), ["a", "b", "d", "c"])
    }

    func testRankingTieBreaksByVerbThenFormID() {
        let d = now
        func w(_ v: String, _ f: String) -> QuizAttempt {
            QuizAttempt(verb: v, formID: f, kind: .conjugate, outcome: .wrong, date: d)
        }
        let p = progress([w("b", "te"), w("a", "short_pos"), w("a", "masu_pos")])
        XCTAssertEqual(p.weakPairs.map { "\($0.verb)/\($0.formID)" }, ["a/masu_pos", "a/short_pos", "b/te"])
    }

    func testWeakPairsAmongFilters() {
        let p = progress([attempt("a", "te", .wrong), attempt("b", "te", .wrong, daysAgo: 1)])
        XCTAssertEqual(p.weakPairs(among: ["b"]).map(\.verb), ["b"])
        XCTAssertEqual(p.weakPairs(among: ["a", "b"]).map(\.verb), ["a", "b"])
        XCTAssertTrue(p.weakPairs(among: []).isEmpty)
    }

    // MARK: streaks

    func testCurrentStreakIncludingToday() {
        let p = progress([attempt(daysAgo: 2), attempt(daysAgo: 1), attempt(daysAgo: 0)])
        XCTAssertEqual(p.currentStreak, 3)
    }

    func testCurrentStreakEndingYesterday() {
        let p = progress([attempt(daysAgo: 2), attempt(daysAgo: 1)])
        XCTAssertEqual(p.currentStreak, 2)
    }

    func testNoStreakWhenNeitherTodayNorYesterday() {
        let p = progress([attempt(daysAgo: 3), attempt(daysAgo: 2)])
        XCTAssertEqual(p.currentStreak, 0)
        XCTAssertEqual(p.bestStreak, 2)
    }

    func testGapBreaksRunAndBestIsLongestHistorical() {
        let a = [10, 9, 8, 7, 4, 3, 0].map { attempt(daysAgo: $0) }
        let p = progress(a)
        XCTAssertEqual(p.currentStreak, 1)
        XCTAssertEqual(p.bestStreak, 4)
    }

    func testTimeoutsAloneDoNotCountADay() {
        let p = progress([attempt(outcome: .timedOut, daysAgo: 0), attempt(daysAgo: 1)])
        XCTAssertEqual(p.currentStreak, 1)
        let only = progress([attempt(outcome: .timedOut, daysAgo: 0)])
        XCTAssertEqual(only.currentStreak, 0)
        XCTAssertEqual(only.bestStreak, 0)
    }

    func testWrongAnswerCountsADay() {
        XCTAssertEqual(progress([attempt(outcome: .wrong)]).currentStreak, 1)
    }

    func testTwoAttemptsSameDayCountOnce() {
        let p = progress([attempt(daysAgo: 0, hour: 8), attempt(daysAgo: 0, hour: 20)])
        XCTAssertEqual(p.currentStreak, 1)
        XCTAssertEqual(p.bestStreak, 1)
    }

    func testEmptyStreaks() {
        let p = progress([])
        XCTAssertEqual(p.currentStreak, 0)
        XCTAssertEqual(p.bestStreak, 0)
    }

    func testMidnightPairInCopenhagenIsTwoConsecutiveDays() {
        let cph = calendar("Europe/Copenhagen")
        let a = QuizAttempt(verb: "a", formID: "te", kind: .conjugate, outcome: .correct,
                            date: date(cph, 2026, 6, 14, 23, 59))
        let b = QuizAttempt(verb: "a", formID: "te", kind: .conjugate, outcome: .correct,
                            date: date(cph, 2026, 6, 15, 0, 1))
        let p = QuizProgress(attempts: [a, b], calendar: cph, now: date(cph, 2026, 6, 15, 10))
        XCTAssertEqual(p.currentStreak, 2)
        XCTAssertEqual(p.bestStreak, 2)
    }

    func testDSTDaysInCopenhagenStayConsecutive() {
        let cph = calendar("Europe/Copenhagen")
        // Spring forward 2026-03-29 (23h day), fall back 2026-10-25 (25h day).
        for (y, m, d) in [(2026, 3, 29), (2026, 10, 25)] {
            let days = [d - 1, d, d + 1]
            let a = days.map { day in
                QuizAttempt(verb: "a", formID: "te", kind: .conjugate, outcome: .correct,
                            date: date(cph, y, m, day, 0, 30))
            }
            let p = QuizProgress(attempts: a, calendar: cph, now: date(cph, y, m, d + 1, 23, 30))
            XCTAssertEqual(p.currentStreak, 3, "\(m)-\(d)")
            XCTAssertEqual(p.bestStreak, 3)
            XCTAssertEqual(p.last7Days.count, 7)
            XCTAssertEqual(p.last7Days.suffix(3).map(\.answered), [1, 1, 1])
        }
    }

    // MARK: stats

    func testLast7DaysShape() {
        let a = [attempt(daysAgo: 0), attempt(daysAgo: 0), attempt(outcome: .timedOut, daysAgo: 0),
                 attempt(daysAgo: 2), attempt(daysAgo: 6), attempt(daysAgo: 7)]
        let days = progress(a).last7Days
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.answered), [1, 0, 0, 0, 1, 0, 2])
        XCTAssertEqual(days.last?.day, cal.startOfDay(for: now))
        XCTAssertEqual(days.first?.day, cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)))
        XCTAssertEqual(days.map(\.day), days.map(\.day).sorted())
    }

    func testAccuracy() {
        let a = [attempt(outcome: .correct), attempt(outcome: .wrong), attempt(outcome: .correct),
                 attempt(outcome: .timedOut)]
        let p = progress(a)
        XCTAssertEqual(p.totalAnswered, 3)
        XCTAssertEqual(p.accuracy!, 2.0 / 3.0, accuracy: 1e-9)
    }

    func testAccuracyNilWithoutAnswers() {
        XCTAssertNil(progress([]).accuracy)
        XCTAssertNil(progress([attempt(outcome: .timedOut)]).accuracy)
        XCTAssertEqual(progress([attempt(outcome: .timedOut)]).totalAnswered, 0)
    }

    func testWeakestVerbsSumsSortsAndCaps() {
        // verb "x" has two weak pairs (1.0 each) -> 2.0; verbs v1...v6 one each.
        var a = [attempt("x", "te", .wrong), attempt("x", "masu_pos", .wrong)]
        for i in 1...6 { a.append(attempt("v\(i)", "te", .wrong, daysAgo: i)) }
        a.append(attempt("ok", "te", .correct))
        let w = progress(a).weakestVerbs
        XCTAssertEqual(w.count, 5)
        XCTAssertEqual(w[0], WeakVerb(verb: "x", weakness: 2.0))
        XCTAssertEqual(w.map(\.verb), ["x", "v1", "v2", "v3", "v4"])
        XCTAssertFalse(w.contains { $0.verb == "ok" })
    }

    func testWeakestFormsAggregatesWithLabelsAndCaps() {
        let ids = QuizForm.all.prefix(7).map(\.id)
        var a = [attempt("a", ids[0], .wrong), attempt("b", ids[0], .wrong)]
        for (i, id) in ids.dropFirst().enumerated() { a.append(attempt("a", id, .wrong, daysAgo: i + 1)) }
        a.append(attempt("a", "te", .correct, daysAgo: 0))
        let f = progress(a).weakestForms
        XCTAssertEqual(f.count, 5)
        XCTAssertEqual(f[0].formID, ids[0])
        XCTAssertEqual(f[0].weakness, 2.0, accuracy: 1e-9)
        XCTAssertEqual(f[0].label, QuizForm.all.first { $0.id == ids[0] }!.label)
    }

    func testUnknownFormIDFallsBackToIDAsLabel() {
        let f = progress([attempt("a", "retired_form", .wrong)]).weakestForms
        XCTAssertEqual(f.first?.label, "retired_form")
    }

    func testHasHistory() {
        XCTAssertFalse(progress([]).hasHistory)
        XCTAssertTrue(progress([attempt(outcome: .timedOut)]).hasHistory)
    }

    func testEmptyHistoryEverythingEmpty() {
        let p = progress([])
        XCTAssertTrue(p.weakPairs.isEmpty)
        XCTAssertTrue(p.weakestVerbs.isEmpty)
        XCTAssertTrue(p.weakestForms.isEmpty)
        XCTAssertEqual(p.last7Days.count, 7)
        XCTAssertEqual(p.last7Days.map(\.answered), Array(repeating: 0, count: 7))
    }

    // MARK: time zones where local midnight is skipped

    /// America/Santiago springs forward at 00:00 on 2026-09-06, so that day starts at 01:00.
    func testStreakAndLast7DaysSurviveSkippedMidnight() {
        let cal = calendar("America/Santiago")
        let now = date(cal, 2026, 9, 6, 12)
        func a(_ d: Int) -> QuizAttempt {
            QuizAttempt(verb: "食べる", formID: "te", kind: .conjugate, outcome: .correct, date: date(cal, 2026, 9, d, 12))
        }
        let p = QuizProgress(attempts: [a(4), a(5), a(6)], calendar: cal, now: now)
        XCTAssertEqual(p.currentStreak, 3)
        XCTAssertEqual(p.bestStreak, 3)
        XCTAssertEqual(p.last7Days.map(\.answered), [0, 0, 0, 0, 1, 1, 1])
        for d in p.last7Days { XCTAssertEqual(d.day, cal.startOfDay(for: d.day)) }
    }

    // MARK: attempts before the start of a day

    func testBeforeStartOfDayKeepsYesterdayEveningAndDropsToday() {
        let cal = calendar("Europe/Copenhagen")
        func a(_ d: Int, _ h: Int, _ m: Int) -> QuizAttempt {
            QuizAttempt(verb: "食べる", formID: "te", kind: .conjugate, outcome: .wrong, date: date(cal, 2026, 6, d, h, m))
        }
        let late = a(14, 23, 59), early = a(15, 0, 1), midnight = a(15, 0, 0)
        let kept = [late, early, midnight].before(startOfDayOf: date(cal, 2026, 6, 15, 9), calendar: cal)
        XCTAssertEqual(kept, [late])
        // The midnight entry (date = midnight) sees yesterday's whole history.
        XCTAssertEqual([late, early].before(startOfDayOf: midnight.date, calendar: cal), [late])
    }
}
