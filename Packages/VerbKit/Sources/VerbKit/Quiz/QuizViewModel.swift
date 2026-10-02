import Foundation
import Observation

@Observable
public final class QuizViewModel {
    public let questions: [QuizQuestion]
    public private(set) var index = 0
    public private(set) var selected: String?
    public private(set) var score = 0
    public private(set) var results: [QuizResult] = []
    public private(set) var timedOut = false
    public private(set) var timeLeft = 20
    public private(set) var finished = false

    public var currentQuestion: QuizQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    public var isAnswered: Bool { selected != nil || timedOut }

    private let recorder: ((QuizAttempt) -> Void)?
    private let now: () -> Date

    /// `recorder` is called once per answered or timed-out question.
    public init(
        questions: [QuizQuestion],
        recorder: ((QuizAttempt) -> Void)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.questions = questions
        self.recorder = recorder
        self.now = now
    }

    private func record(_ question: QuizQuestion, _ outcome: QuizOutcome) {
        recorder?(QuizAttempt(
            verb: question.verb.dict, formID: question.form.id, kind: question.kind,
            outcome: outcome, date: now()
        ))
    }

    public func choose(_ choice: String) {
        guard !isAnswered, let question = currentQuestion else { return }
        selected = choice
        let ok = choice == question.correct
        if ok { score += 1 }
        results.append(QuizResult(
            verb: question.verb.dict, formLabel: question.form.label, formID: question.form.id, formString: question.formString,
            kind: question.kind, correct: question.correct, chosen: choice, ok: ok
        ))
        record(question, ok ? .correct : .wrong)
    }

    /// A timeout counts as a miss and is recorded, so the results screen lists it
    /// (the web app omitted timed-out questions from its breakdown).
    public func markTimedOut() {
        guard !isAnswered, let question = currentQuestion else { return }
        timedOut = true
        results.append(QuizResult(
            verb: question.verb.dict, formLabel: question.form.label, formID: question.form.id, formString: question.formString,
            kind: question.kind, correct: question.correct, chosen: "", ok: false, timedOut: true
        ))
        record(question, .timedOut)
    }

    /// The questions answered wrongly or timed out, with fresh choice order, for
    /// "Practise missed". Meaningful once the quiz has finished, when every question
    /// has exactly one result in order.
    public var missedQuestions: [QuizQuestion] {
        zip(questions, results).filter { !$0.1.ok }.map { question, _ in
            var again = question
            again.choices.shuffle()
            return again
        }
    }

    public func advance() {
        guard isAnswered else { return }
        if index + 1 >= questions.count {
            finished = true
        } else {
            index += 1
            selected = nil
            timedOut = false
            timeLeft = 20
        }
    }

    public func tickTimer() {
        guard !isAnswered else { return }
        if timeLeft <= 1 {
            timeLeft = 0
            markTimedOut()
        } else {
            timeLeft -= 1
        }
    }
}
