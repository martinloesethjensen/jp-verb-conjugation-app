import SwiftUI
import VerbKit

struct QuizView: View {
    @State private var viewModel: QuizViewModel
    /// Bumped when "Practise missed" starts a fresh quiz, so the timer loop restarts
    /// even when the new quiz's first question has the same index as the old last one.
    @State private var attempt = 0
    var onDone: () -> Void

    init(questions: [QuizQuestion], onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: QuizViewModel(questions: questions))
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if viewModel.finished {
                QuizResultsView(viewModel: viewModel, onDone: onDone) { missed in
                    viewModel = QuizViewModel(questions: missed)
                    attempt += 1
                }
            } else if let question = viewModel.currentQuestion {
                QuizQuestionView(viewModel: viewModel, question: question, onDone: onDone)
            }
        }
        // Restarts the countdown loop each time the question index
        // changes; SwiftUI cancels the previous instance automatically.
        .task(id: "\(attempt)-\(viewModel.index)") {
            while !viewModel.isAnswered && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                viewModel.tickTimer()
            }
        }
        // Immersive fullscreen takeover per spec section 10 — hides the
        // home indicator for the duration of the quiz.
        .persistentSystemOverlays(.hidden)
    }
}
