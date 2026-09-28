import SwiftUI
import VerbKit

struct QuizQuestionView: View {
    var viewModel: QuizViewModel
    let question: QuizQuestion

    private let shapeSymbols = ["triangle.fill", "diamond.fill", "circle.fill", "square.fill"]
    private let choiceColors: [Color] = [.red, .blue, .yellow, .green]

    var body: some View {
        // A ScrollView here (matching QuizResultsView) is what makes the
        // Next/See Results button reachable once `feedback` grows this
        // screen's content past whatever height the presenting container
        // actually offers on this SDK — a plain VStack silently clips the
        // overflow instead of resizing, taking the button with it.
        ScrollView {
            VStack(spacing: 20) {
                header
                promptCard
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                        choiceButton(choice, index: index)
                    }
                }
                if viewModel.isAnswered {
                    feedback
                    Button(viewModel.index + 1 >= viewModel.questions.count ? "See Results →" : "Next →") {
                        viewModel.advance()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .padding()
        }
    }

    private var header: some View {
        HStack {
            Text("\(viewModel.index + 1) / \(viewModel.questions.count)")
                .font(.headline)
            Spacer()
            Text("⭐ \(viewModel.score)")
        }
    }

    private var promptCard: some View {
        VStack(spacing: 8) {
            Text(.init("What is the **\(formLabels[question.form] ?? "")** form of…"))
                .font(.caption)
                .multilineTextAlignment(.center)
            Text(question.verb.dict)
                .font(.system(size: 36, weight: .heavy))
            if let kanji = question.verb.kanji {
                Text(kanji).font(.title3).foregroundStyle(.secondary)
            }
            Text(question.verb.meaning)
                .italic()
                .foregroundStyle(.secondary)
            Text("⏱ \(viewModel.timeLeft)s")
                .font(.headline)
                .foregroundStyle(timerColor)
        }
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
    }

    private var timerColor: Color {
        viewModel.timeLeft > 10 ? .green : viewModel.timeLeft > 5 ? .orange : .red
    }

    private func choiceButton(_ choice: String, index: Int) -> some View {
        let isCorrect = choice == question.correct
        let isSelected = choice == viewModel.selected
        var background = choiceColors[index % choiceColors.count]
        if viewModel.isAnswered {
            if isCorrect { background = .green }
            else if isSelected { background = .red }
        }
        return Button {
            viewModel.choose(choice)
        } label: {
            HStack {
                Image(systemName: shapeSymbols[index % shapeSymbols.count])
                Text(choice)
                if viewModel.isAnswered && isCorrect { Image(systemName: "checkmark") }
                if viewModel.isAnswered && isSelected && !isCorrect { Image(systemName: "xmark") }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.glassProminent)
        .tint(background)
        .disabled(viewModel.isAnswered)
        .opacity(viewModel.isAnswered && !isCorrect && !isSelected ? 0.35 : 1)
    }

    private var feedback: some View {
        Group {
            if viewModel.timedOut {
                Text("⏰ Time's up!")
            } else if viewModel.selected == question.correct {
                Text("🎉 Correct!")
            } else {
                Text("❌ The answer was: \(question.correct)")
            }
        }
        .font(.headline)
        .padding()
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .glassEffect(
            .regular.tint(viewModel.timedOut ? .orange : (viewModel.selected == question.correct ? .green : .red)),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}
