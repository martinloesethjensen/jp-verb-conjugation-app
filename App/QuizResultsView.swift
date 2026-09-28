import SwiftUI
import VerbKit

struct QuizResultsView: View {
    var viewModel: QuizViewModel
    var onDone: () -> Void

    private var percentage: Int {
        guard !viewModel.questions.isEmpty else { return 0 }
        return Int((Double(viewModel.score) / Double(viewModel.questions.count) * 100).rounded())
    }

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
                Text(emoji).font(.system(size: 56))
                Text("Quiz Complete!").font(.title2.weight(.bold))
                Text("\(viewModel.score)/\(viewModel.questions.count)")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(percentage >= 60 ? .green : .orange)
                Text("\(percentage)% correct").foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.offset) { _, result in
                        resultRow(result)
                        Divider()
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button("Back to Table", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func resultRow(_ result: QuizResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(result.ok ? "✅" : "❌")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.verb) — \(formLabels[result.form] ?? "")")
                    .font(.subheadline.weight(.semibold))
                if !result.ok {
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
