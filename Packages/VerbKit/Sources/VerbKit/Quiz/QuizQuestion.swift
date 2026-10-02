public enum QuizQuestionKind: String, CaseIterable, Sendable {
    /// Given a verb and a form's name, pick the conjugated string.
    case conjugate
    /// Given a conjugated string, pick the name of its form.
    case identify
    /// Given an example sentence with the verb blanked, pick the form that fits.
    case fillIn
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
    /// For `.fillIn`: the example sentence with the form replaced by `blank`.
    public var sentence: String?
    /// For `.fillIn`: the English translation of the sentence.
    public var translation: String?

    /// What stands in for the verb in a fill-in sentence.
    public static let blank = "＿＿＿"

    public init(
        verb: Verb, form: QuizForm, kind: QuizQuestionKind,
        formString: String, correct: String, choices: [String],
        sentence: String? = nil, translation: String? = nil
    ) {
        self.sentence = sentence
        self.translation = translation
        self.verb = verb
        self.form = form
        self.kind = kind
        self.formString = formString
        self.correct = correct
        self.choices = choices
    }
}
