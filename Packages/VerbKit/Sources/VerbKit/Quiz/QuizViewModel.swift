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

    public init(questions: [QuizQuestion]) {
        self.questions = questions
    }

    public func choose(_ choice: String) {
        guard !isAnswered, let question = currentQuestion else { return }
        selected = choice
        let ok = choice == question.correct
        if ok { score += 1 }
        results.append(QuizResult(verb: question.verb.dict, form: question.form, correct: question.correct, chosen: choice, ok: ok))
    }

    /// Matches the web app: a timeout flips `timedOut` but does not
    /// append a `QuizResult` — the end-of-quiz breakdown silently omits
    /// timed-out questions there, and this ports that faithfully.
    public func markTimedOut() {
        guard !isAnswered else { return }
        timedOut = true
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
