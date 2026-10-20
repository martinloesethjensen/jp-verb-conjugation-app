import Foundation

public enum QuizOutcome: String, Sendable, Codable {
    case correct, wrong, timedOut

    /// A wrong answer or a timeout.
    public var isMiss: Bool { self != .correct }
    /// Only answered attempts count toward accuracy, answers per day and the streak.
    public var isAnswered: Bool { self != .timedOut }
}

public struct QuizAttempt: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// A `Verb.id` for a verb question, a `Counter.id` for a counter question.
    public var subject: String
    public var formID: String
    public var kind: QuizQuestionKind
    public var outcome: QuizOutcome
    public var date: Date

    public init(
        id: UUID = UUID(), subject: String, formID: String,
        kind: QuizQuestionKind, outcome: QuizOutcome, date: Date
    ) {
        self.id = id
        self.subject = subject
        self.formID = formID
        self.kind = kind
        self.outcome = outcome
        self.date = date
    }
}

public extension Sequence where Element == QuizAttempt {
    /// Attempts dated before the start of `date`'s day. A widget uses this so a day's
    /// weak-verb pool stays fixed while the day's quizzes are recorded.
    func before(startOfDayOf date: Date, calendar: Calendar = .current) -> [QuizAttempt] {
        let cutoff = calendar.startOfDay(for: date)
        return filter { $0.date < cutoff }
    }
}
