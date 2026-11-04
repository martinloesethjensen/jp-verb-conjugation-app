import Foundation
import Observation

/// Runs a particle quiz one question at a time. It has no timer, like the connection, counter and
/// Spot the mistake quizzes. Each answer goes into quiz history as a `.particle` attempt: the
/// blank's id ("<example id>#<n>") in `subject`, the right particle in `formID`, and for a wrong
/// answer the particle picked as a `wrong_particle:<particle>` error tag.
@Observable
public final class ParticleQuizModel {
    public let questions: [ParticleQuestion]
    public private(set) var index = 0
    public private(set) var selected: String?
    public private(set) var score = 0
    public private(set) var finished = false
    /// Whether each answered question was right, in order.
    private var outcomes: [Bool] = []

    private let recorder: ((QuizAttempt) -> Void)?
    private let now: () -> Date

    public init(
        questions: [ParticleQuestion],
        recorder: ((QuizAttempt) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.questions = questions
        self.recorder = recorder
        self.now = now
    }

    public var currentQuestion: ParticleQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    public var isAnswered: Bool { selected != nil }

    /// Whether the chosen particle was right; nil before answering.
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
        recorder?(QuizAttempt(
            subject: question.blankID, formID: question.particle, kind: .particle,
            outcome: ok ? .correct : .wrong, date: now(), errorTag: ok ? nil : .wrongParticle(choice)
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
    public var missedQuestions: [ParticleQuestion] {
        zip(questions, outcomes).filter { !$0.1 }.map { question, _ in
            var again = question
            again.choices.shuffle()
            return again
        }
    }
}
