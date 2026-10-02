public struct QuizResult: Equatable, Sendable {
    public var verb: String
    public var formLabel: String
    public var formID: String
    public var formString: String
    public var kind: QuizQuestionKind
    public var correct: String
    public var chosen: String
    public var ok: Bool
    /// True when the 20 seconds ran out; `chosen` is then empty.
    public var timedOut: Bool

    public init(
        verb: String, formLabel: String, formID: String, formString: String, kind: QuizQuestionKind,
        correct: String, chosen: String, ok: Bool, timedOut: Bool = false
    ) {
        self.verb = verb
        self.formLabel = formLabel
        self.formID = formID
        self.formString = formString
        self.kind = kind
        self.correct = correct
        self.chosen = chosen
        self.ok = ok
        self.timedOut = timedOut
    }
}
