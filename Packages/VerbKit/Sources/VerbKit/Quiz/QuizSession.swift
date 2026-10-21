import Foundation

/// Where a running quiz is: the part of `QuizViewModel` that changes as it is answered.
public struct QuizProgressState: Codable, Equatable, Sendable {
    public var index: Int
    /// The chosen answer when the current question is answered and not yet advanced past.
    public var selected: String?
    public var timedOut: Bool
    public var timeLeft: Int
    public var score: Int
    public var results: [QuizResult]

    public init(
        index: Int = 0, selected: String? = nil, timedOut: Bool = false,
        timeLeft: Int = 20, score: Int = 0, results: [QuizResult] = []
    ) {
        self.index = index
        self.selected = selected
        self.timedOut = timedOut
        self.timeLeft = timeLeft
        self.score = score
        self.results = results
    }
}

/// What a saved quiz was practising, for the Resume row.
public enum QuizSessionTopic: Codable, Equatable, Sendable {
    case topics([QuizTopic])
    case weakSpots

    public var title: String {
        switch self {
        case .weakSpots: return "Weak spots"
        case .topics(let topics) where topics.count == 1: return topics[0].title
        case .topics: return "Everything"
        }
    }
}

/// A running verb quiz, saved after each answer so it survives the app being killed or a
/// link opening another page (issue #38). Questions are kept by verb and form id, with the
/// strings they showed, and are checked against the current data when restored: a verb or
/// form that has gone or changed means the quiz cannot be resumed.
public struct QuizSession: Codable, Equatable, Sendable {
    /// Bumped when the stored shape changes; an older session is dropped, not migrated.
    public static let currentVersion = 1

    public struct Question: Codable, Equatable, Sendable {
        public var verb: String
        public var formID: String
        public var kind: QuizQuestionKind
        public var formString: String
        public var correct: String
        public var choices: [String]
        public var sentence: String?
        public var translation: String?

        public init(_ question: QuizQuestion) {
            verb = question.verb.id
            formID = question.form.id
            kind = question.kind
            formString = question.formString
            correct = question.correct
            choices = question.choices
            sentence = question.sentence
            translation = question.translation
        }
    }

    public var version: Int
    public var topic: QuizSessionTopic
    /// `QuizForm.catalogueFingerprint` when saved: a changed form set drops the session.
    public var catalogue: String
    public var questions: [Question]
    public var progress: QuizProgressState
    public var savedAt: Date

    public init(topic: QuizSessionTopic, questions: [QuizQuestion], progress: QuizProgressState, savedAt: Date) {
        self.version = Self.currentVersion
        self.topic = topic
        self.catalogue = QuizForm.catalogueFingerprint
        self.questions = questions.map(Question.init)
        self.progress = progress
        self.savedAt = savedAt
    }

    /// The quiz to pick up again, or nil when there is nothing left to answer or it no longer
    /// fits the data: another version, another form set, a verb or form gone, or a form whose
    /// string or label has changed. `verbs` should be every verb, not only the visible ones.
    public func restore(verbs: [Verb]) -> (questions: [QuizQuestion], progress: QuizProgressState)? {
        guard version == Self.currentVersion, catalogue == QuizForm.catalogueFingerprint else { return nil }
        guard isConsistent else { return nil }
        let verbsByID = Dictionary(verbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let formsByID = Dictionary(QuizForm.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var restored: [QuizQuestion] = []
        for saved in questions {
            guard QuizQuestionKind.verbKinds.contains(saved.kind),
                  let verb = verbsByID[saved.verb], let form = formsByID[saved.formID],
                  form.value(in: verb.forms) == saved.formString,
                  saved.correct == (saved.kind == .identify ? form.label : saved.formString),
                  saved.choices.contains(saved.correct)
            else { return nil }
            restored.append(QuizQuestion(
                verb: verb, form: form, kind: saved.kind, formString: saved.formString,
                correct: saved.correct, choices: saved.choices,
                sentence: saved.sentence, translation: saved.translation
            ))
        }
        return (restored, progress)
    }

    /// The progress could have come from these questions: one result per question before the
    /// current one, plus one when it is answered (the last one answered still has its results
    /// screen to show).
    private var isConsistent: Bool {
        let p = progress
        guard questions.indices.contains(p.index), (0...20).contains(p.timeLeft) else { return false }
        let answered = p.selected != nil || p.timedOut
        return p.results.count == p.index + (answered ? 1 : 0)
            && p.score == p.results.filter(\.ok).count
    }

    /// "3 of 10 answered · 2 correct", for the Resume row.
    public var summary: String {
        "\(progress.results.count) of \(questions.count) answered · \(progress.score) correct"
    }
}

extension QuizForm {
    /// Identifies the form set (ids, topics and labels, in order), so a saved quiz made with
    /// another catalogue is not resumed with mismatched labels.
    public static let catalogueFingerprint: String = sha256Hex(of: Data(
        all.map { "\($0.id)|\($0.topic.rawValue)|\($0.label)" }.joined(separator: "\n").utf8
    ))
}
