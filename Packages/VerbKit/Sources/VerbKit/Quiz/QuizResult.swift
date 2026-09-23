public struct QuizResult: Equatable, Sendable {
    public var verb: String
    public var form: FormKey
    public var correct: String
    public var chosen: String
    public var ok: Bool

    public init(verb: String, form: FormKey, correct: String, chosen: String, ok: Bool) {
        self.verb = verb
        self.form = form
        self.correct = correct
        self.chosen = chosen
        self.ok = ok
    }
}
