import SwiftUI
import VerbKit

struct QuizResultsView: View {
    var viewModel: QuizViewModel
    var onDone: () -> Void
    /// Starts a new quiz from the questions that were missed.
    var onPractiseMissed: ([QuizQuestion]) -> Void

    private var percentage: Int {
        guard !viewModel.questions.isEmpty else { return 0 }
        return Int((Double(viewModel.score) / Double(viewModel.questions.count) * 100).rounded())
    }

    @ScaledMetric(relativeTo: .largeTitle) private var emojiSize: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize: CGFloat = 44

    private var emoji: String {
        switch percentage {
        case 100: return "🏆"
        case 80...: return "🌟"
        case 60...: return "👍"
        case 40...: return "📚"
        default: return "💪"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(emoji).font(.system(size: emojiSize))
                Text("Quiz Complete!").font(.title2.weight(.bold))
                Text("\(viewModel.score)/\(viewModel.questions.count)")
                    .font(.system(size: scoreSize, weight: .heavy))
                    .foregroundStyle(percentage >= 60 ? .green : .orange)
                Text("\(percentage)% correct").foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.offset) { index, result in
                        if index > 0 { Divider() }
                        resultRow(result)
                    }
                }
                .glassEffect(in: RoundedRectangle(cornerRadius: 16))

                let missed = viewModel.missedQuestions
                if !missed.isEmpty {
                    Button("Practise missed (\(missed.count))") { onPractiseMissed(missed) }
                        .buttonStyle(.glassProminent)
                }
                Button("Done", action: onDone)
                    .buttonStyle(.glass)
            }
            .padding()
        }
    }

    private func resultRow(_ result: QuizResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(result.timedOut ? "⏰" : (result.ok ? "✅" : "❌"))
            VStack(alignment: .leading, spacing: 2) {
                // Identify rows list the labels below, so the header shows the form's string.
                Text("\(result.verb) — \(result.kind == .identify ? result.formString : result.formLabel)")
                    .font(.subheadline.weight(.semibold))
                if result.timedOut {
                    Text("Time's up")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !result.ok {
                    Text("You chose: \(result.chosen)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Correct: \(result.correct)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
        }
        .padding(12)
    }
}
