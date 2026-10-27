public struct QuizResult: Codable, Equatable, Sendable {
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
    /// The mistake the chosen wrong answer represented, and the one-line explanation of it.
    public var error: QuizErrorTag?
    public var errorExplanation: String?

    public init(
        verb: String, formLabel: String, formID: String, formString: String, kind: QuizQuestionKind,
        correct: String, chosen: String, ok: Bool, timedOut: Bool = false,
        error: QuizErrorTag? = nil, errorExplanation: String? = nil
    ) {
        self.error = error
        self.errorExplanation = errorExplanation
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
