public enum QuizQuestionKind: Sendable {
    /// Given a verb and a form's name, pick the conjugated string.
    case conjugate
    /// Given a conjugated string, pick the name of its form.
    case identify
}

public struct QuizQuestion: Equatable, Sendable {
    public var verb: Verb
    public var form: QuizForm
    public var kind: QuizQuestionKind
    /// The form's string for this verb, e.g. たべられました.
    public var formString: String
    /// The right choice: the string for `.conjugate`, the label for `.identify`.
    public var correct: String
    public var choices: [String]

    public init(
        verb: Verb, form: QuizForm, kind: QuizQuestionKind,
        formString: String, correct: String, choices: [String]
    ) {
        self.verb = verb
        self.form = form
        self.kind = kind
        self.formString = formString
        self.correct = correct
        self.choices = choices
    }
}
