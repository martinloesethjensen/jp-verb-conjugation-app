import SwiftUI

/// The parts every quiz screen repeats: the quit/score header, the answer grid, the prompt and
/// feedback cards, the pinned Next button, the quit confirmation and the "practise missed"
/// results shell. The verb quiz, counter quiz and connection quiz all use these; only their
/// question content and two model types differ.

// MARK: - Header

/// Quit button, question progress and score. Shared by every quiz screen.
struct QuizHeader: View {
    let index: Int
    let count: Int
    let score: Int
    let onQuit: () -> Void

    var body: some View {
        HStack {
            Button(action: onQuit) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Quit quiz")

            Text("\(index + 1) / \(count)")
                .font(.headline)
            Spacer()
            Label("\(score)", systemImage: "star.fill")
                .accessibilityLabel("Score \(score)")
        }
    }
}

// MARK: - Answers

/// The two-column answer grid. `isCorrect` differs per quiz because the counter quiz accepts
/// more than one answer.
struct QuizChoiceGrid: View {
    let choices: [String]
    let isCorrect: (String) -> Bool
    let selected: String?
    let isAnswered: Bool
    let onChoose: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                QuizChoiceButton(
                    choice: choice, index: index, isCorrect: isCorrect(choice),
                    isSelected: choice == selected, isAnswered: isAnswered
                ) {
                    onChoose(choice)
                }
            }
        }
    }
}

/// Pins the question's primary button (Next / See Results) below the scrolling content, so it
/// doesn't move below the fold as feedback appears.
extension View {
    func quizAdvanceBar(isVisible: Bool, title: String, action: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom) {
            if isVisible {
                Button(title, systemImage: "arrow.right", action: action)
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Cards

/// The question's glass card. `fillsWidth` matches the counter and connection quizzes, whose
/// cards span the column; the verb quiz's card hugs its content.
struct QuizPromptCard<Content: View>: View {
    var fillsWidth = false
    @ViewBuilder var content: Content

    var body: some View {
        if fillsWidth {
            content
                .frame(maxWidth: .infinity)
                .padding()
                .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        } else {
            content
                .padding()
                .glassEffect(in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

enum QuizFeedbackTone {
    case correct
    case wrong
    case timeout

    var tint: Color {
        switch self {
        case .correct: QuizChoiceButton.correctColor
        case .wrong: QuizChoiceButton.wrongColor
        case .timeout: .orange
        }
    }
}

/// The answered-question feedback card: a tinted glass surface. The verb quiz centres its
/// single line; the counter and connection quizzes lead with their explanation.
struct QuizFeedbackCard<Content: View>: View {
    var tone: QuizFeedbackTone
    var alignment: Alignment = .leading
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: alignment)
            .foregroundStyle(.white)
            .glassEffect(.regular.tint(tone.tint), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// One missed question on the results screen.
struct QuizMissedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .glassEffect(in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Quit confirmation

extension View {
    func quizQuitDialog(isPresented: Binding<Bool>, onQuit: @escaping () -> Void) -> some View {
        confirmationDialog("Quit this quiz?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Quit quiz", role: .destructive, action: onQuit)
            Button("Keep going", role: .cancel) {}
        }
    }
}

// MARK: - Results

/// The counter and connection quizzes' results screen: score, a subtitle, each missed question,
/// "Practise missed" and Done. The verb quiz has its own richer results (`QuizResultsView`).
struct QuizResultsSummary<Missed: View>: View {
    let score: Int
    let count: Int
    let subtitle: String
    let hasMissed: Bool
    let onPractiseMissed: () -> Void
    let onDone: () -> Void
    @ViewBuilder var missed: Missed

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("\(score) / \(count)")
                    .font(.system(size: 56, weight: .heavy))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                missed
                if hasMissed {
                    Button("Practise missed", systemImage: "arrow.counterclockwise", action: onPractiseMissed)
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
