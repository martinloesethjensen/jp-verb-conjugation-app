import Foundation
import SwiftData

/// One answered or timed-out quiz question. A new table, so adding it to the
/// schema is a lightweight migration for existing stores.
@Model
public final class QuizAttemptEntity {
    public var id: UUID
    public var verb: String
    public var formID: String
    public var kindRaw: String
    public var outcomeRaw: String
    public var date: Date

    public init(id: UUID, verb: String, formID: String, kindRaw: String, outcomeRaw: String, date: Date) {
        self.id = id
        self.verb = verb
        self.formID = formID
        self.kindRaw = kindRaw
        self.outcomeRaw = outcomeRaw
        self.date = date
    }

    public convenience init(_ attempt: QuizAttempt) {
        self.init(
            id: attempt.id, verb: attempt.verb, formID: attempt.formID,
            kindRaw: attempt.kind.rawValue, outcomeRaw: attempt.outcome.rawValue, date: attempt.date
        )
    }

    /// `nil` if the raw kind/outcome isn't known to this build; callers skip such rows.
    public func toAttempt() -> QuizAttempt? {
        guard let kind = QuizQuestionKind(rawValue: kindRaw),
              let outcome = QuizOutcome(rawValue: outcomeRaw) else { return nil }
        return QuizAttempt(id: id, verb: verb, formID: formID, kind: kind, outcome: outcome, date: date)
    }
}
