import SwiftUI
import VerbKit

struct QuizView: View {
    @State private var viewModel: QuizViewModel
    var onDone: () -> Void

    init(questions: [QuizQuestion], onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: QuizViewModel(questions: questions))
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if viewModel.finished {
                QuizResultsView(viewModel: viewModel, onDone: onDone)
            } else if let question = viewModel.currentQuestion {
                QuizQuestionView(viewModel: viewModel, question: question)
            }
        }
        // Restarts the countdown loop each time the question index
        // changes; SwiftUI cancels the previous instance automatically.
        .task(id: viewModel.index) {
            while !viewModel.isAnswered && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                viewModel.tickTimer()
            }
        }
    }
}
