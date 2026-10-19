import Foundation
import Observation

/// Runs a connection quiz one question at a time. It has no timer, because building the
/// form takes thought. Each answer goes into quiz history as a `.connect` attempt: the
/// word in `verb` and the pattern and slot in `formID`.
@Observable
public final class ConnectionQuizModel {
    public let questions: [ConnectionQuestion]
    public private(set) var index = 0
    public private(set) var selected: String?
    public private(set) var score = 0
    public private(set) var finished = false
    /// Whether each answered question was right, in order.
    private var outcomes: [Bool] = []

    private let recorder: ((QuizAttempt) -> Void)?
    private let now: () -> Date

    public init(
        questions: [ConnectionQuestion],
        recorder: ((QuizAttempt) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.questions = questions
        self.recorder = recorder
        self.now = now
    }

    public var currentQuestion: ConnectionQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    public var isAnswered: Bool { selected != nil }

    public func choose(_ choice: String) {
        guard !isAnswered, let question = currentQuestion else { return }
        selected = choice
        let ok = choice == question.correct
        if ok { score += 1 }
        outcomes.append(ok)
        recorder?(QuizAttempt(
            verb: question.wordID, formID: question.attemptFormID, kind: .connect,
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
    public var missedQuestions: [ConnectionQuestion] {
        zip(questions, outcomes).filter { !$0.1 }.map { question, _ in
            var again = question
            again.choices.shuffle()
            return again
        }
    }
}
