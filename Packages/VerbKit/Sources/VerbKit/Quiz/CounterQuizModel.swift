import Foundation
import Observation

/// Runs a counter quiz one question at a time. It has no timer, like the connection quiz. A choice
/// is right when it is any accepted answer (八本 reads はっぽん or はちほん). Each answer goes into
/// quiz history as a `.counterChoice`, `.counterReading` or `.counterAsk` attempt: the counter in `subject`, and
/// the thing's word or the number key in `formID`.
@Observable
public final class CounterQuizModel {
    public let questions: [CounterQuestion]
    public private(set) var index = 0
    public private(set) var selected: String?
    public private(set) var score = 0
    public private(set) var finished = false
    /// Whether each answered question was right, in order.
    private var outcomes: [Bool] = []

    private let recorder: ((QuizAttempt) -> Void)?
    private let now: () -> Date

    public init(
        questions: [CounterQuestion],
        recorder: ((QuizAttempt) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.questions = questions
        self.recorder = recorder
        self.now = now
    }

    public var currentQuestion: CounterQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    public var isAnswered: Bool { selected != nil }

    public func choose(_ choice: String) {
        guard !isAnswered, let question = currentQuestion else { return }
        selected = choice
        let ok = question.accepted.contains(choice)
        if ok { score += 1 }
        outcomes.append(ok)
        recorder?(QuizAttempt(
            subject: question.counterID, formID: question.formID, kind: question.kind,
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
    public var missedQuestions: [CounterQuestion] {
        zip(questions, outcomes).filter { !$0.1 }.map { question, _ in
            var again = question
            again.choices.shuffle()
            return again
        }
    }
}
