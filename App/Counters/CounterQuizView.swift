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
        .confirmationDialog("Quit this quiz?", isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button("Quit quiz", role: .destructive, action: onDone)
            Button("Keep going", role: .cancel) {}
        }
    }

    private func questionScreen(_ question: CounterQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                prompt(question)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                        QuizChoiceButton(
                            choice: choice, index: index, isCorrect: question.accepted.contains(choice),
                            isSelected: choice == model.selected, isAnswered: model.isAnswered
                        ) {
                            model.choose(choice)
                        }
                    }
                }
                if model.isAnswered { feedback(question) }
            }
            .padding()
        }
        // Pinned so the button doesn't move below the fold as feedback appears.
        .safeAreaInset(edge: .bottom) {
            if model.isAnswered {
                Button(model.index + 1 >= model.questions.count ? "See Results" : "Next",
                       systemImage: "arrow.right") {
                    model.advance()
                }
                .labelStyle(.titleAndIcon)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
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

            Text("\(model.index + 1) / \(model.questions.count)")
                .font(.headline)
            Spacer()
            Label("\(model.score)", systemImage: "star.fill")
                .accessibilityLabel("Score \(model.score)")
        }
    }

    /// Plain `Text` throughout: the furigana dictionary would read 三本 as さん + ほん.
    private func prompt(_ question: CounterQuestion) -> some View {
        VStack(spacing: 8) {
            Text(question.kind == .counterChoice ? "Which counter?" : "How do you read it?")
                .font(.caption)
            if let symbol = question.symbol {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            Text(question.prompt)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(question.detail)
                .italic()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func feedback(_ question: CounterQuestion) -> some View {
        let right = model.selected.map(question.accepted.contains) ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(right ? "Correct!" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.headline)
                Spacer()
                if question.kind == .counterReading { SpeakButton(text: question.correct) }
            }
            if !right {
                Text(question.explanation)
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .glassEffect(
            .regular.tint(right ? QuizChoiceButton.correctColor : QuizChoiceButton.wrongColor),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var results: some View {
        let missed = model.missedQuestions
        return ScrollView {
            VStack(spacing: 20) {
                Text("\(model.score) / \(model.questions.count)")
                    .font(.system(size: 56, weight: .heavy))
                Text(missed.isEmpty ? "Every counter in its place." : "Worth another look:")
                    .foregroundStyle(.secondary)
                ForEach(Array(missed.enumerated()), id: \.offset) { _, question in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(question.prompt)  \(question.correct)").font(.headline)
                        Text(question.explanation).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassEffect(in: RoundedRectangle(cornerRadius: 12))
                }
                if !missed.isEmpty {
                    Button("Practise missed", systemImage: "arrow.counterclockwise") {
                        model = CounterQuizModel(questions: missed, recorder: recorder)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }
                Button("Done", action: onDone)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
            .padding()
        }
    }
}
