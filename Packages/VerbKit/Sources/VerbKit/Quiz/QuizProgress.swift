import Foundation

public struct WeakPair: Equatable, Sendable {
    public let verb: String
    public let formID: String
    public let weakness: Double
}

public struct DayCount: Equatable, Sendable {
    /// Start of the day in the progress's calendar.
    public let day: Date
    public let answered: Int
}

public struct WeakVerb: Equatable, Sendable {
    public let verb: String
    public let weakness: Double
}

public struct WeakForm: Equatable, Sendable {
    public let formID: String
    public let label: String
    public let weakness: Double
}

/// Weakness, streaks and statistics derived from the quiz history. Pure: no I/O;
/// the calendar and "now" are injected.
///
/// Weakness of a (verb, form) pair: its most recent 5 attempts, newest first, get
/// weights 5, 4, 3, 2, 1; weakness = weight of misses (wrong or timed out) / weight
/// of all attempts in the window. A pair is weak when weakness > 0.
/// - A pair with fewer than 5 attempts uses all of them, weights 5, 4, 3... from newest.
/// - Attempts are ordered by date; attempts with identical dates keep input order,
///   the later one in `attempts` counting as newer (the store appends chronologically).
/// - Ranking: weakness descending, then newest attempt date descending, then verb and
///   form id ascending.
///
/// Streak: a calendar day counts when it has at least one answered (correct or wrong)
/// attempt. The current streak ends today, or yesterday when today has none yet.
/// Attempts dated after `now` never extend the current streak (it is anchored on
/// today/yesterday) but still count toward the best streak.
public struct QuizProgress: Sendable {
    private static let window = 5


    public let weakPairs: [WeakPair]
    public let currentStreak: Int
    public let bestStreak: Int
    public let totalAnswered: Int
    public let accuracy: Double?
    public let last7Days: [DayCount]
    public let weakestVerbs: [WeakVerb]
    public let weakestForms: [WeakForm]
    public let hasHistory: Bool

    public init(attempts: [QuizAttempt], calendar: Calendar = .current, now: Date = Date()) {
        hasHistory = !attempts.isEmpty

        // Weakness.
        struct Key: Hashable { let verb: String; let formID: String }
        var byPair: [Key: [(attempt: QuizAttempt, index: Int)]] = [:]
        for (i, a) in attempts.enumerated() {
            byPair[Key(verb: a.verb, formID: a.formID), default: []].append((a, i))
        }
        var pairs: [(pair: WeakPair, newest: Date)] = []
        for (key, list) in byPair {
            let newestFirst = list.sorted {
                $0.attempt.date != $1.attempt.date ? $0.attempt.date > $1.attempt.date : $0.index > $1.index
            }.prefix(Self.window)
            var missWeight = 0, totalWeight = 0
            for (offset, entry) in newestFirst.enumerated() {
                let weight = Self.window - offset
                totalWeight += weight
                if entry.attempt.outcome.isMiss { missWeight += weight }
            }
            guard missWeight > 0 else { continue }
            pairs.append((
                WeakPair(verb: key.verb, formID: key.formID, weakness: Double(missWeight) / Double(totalWeight)),
                newestFirst[newestFirst.startIndex].attempt.date))
        }
        pairs.sort { a, b in
            if a.pair.weakness != b.pair.weakness { return a.pair.weakness > b.pair.weakness }
            if a.newest != b.newest { return a.newest > b.newest }
            if a.pair.verb != b.pair.verb { return a.pair.verb < b.pair.verb }
            return a.pair.formID < b.pair.formID
        }
        weakPairs = pairs.map(\.pair)

        // Answered counts per day, streaks, totals.
        let answered = attempts.filter { $0.outcome.isAnswered }
        totalAnswered = answered.count
        let correct = answered.filter { $0.outcome == .correct }.count
        accuracy = answered.isEmpty ? nil : Double(correct) / Double(answered.count)

        var perDay: [Date: Int] = [:]
        for a in answered { perDay[calendar.startOfDay(for: a.date), default: 0] += 1 }

        let sortedDays = perDay.keys.sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in sortedDays {
            if let p = previous, Self.shifted(p, by: 1, calendar) == day {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        bestStreak = best

        let today = calendar.startOfDay(for: now)
        var cursor: Date? = perDay[today] != nil ? today : Self.shifted(today, by: -1, calendar)
        var current = 0
        while let day = cursor, perDay[day] != nil {
            current += 1
            cursor = Self.shifted(day, by: -1, calendar)
        }
        currentStreak = current

        last7Days = (0..<7).reversed().compactMap { back in
            Self.shifted(today, by: -back, calendar).map {
                DayCount(day: $0, answered: perDay[$0] ?? 0)
            }
        }

        // Weakest verbs and forms.
        var verbSums: [String: Double] = [:]
        var formSums: [String: Double] = [:]
        for p in weakPairs {
            verbSums[p.verb, default: 0] += p.weakness
            formSums[p.formID, default: 0] += p.weakness
        }
        weakestVerbs = verbSums
            .map { WeakVerb(verb: $0.key, weakness: $0.value) }
            .sorted { $0.weakness != $1.weakness ? $0.weakness > $1.weakness : $0.verb < $1.verb }
            .prefix(5).map { $0 }
        let labels = Dictionary(QuizForm.all.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
        weakestForms = formSums
            .map { WeakForm(formID: $0.key, label: labels[$0.key] ?? $0.key, weakness: $0.value) }
            .sorted { $0.weakness != $1.weakness ? $0.weakness > $1.weakness : $0.formID < $1.formID }
            .prefix(5).map { $0 }
    }

    /// The start of the day `days` away from `day`. Re-anchored with `startOfDay` because
    /// in zones where a DST change skips local midnight, adding a day lands on 01:00.
    private static func shifted(_ day: Date, by days: Int, _ calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: day).map { calendar.startOfDay(for: $0) }
    }

    /// The weak pairs whose verb is in `verbs`, in the same order.
    public func weakPairs(among verbs: Set<String>) -> [WeakPair] {
        weakPairs.filter { verbs.contains($0.verb) }
    }
}
