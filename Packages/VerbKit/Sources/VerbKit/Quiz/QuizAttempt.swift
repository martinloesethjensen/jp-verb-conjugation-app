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
    public var verb: String
    public var formID: String
    public var kind: QuizQuestionKind
    public var outcome: QuizOutcome
    public var date: Date

    public init(
        id: UUID = UUID(), verb: String, formID: String,
        kind: QuizQuestionKind, outcome: QuizOutcome, date: Date
    ) {
        self.id = id
        self.verb = verb
        self.formID = formID
        self.kind = kind
        self.outcome = outcome
        self.date = date
    }
}
