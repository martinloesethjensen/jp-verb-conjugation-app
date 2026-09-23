public struct QuizQuestion: Equatable, Sendable {
    public var verb: Verb
    public var form: FormKey
    public var correct: String
    public var choices: [String]

    public init(verb: Verb, form: FormKey, correct: String, choices: [String]) {
        self.verb = verb
        self.form = form
        self.correct = correct
        self.choices = choices
    }
}
