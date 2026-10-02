import SwiftUI
import VerbKit
import WidgetKit

struct QuizView: View {
    @State private var viewModel: QuizViewModel
    /// Bumped when "Practise missed" starts a fresh quiz, so the timer loop restarts
    /// even when the new quiz's first question has the same index as the old last one.
    @State private var attempt = 0
    @AppStorage("speakQuizAnswers", store: .appGroup) private var speakQuizAnswers = true
    private let recorder: (QuizAttempt) -> Void
    var onDone: () -> Void

    init(questions: [QuizQuestion], recorder: @escaping (QuizAttempt) -> Void, onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: QuizViewModel(questions: questions, recorder: recorder))
        self.recorder = recorder
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if viewModel.finished {
                QuizResultsView(viewModel: viewModel, onDone: onDone) { missed in
                    viewModel = QuizViewModel(questions: missed, recorder: recorder)
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
        .onChange(of: viewModel.isAnswered) { _, answered in
            guard answered else {
                Speaker.shared.stop()
                return
            }
            guard speakQuizAnswers, let question = viewModel.currentQuestion else { return }
            Speaker.shared.speak(question.formString, restart: true)
        }
        // The widgets show weak spots, so refresh them when the quiz ends or is left early.
        .onChange(of: viewModel.finished) { _, finished in
            if finished { WidgetCenter.shared.reloadAllTimelines() }
        }
        .onDisappear {
            Speaker.shared.stop()
            WidgetCenter.shared.reloadAllTimelines()
        }
        // Immersive fullscreen takeover per spec section 10 — hides the
        // home indicator for the duration of the quiz.
        .persistentSystemOverlays(.hidden)
    }
}
