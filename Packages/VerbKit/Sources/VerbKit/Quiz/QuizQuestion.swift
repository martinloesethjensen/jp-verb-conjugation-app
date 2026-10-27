public enum QuizQuestionKind: String, CaseIterable, Codable, Sendable {
    /// Given a verb and a form's name, pick the conjugated string.
    case conjugate
    /// Given a conjugated string, pick the name of its form.
    case identify
    /// Given an example sentence with the verb blanked, pick the form that fits.
    case fillIn
    /// A connection question (しずか + ので → しずかなので). Only recorded in quiz history:
    /// connection questions have their own screen, and `buildQuestions` never makes one.
    case connect
    /// A counter question: given a thing (傘), pick its counter (本). Only recorded in quiz
    /// history, with the thing's word as the form id: counter questions have their own screen.
    case counterChoice
    /// A counter question: given a counted form (三本), pick its reading. Only recorded in quiz
    /// history, with the number key ("3", "what") as the form id.
    case counterReading
    /// A counter question: given an English question (How many people are there?), pick the 何
    /// phrase that asks it (何人). Only recorded in quiz history, with the Japanese sentence as the
    /// form id. Builds on old kinds' history: an older app build skips an attempt of this kind.
    case counterAsk
    /// A Spot the mistake question: pick the wrong form among correct ones, built from a Common
    /// mistakes pitfall. Only recorded in quiz history, with the pitfall's id ("node#0",
    /// "counter:hon#0") as the subject. Builds on old kinds' history: an older app build skips an
    /// attempt of this kind. It is neither a verb question nor a counter question.
    case spotMistake

    /// A counter question, which verb code (the verb quiz, weak spots, the widget) never handles.
    public var isCounter: Bool { self == .counterChoice || self == .counterReading || self == .counterAsk }

    /// A kind about a verb and a form: the only kind that makes weak verb spots.
    public var isVerbQuestion: Bool { Self.verbKinds.contains(self) }

    /// The kinds the verb quiz may build. `allCases` also holds kinds with their own screens.
    public static let verbKinds: [QuizQuestionKind] = [.conjugate, .identify, .fillIn]
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
    /// The mistake each wrong choice represents. Every wrong choice a generator makes is here.
    public var errors: [String: QuizErrorTag]
    /// For `.fillIn`: the example sentence with the form replaced by `blank`.
    public var sentence: String?
    /// For `.fillIn`: the English translation of the sentence.
    public var translation: String?

    /// What stands in for the verb in a fill-in sentence.
    public static let blank = "＿＿＿"

    public init(
        verb: Verb, form: QuizForm, kind: QuizQuestionKind,
        formString: String, correct: String, choices: [String],
        errors: [String: QuizErrorTag] = [:],
        sentence: String? = nil, translation: String? = nil
    ) {
        self.errors = errors
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
