import SwiftUI
import VerbKit

struct QuizQuestionView: View {
    var viewModel: QuizViewModel
    let question: QuizQuestion
    var onDone: () -> Void

    @State private var confirmingQuit = false

    private let shapeSymbols = ["triangle.fill", "diamond.fill", "circle.fill", "square.fill"]
    // Pastels from the app palette (labels are near-black, as on `accentPill`). The shapes carry
    // the identity; correct/wrong use deeper green and red so they stand out from every choice.
    private let choiceColors: [Color] = [
        TeGroup.tte.accentColor,
        VerbType.ru.accentColor,
        VerbType.u.accentColor,
        TeGroup.ite.accentColor,
    ]
    private let correctColor = Color(red: 0.13, green: 0.55, blue: 0.32)
    private let wrongColor = Color(red: 0.78, green: 0.20, blue: 0.20)

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
                }
            }
            .padding()
        }
        // Pinned so the button doesn't move below the fold as feedback appears.
        .safeAreaInset(edge: .bottom) {
            if viewModel.isAnswered {
                Button(viewModel.index + 1 >= viewModel.questions.count ? "See Results" : "Next",
                       systemImage: "arrow.right") {
                    viewModel.advance()
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .confirmationDialog("Quit this quiz?", isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button("Quit quiz", role: .destructive, action: onDone)
            Button("Keep going", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack {
            Button {
                confirmingQuit = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Quit quiz")

            Text("\(viewModel.index + 1) / \(viewModel.questions.count)")
                .font(.headline)
            Spacer()
            Label("\(viewModel.score)", systemImage: "star.fill")
                .accessibilityLabel("Score \(viewModel.score)")
        }
    }

    private var promptCard: some View {
        VStack(spacing: 8) {
            switch question.kind {
            case .conjugate:
                Text(.init("What is the **\(question.form.label)** form of…"))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                verbBlock
            case .identify:
                Text("Which form is this?")
                    .font(.caption)
                Text(question.formString)
                    .font(.largeTitle.weight(.heavy))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                // The dictionary form would give the answer away when it is the question.
                Text(question.verb.dict == question.formString
                     ? question.verb.meaning
                     : "\(question.verb.dict) · \(question.verb.meaning)")
                    .italic()
                    .foregroundStyle(.secondary)
            }
            Label("\(viewModel.timeLeft)s", systemImage: viewModel.timeLeft > 5 ? "timer" : "exclamationmark.timer")
                .font(.headline)
                .foregroundStyle(timerColor)
        }
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
    }

    private var verbBlock: some View {
        VStack(spacing: 8) {
            Text(question.verb.dict)
                .font(.largeTitle.weight(.heavy))
            if let kanji = question.verb.kanji {
                JapaneseText(kanji).font(.title3).foregroundStyle(.secondary)
            }
            Text(question.verb.meaning)
                .italic()
                .foregroundStyle(.secondary)
        }
    }

    private var timerColor: Color {
        viewModel.timeLeft > 10 ? .green : viewModel.timeLeft > 5 ? .orange : .red
    }

    private func choiceButton(_ choice: String, index: Int) -> some View {
        let isCorrect = choice == question.correct
        let isSelected = choice == viewModel.selected
        var background = choiceColors[index % choiceColors.count]
        var labelColor = Color.black.opacity(0.85)
        if viewModel.isAnswered {
            if isCorrect { background = correctColor; labelColor = .white }
            else if isSelected { background = wrongColor; labelColor = .white }
        }
        return Button {
            viewModel.choose(choice)
        } label: {
            HStack {
                Image(systemName: shapeSymbols[index % shapeSymbols.count])
                Text(choice)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .lineLimit(3)
                if viewModel.isAnswered && isCorrect { Image(systemName: "checkmark") }
                if viewModel.isAnswered && isSelected && !isCorrect { Image(systemName: "xmark") }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(labelColor)
        }
        .buttonStyle(.glassProminent)
        .tint(background)
        .allowsHitTesting(!viewModel.isAnswered)
        .opacity(viewModel.isAnswered && !isCorrect && !isSelected ? 0.35 : 1)
    }

    private var feedback: some View {
        Group {
            if viewModel.timedOut {
                Label("Time's up!", systemImage: "alarm")
            } else if viewModel.selected == question.correct {
                Label("Correct!", systemImage: "checkmark.circle.fill")
            } else {
                Label("The answer was: \(question.correct)", systemImage: "xmark.circle.fill")
            }
        }
        .font(.headline)
        .padding()
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .glassEffect(
            .regular.tint(viewModel.timedOut ? .orange : (viewModel.selected == question.correct ? correctColor : wrongColor)),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}
