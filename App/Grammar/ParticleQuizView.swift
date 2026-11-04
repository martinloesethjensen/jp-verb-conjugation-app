import SwiftUI
import VerbKit
import WidgetKit

/// Particles: an example sentence with one marked particle blanked, pick the particle. Built only
/// from the blanks the data marks (`particle_blanks`). No timer. After each answer the whole
/// sentence shows with the right particle named, and a link to the lesson or verb it comes from.
struct ParticleQuizView: View {
    @Environment(\.openRoute) private var openRoute
    @State private var model: ParticleQuizModel
    @State private var confirmingQuit = false
    private let recorder: (QuizAttempt) -> Void
    var onDone: () -> Void

    init(questions: [ParticleQuestion], recorder: @escaping (QuizAttempt) -> Void, onDone: @escaping () -> Void) {
        _model = State(initialValue: ParticleQuizModel(questions: questions, recorder: recorder))
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

    private func questionScreen(_ question: ParticleQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                QuizHeader(index: model.index, count: model.questions.count, score: model.score) {
                    confirmingQuit = true
                }
                prompt(question)
                QuizChoiceGrid(
                    choices: question.choices, isCorrect: question.isCorrect,
                    selected: model.selected, isAnswered: model.isAnswered, onChoose: model.choose
                )
                .font(.title2.weight(.semibold))
                if model.isAnswered {
                    feedback(question)
                    source(question)
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

    private func prompt(_ question: ParticleQuestion) -> some View {
        QuizPromptCard(fillsWidth: true) {
            VStack(spacing: 12) {
                Text("Which particle fits?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                JapaneseText(question.blanked)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("\(question.before), blank, \(question.after)")
                Text(question.translation)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func feedback(_ question: ParticleQuestion) -> some View {
        let right = model.answeredCorrectly == true
        return QuizFeedbackCard(tone: right ? .correct : .wrong) {
            VStack(alignment: .leading, spacing: 8) {
                Label(right ? "Correct!" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline)
                Text(Self.answerLine(question, selected: model.selected, right: right))
                    .font(.subheadline.weight(.semibold))
                JapaneseText(question.sentence)
                    .font(.body)
                if !question.acceptAlso.isEmpty {
                    Text("\(question.acceptAlso.joined(separator: " or ")) also works here.")
                        .font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "The particle is に." after a right answer; after a wrong one, also what was picked.
    static func answerLine(_ question: ParticleQuestion, selected: String?, right: Bool) -> String {
        if right || selected == nil { return "The particle is \(question.particle)." }
        return "The particle is \(question.particle), not \(selected ?? "")."
    }

    /// Leaves the quiz for the page. Answers are already recorded, so nothing is lost.
    private func source(_ question: ParticleQuestion) -> some View {
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
            subtitle: missed.isEmpty ? "Every particle in its place." : "Worth another look:",
            hasMissed: !missed.isEmpty,
            onPractiseMissed: { model = ParticleQuizModel(questions: missed, recorder: recorder) },
            onDone: onDone
        ) {
            ForEach(Array(missed.enumerated()), id: \.offset) { _, question in
                QuizMissedCard {
                    VStack(alignment: .leading, spacing: 4) {
                        JapaneseText(question.sentence).font(.headline)
                        Text("\(question.particle) · \(question.translation)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
