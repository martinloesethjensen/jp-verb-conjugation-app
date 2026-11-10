import Foundation
import Observation

/// Runs a verb pair quiz one question at a time, with no timer, like the particle quiz. Each answer
/// goes into quiz history as a `.verbPair` attempt: the verb's id in `subject`, what was blanked
/// ("verb" or "particle") in `formID`, and for a wrong answer the partner verb
/// (`other_verb:<partner id>`) or the particle picked (`wrong_particle:<particle>`) as the error tag.
@Observable
public final class VerbPairQuizModel {
    public let questions: [VerbPairQuestion]
    public private(set) var index = 0
    public private(set) var selected: String?
    public private(set) var score = 0
    public private(set) var finished = false
    /// Whether each answered question was right, in order.
    private var outcomes: [Bool] = []

    private let recorder: ((QuizAttempt) -> Void)?
    private let now: () -> Date

    public init(
        questions: [VerbPairQuestion],
        recorder: ((QuizAttempt) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.questions = questions
        self.recorder = recorder
        self.now = now
    }

    public var currentQuestion: VerbPairQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    public var isAnswered: Bool { selected != nil }

    /// Whether the choice was right; nil before answering.
    public var answeredCorrectly: Bool? {
        guard let selected, let question = currentQuestion else { return nil }
        return question.isCorrect(selected)
    }

    public func choose(_ choice: String) {
        guard !isAnswered, let question = currentQuestion else { return }
        selected = choice
        let ok = question.isCorrect(choice)
        if ok { score += 1 }
        outcomes.append(ok)
        let mistake: QuizErrorTag = switch question.blank {
        case .verb: .otherVerb(question.partnerID)
        case .particle: .wrongParticle(choice)
        }
        recorder?(QuizAttempt(
            subject: question.verbID, formID: question.blank.rawValue, kind: .verbPair,
            outcome: ok ? .correct : .wrong, date: now(), errorTag: ok ? nil : mistake
        ))
    }

    public func advance() {
        guard isAnswered else { return }
        if index + 1 >= questions.count {
            finished = true
        } else {
            index += 1
            selected = nil
        }
    }

    /// The questions answered wrongly, with the choices reshuffled, for "Practise missed".
    public var missedQuestions: [VerbPairQuestion] {
        zip(questions, outcomes).filter { !$0.1 }.map { question, _ in
            var again = question
            again.choices.shuffle()
            return again
        }
    }
}
