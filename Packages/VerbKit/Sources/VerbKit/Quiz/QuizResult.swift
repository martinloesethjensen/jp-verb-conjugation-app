public struct QuizResult: Equatable, Sendable {
    public var verb: String
    public var formLabel: String
    public var formString: String
    public var kind: QuizQuestionKind
    public var correct: String
    public var chosen: String
    public var ok: Bool

    public init(
        verb: String, formLabel: String, formString: String, kind: QuizQuestionKind,
        correct: String, chosen: String, ok: Bool
    ) {
        self.verb = verb
        self.formLabel = formLabel
        self.formString = formString
        self.kind = kind
        self.correct = correct
        self.chosen = chosen
        self.ok = ok
    }
}
