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
        .confirmationDialog("Quit this quiz?", isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button("Quit quiz", role: .destructive, action: onDone)
            Button("Keep going", role: .cancel) {}
        }
    }

    private func questionScreen(_ question: ConnectionQuestion) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                prompt(question)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                        QuizChoiceButton(
                            choice: choice, index: index, isCorrect: choice == question.correct,
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

    private func prompt(_ question: ConnectionQuestion) -> some View {
        VStack(spacing: 8) {
            Text("Join them with the right building block")
                .font(.caption)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(question.word)
                Image(systemName: "plus").font(.title2).foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity)
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 20))
    }

    private func feedback(_ question: ConnectionQuestion) -> some View {
        let right = model.selected == question.correct
        return VStack(alignment: .leading, spacing: 6) {
            Label(right ? "Correct!" : "Not quite", systemImage: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
            Text(question.explanation)
                .font(.subheadline)
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
                Text(missed.isEmpty ? "Every block in the right place." : "Worth another look:")
                    .foregroundStyle(.secondary)
                ForEach(Array(missed.enumerated()), id: \.offset) { _, question in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.correct).font(.headline)
                        Text(question.explanation).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassEffect(in: RoundedRectangle(cornerRadius: 12))
                }
                if !missed.isEmpty {
                    Button("Practise missed", systemImage: "arrow.counterclockwise") {
                        model = ConnectionQuizModel(questions: missed, recorder: recorder)
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
