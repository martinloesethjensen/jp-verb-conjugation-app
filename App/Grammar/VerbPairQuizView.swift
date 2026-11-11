import SwiftUI
import VerbKit
import WidgetKit

/// Verb pairs (#58): a pair phrase with its verb or its particle blanked, pick the half that fits
/// (会議が＿＿＿ → はじまる) or the particle (会議＿＿＿始める → を). No timer. After each answer both
/// phrases of the pair show side by side, with a link to the verb's page.
struct VerbPairQuizView: View {
    @Environment(\.openRoute) private var openRoute
    @State private var model: VerbPairQuizModel
    @State private var confirmingQuit = false
    private let recorder: (QuizAttempt) -> Void
    var onDone: () -> Void

    init(questions: [VerbPairQuestion], recorder: @escaping (QuizAttempt) -> Void, onDone: @escaping () -> Void) {
        _model = State(initialValue: VerbPairQuizModel(questions: questions, recorder: recorder))
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

    private func questionScreen(_ question: VerbPairQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                QuizHeader(index: model.index, count: model.questions.count, score: model.score) {
                    confirmingQuit = true
                }
                prompt(question)
                QuizChoiceGrid(
                    choices: question.choices, isCorrect: question.isCorrect,
                    selected: model.selected, isAnswered: model.isAnswered,
                    verb: question.choiceVerbs.isEmpty ? nil : { question.choiceVerbs[$0]! },
                    onChoose: model.choose
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

    private func prompt(_ question: VerbPairQuestion) -> some View {
        QuizPromptCard(fillsWidth: true) {
            VStack(spacing: 12) {
                Text(question.blank == .verb ? "Which verb fits?" : "Which particle fits?")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                JapaneseText(question.blanked)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("\(question.before), blank, \(question.after)")
                Text(question.gloss)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func feedback(_ question: VerbPairQuestion) -> some View {
        let right = model.answeredCorrectly == true
        return QuizFeedbackCard(tone: right ? .correct : .wrong) {
            VStack(alignment: .leading, spacing: 10) {
                Label(right ? "Correct!" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline)
                JapaneseText(Self.answerLine(question))
                    .font(.subheadline.weight(.semibold))
                ForEach(Self.halves(question), id: \.phrase) { half in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(half.transitivity.title) · \(half.transitivity.particle)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(half.transitivity.accessibilityTitle)
                        JapaneseText(half.phrase).font(.body)
                        Text(half.gloss).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Why the answer is right: "が goes with the intransitive verb, はじまる." for a verb blank,
    /// "始める is transitive, so it takes を." for a particle blank.
    static func answerLine(_ question: VerbPairQuestion) -> String {
        let kind = question.transitivity.title.lowercased()
        switch question.blank {
        case .verb:
            return "\(question.transitivity.particle) goes with the \(kind) verb, \(question.answer)."
        case .particle:
            return "\(question.after) is \(kind), so it takes \(question.answer)."
        }
    }

    /// Both phrases of the pair, the transitive one first.
    static func halves(_ question: VerbPairQuestion) -> [(transitivity: Transitivity, phrase: String, gloss: String)] {
        let this = (question.transitivity, question.phrase, question.gloss)
        let partnerSide: Transitivity = question.transitivity == .transitive ? .intransitive : .transitive
        let partner = (partnerSide, question.partnerPhrase, question.partnerGloss)
        return question.transitivity == .transitive ? [this, partner] : [partner, this]
    }

    /// Leaves the quiz for the verb's page. Answers are already recorded, so nothing is lost.
    private func source(_ question: VerbPairQuestion) -> some View {
        Button {
            onDone()
            openRoute(.verb(question.verbID))
        } label: {
            Label("Open \(question.verbTitle)", systemImage: "book")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.paperSecondary)
        .accessibilityHint("Ends the quiz and opens the page")
    }

    private var results: some View {
        let missed = model.missedQuestions
        return QuizResultsSummary(
            score: model.score,
            count: model.questions.count,
            subtitle: missed.isEmpty ? "Every pair in its place." : "Worth another look:",
            hasMissed: !missed.isEmpty,
            onPractiseMissed: { model = VerbPairQuizModel(questions: missed, recorder: recorder) },
            onDone: onDone
        ) {
            ForEach(Array(missed.enumerated()), id: \.offset) { _, question in
                QuizMissedCard {
                    // The prompt as asked, so a verb's two questions read apart.
                    VStack(alignment: .leading, spacing: 4) {
                        JapaneseText(question.blanked).font(.headline)
                        Text("\(question.answer) · \(question.gloss)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
