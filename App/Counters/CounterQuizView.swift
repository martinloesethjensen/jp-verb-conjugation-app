import SwiftUI
import VerbKit
import WidgetKit

/// The counter quiz: pick a thing's counter, or a counted form's reading. No timer, like the
/// connection quiz. A wrong answer shows the pattern; the right reading can be heard.
struct CounterQuizView: View {
    @State private var model: CounterQuizModel
    @State private var confirmingQuit = false
    private let recorder: (QuizAttempt) -> Void
    var onDone: () -> Void

    init(questions: [CounterQuestion], recorder: @escaping (QuizAttempt) -> Void, onDone: @escaping () -> Void) {
        _model = State(initialValue: CounterQuizModel(questions: questions, recorder: recorder))
        self.recorder = recorder
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if model.finished {
                results
            } else if let question = model.currentQuestion {
                questionScreen(question)
            }
        }
        // The widgets read quiz history, which these answers add to.
        .onDisappear { WidgetCenter.shared.reloadAllTimelines() }
        .quizQuitDialog(isPresented: $confirmingQuit, onQuit: onDone)
    }

    private func questionScreen(_ question: CounterQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                QuizHeader(index: model.index, count: model.questions.count, score: model.score) {
                    confirmingQuit = true
                }
                prompt(question)
                QuizChoiceGrid(
                    choices: question.choices,
                    isCorrect: { question.accepted.contains($0) },
                    selected: model.selected,
                    isAnswered: model.isAnswered
                ) { choice in
                    model.choose(choice)
                }
                if model.isAnswered { feedback(question) }
            }
            .padding()
        }
        .quizAdvanceBar(
            isVisible: model.isAnswered,
            title: model.index + 1 >= model.questions.count ? "See Results" : "Next"
        ) {
            model.advance()
        }
    }

    private func header(for kind: QuizQuestionKind) -> String {
        switch kind {
        case .counterChoice: "Which counter?"
        case .counterAsk: "Which 何 phrase?"
        default: "How do you read it?"
        }
    }

    /// Plain `Text` throughout: the furigana dictionary would read 三本 as さん + ほん.
    private func prompt(_ question: CounterQuestion) -> some View {
        QuizPromptCard(fillsWidth: true) {
            VStack(spacing: 8) {
                Text(header(for: question.kind))
                    .font(.caption)
                if let symbol = question.symbol {
                    Image(systemName: symbol)
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
                if question.kind == .counterAsk {
                    // An English sentence, not a counted form: let it wrap.
                    Text(question.prompt)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                } else {
                    Text(question.prompt)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                Text(question.detail)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func feedback(_ question: CounterQuestion) -> some View {
        let right = model.selected.map(question.accepted.contains) ?? false
        return QuizFeedbackCard(tone: right ? .correct : .wrong) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(right ? "Correct!" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.headline)
                    Spacer()
                    if question.kind == .counterReading { SpeakButton(text: question.correct) }
                }
                // Ask it always shows the Japanese sentence, right or wrong: it is the answer's context.
                if !right || question.kind == .counterAsk {
                    Text(question.explanation)
                        .font(.subheadline)
                }
            }
        }
    }

    private var results: some View {
        let missed = model.missedQuestions
        return QuizResultsSummary(
            score: model.score,
            count: model.questions.count,
            subtitle: missed.isEmpty ? "Every counter in its place." : "Worth another look:",
            hasMissed: !missed.isEmpty,
            onPractiseMissed: { model = CounterQuizModel(questions: missed, recorder: recorder) },
            onDone: onDone
        ) {
            ForEach(Array(missed.enumerated()), id: \.offset) { _, question in
                QuizMissedCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(question.prompt)  \(question.correct)").font(.headline)
                        Text(question.explanation).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
