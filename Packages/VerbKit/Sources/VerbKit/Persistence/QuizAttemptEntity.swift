import Foundation
import SwiftData

/// One answered or timed-out quiz question. A new table, so adding it to the
/// schema is a lightweight migration for existing stores.
@Model
public final class QuizAttemptEntity {
    public var id: UUID
    /// Named `verb` before counters existed; the original name keeps old stores migrating in place.
    @Attribute(originalName: "verb") public var subject: String
    public var formID: String
    public var kindRaw: String
    public var outcomeRaw: String
    public var date: Date

    public init(id: UUID, subject: String, formID: String, kindRaw: String, outcomeRaw: String, date: Date) {
        self.id = id
        self.subject = subject
        self.formID = formID
        self.kindRaw = kindRaw
        self.outcomeRaw = outcomeRaw
        self.date = date
    }

    public convenience init(_ attempt: QuizAttempt) {
        self.init(
            id: attempt.id, subject: attempt.subject, formID: attempt.formID,
            kindRaw: attempt.kind.rawValue, outcomeRaw: attempt.outcome.rawValue, date: attempt.date
        )
    }

    /// `nil` if the raw kind/outcome isn't known to this build; callers skip such rows.
    public func toAttempt() -> QuizAttempt? {
        guard let kind = QuizQuestionKind(rawValue: kindRaw),
              let outcome = QuizOutcome(rawValue: outcomeRaw) else { return nil }
        return QuizAttempt(id: id, subject: subject, formID: formID, kind: kind, outcome: outcome, date: date)
    }
}
