import SwiftUI
import VerbKit
import WidgetKit

/// The connection quiz: a word plus a pattern's ending; pick the joined form. Every answer
/// shows the building block the pattern needed. No timer: building the form takes thought.
struct ConnectionQuizView: View {
    @State private var model: ConnectionQuizModel
    @State private var confirmingQuit = false
    private let recorder: (QuizAttempt) -> Void
    var onDone: () -> Void

    init(questions: [ConnectionQuestion], recorder: @escaping (QuizAttempt) -> Void, onDone: @escaping () -> Void) {
        _model = State(initialValue: ConnectionQuizModel(questions: questions, recorder: recorder))
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

    private func questionScreen(_ question: ConnectionQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                QuizHeader(index: model.index, count: model.questions.count, score: model.score) {
                    confirmingQuit = true
                }
                prompt(question)
                QuizChoiceGrid(
                    choices: question.choices,
                    isCorrect: { $0 == question.correct },
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

    private func prompt(_ question: ConnectionQuestion) -> some View {
        QuizPromptCard(fillsWidth: true) {
            VStack(spacing: 8) {
                Text("Join them with the right building block")
                    .font(.caption)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(question.word)
                    Image(systemName: "plus").font(.title2).foregroundStyle(.secondary)
                        .accessibilityLabel("plus")
                    Text(question.ending)
                }
                .font(.largeTitle.weight(.heavy))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                if let kanji = question.kanji {
                    JapaneseText(kanji).font(.title3).foregroundStyle(.secondary)
                }
                Text("\(question.wordClass.displayName) · \(question.meaning)")
                    .italic()
                    .foregroundStyle(.secondary)
                if let cue = question.cue.label {
                    Text(cue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
        }
    }

    private func feedback(_ question: ConnectionQuestion) -> some View {
        let right = model.selected == question.correct
        return QuizFeedbackCard(tone: right ? .correct : .wrong) {
            VStack(alignment: .leading, spacing: 6) {
                Label(right ? "Correct!" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline)
                Text(question.explanation)
                    .font(.subheadline)
            }
        }
    }

    private var results: some View {
        let missed = model.missedQuestions
        return QuizResultsSummary(
            score: model.score,
            count: model.questions.count,
            subtitle: missed.isEmpty ? "Every block in the right place." : "Worth another look:",
            hasMissed: !missed.isEmpty,
            onPractiseMissed: { model = ConnectionQuizModel(questions: missed, recorder: recorder) },
            onDone: onDone
        ) {
            ForEach(Array(missed.enumerated()), id: \.offset) { _, question in
                QuizMissedCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.correct).font(.headline)
                        Text(question.explanation).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
