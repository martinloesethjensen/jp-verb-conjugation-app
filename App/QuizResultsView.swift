import SwiftUI
import VerbKit

/// The verb quiz's results: the score stamped in red, then only the answers marked wrong, each
/// with what was chosen (or that time ran out) and the correct answer, and the actions pinned
/// at the bottom.
struct QuizResultsView: View {
    var viewModel: QuizViewModel
    /// The quiz's topic, shown beside the percentage ("80% correct · て-form").
    var topicTitle: String
    var onDone: () -> Void
    /// Starts a new quiz from the questions that were missed.
    var onPractiseMissed: ([QuizQuestion]) -> Void
    @Environment(\.palette) private var palette
    @Environment(QuizHistoryStore.self) private var quizHistory

    private var percentage: Int {
        guard !viewModel.questions.isEmpty else { return 0 }
        return Int((Double(viewModel.score) / Double(viewModel.questions.count) * 100).rounded())
    }

    private var lines: [String] {
        var lines = ["\(percentage)% correct · \(topicTitle)"]
        let streak = QuizProgress(attempts: quizHistory.attempts).currentStreak
        if streak > 0 {
            lines.append("Streak: \(streak) \(streak == 1 ? "day" : "days")")
        }
        return lines
    }

    var body: some View {
        let missed = viewModel.missed
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                QuizScoreCard(score: viewModel.score, count: viewModel.questions.count, lines: lines)
                if !missed.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Marked wrong")
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(missed.enumerated()), id: \.offset) { index, pair in
                                if index > 0 { Divider().overlay(palette.rule) }
                                missedRow(pair.question, pair.result)
                            }
                        }
                        .paperCard()
                    }
                }
            }
            .padding()
        }
        .paperBackground()
        .quizResultsActions(
            practise: missed.isEmpty ? nil : "Practise the \(missed.count) missed",
            onPractise: { onPractiseMissed(viewModel.missedQuestions) },
            onDone: onDone
        )
    }

    private func missedRow(_ question: QuizQuestion, _ result: QuizResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                JapaneseText(units: question.verb.dictionaryUnits)
                    .font(.headword(.title3))
                    .foregroundStyle(palette.ink)
                // Identify rows ask for the label, so the heading shows the form's string.
                Text(" — " + (result.kind == .identify ? result.formString : result.formLabel))
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            }
            WrappingFlowLayout(spacing: 8) {
                if result.timedOut {
                    Text("TIME’S UP")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.mark)
                } else {
                    Text("YOU CHOSE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(palette.mark)
                    Text(result.chosen)
                        .strikethrough(color: palette.mark)
                        .foregroundStyle(palette.ink)
                }
                Text("CORRECT")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.good)
                Text(result.correct)
                    .bold()
                    .foregroundStyle(palette.ink)
            }
            if let why = result.errorExplanation {
                Text(why)
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
