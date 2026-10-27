import SwiftUI
import VerbKit
import WidgetKit

/// Spot the mistake: pick the wrong form among correct ones, built from the Common mistakes
/// pitfalls that have a wrong form. No timer. After each answer the pitfall's explanation shows,
/// with a link to the lesson or counter page it comes from.
struct SpotMistakeQuizView: View {
    @Environment(\.openRoute) private var openRoute
    @State private var model: SpotMistakeQuizModel
    @State private var confirmingQuit = false
    private let recorder: (QuizAttempt) -> Void
    var onDone: () -> Void

    init(questions: [SpotMistakeQuestion], recorder: @escaping (QuizAttempt) -> Void, onDone: @escaping () -> Void) {
        _model = State(initialValue: SpotMistakeQuizModel(questions: questions, recorder: recorder))
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

    private func questionScreen(_ question: SpotMistakeQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                QuizHeader(index: model.index, count: model.questions.count, score: model.score) {
                    confirmingQuit = true
                }
                prompt(question)
                // One column: the choices are phrases and sentences, which need the width at large text sizes.
                VStack(spacing: 12) {
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                        QuizChoiceButton(
                            choice: choice, index: index, isCorrect: choice == question.wrong,
                            isSelected: choice == model.selected, isAnswered: model.isAnswered,
                            lineLimit: nil
                        ) {
                            model.choose(choice)
                        }
                    }
                }
                if model.isAnswered {
                    feedback(question)
                    lesson(question)
                }
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

    private func prompt(_ question: SpotMistakeQuestion) -> some View {
        QuizPromptCard(fillsWidth: true) {
            VStack(spacing: 8) {
                Text(question.isReading ? "Which reading is wrong?" : "Which one is the mistake?")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("One of these is a mistake learners often make.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func feedback(_ question: SpotMistakeQuestion) -> some View {
        let right = model.selected == question.wrong
        return QuizFeedbackCard(tone: right ? .correct : .wrong) {
            VStack(alignment: .leading, spacing: 8) {
                Label(right ? "Correct!" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline)
                Text("The mistake: \(question.wrong)")
                    .font(.subheadline.weight(.semibold))
                Text(question.explanation)
                    .font(.subheadline)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Leaves the quiz for the page. Answers are already recorded, so nothing is lost.
    private func lesson(_ question: SpotMistakeQuestion) -> some View {
        Button {
            onDone()
            openRoute(question.source)
        } label: {
            Label("Open \(question.sourceTitle)", systemImage: "book")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityHint("Ends the quiz and opens the page")
    }

    private var results: some View {
        let missed = model.missedQuestions
        return QuizResultsSummary(
            score: model.score,
            count: model.questions.count,
            subtitle: missed.isEmpty ? "No mistake got past you." : "Worth another look:",
            hasMissed: !missed.isEmpty,
            onPractiseMissed: { model = SpotMistakeQuizModel(questions: missed, recorder: recorder) },
            onDone: onDone
        ) {
            ForEach(Array(missed.enumerated()), id: \.offset) { _, question in
                QuizMissedCard {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mistake: \(question.wrong)").font(.headline)
                        Text(question.explanation).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
