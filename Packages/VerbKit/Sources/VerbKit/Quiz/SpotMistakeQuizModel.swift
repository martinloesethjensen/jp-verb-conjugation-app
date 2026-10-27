import Foundation
import Observation

/// Runs a *Spot the mistake* quiz one question at a time. It has no timer, like the connection and
/// counter quizzes. A choice is right when it is the pitfall's wrong form. Each answer goes into quiz
/// history as a `.spotMistake` attempt: the pitfall's id (`CommonMistake.id`) in `subject`.
@Observable
public final class SpotMistakeQuizModel {
    /// What `QuizAttempt.formID` holds for every spot-the-mistake attempt.
    public static let attemptFormID = "wrong"

    public let questions: [SpotMistakeQuestion]
    public private(set) var index = 0
    public private(set) var selected: String?
    public private(set) var score = 0
    public private(set) var finished = false
    /// Whether each answered question was right, in order.
    private var outcomes: [Bool] = []

    private let recorder: ((QuizAttempt) -> Void)?
    private let now: () -> Date

    public init(
        questions: [SpotMistakeQuestion],
        recorder: ((QuizAttempt) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.questions = questions
        self.recorder = recorder
        self.now = now
    }

    public var currentQuestion: SpotMistakeQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    public var isAnswered: Bool { selected != nil }

    public func choose(_ choice: String) {
        guard !isAnswered, let question = currentQuestion else { return }
        selected = choice
        let ok = choice == question.wrong
        if ok { score += 1 }
        outcomes.append(ok)
        recorder?(QuizAttempt(
            subject: question.mistakeID, formID: Self.attemptFormID, kind: .spotMistake,
            outcome: ok ? .correct : .wrong, date: now()
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
    public var missedQuestions: [SpotMistakeQuestion] {
        zip(questions, outcomes).filter { !$0.1 }.map { question, _ in
            var again = question
            again.choices.shuffle()
            return again
        }
    }
}
