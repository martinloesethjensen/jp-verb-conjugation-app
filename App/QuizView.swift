import SwiftUI
import VerbKit
import WidgetKit

struct QuizView: View {
    @Environment(QuizSessionStore.self) private var sessions
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: QuizViewModel
    /// Bumped when "Practise missed" starts a fresh quiz, so the timer loop restarts
    /// even when the new quiz's first question has the same index as the old last one.
    @State private var attempt = 0
    /// Set when the quiz is quit or done, so leaving the screen then doesn't save it again.
    @State private var ended = false
    @AppStorage("speakQuizAnswers", store: .appGroup) private var speakQuizAnswers = true
    private let topic: QuizSessionTopic
    private let recorder: (QuizAttempt) -> Void
    var onDone: () -> Void

    /// `progress` resumes a saved quiz; without it the quiz starts at the first question.
    init(
        questions: [QuizQuestion], progress: QuizProgressState? = nil, topic: QuizSessionTopic,
        recorder: @escaping (QuizAttempt) -> Void, onDone: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: QuizViewModel(questions: questions, progress: progress, recorder: recorder))
        self.topic = topic
        self.recorder = recorder
        self.onDone = onDone
    }

    /// Keeps the quiz for Resume (issue #38): after each answer and step, and when the app
    /// or this screen goes away. A finished quiz has nothing to resume.
    private func save() {
        guard !ended, !viewModel.finished else { return }
        sessions.save(QuizSession(topic: topic, questions: viewModel.questions, progress: viewModel.progress, savedAt: .now))
    }

    /// Quit or Done: the quiz is over, so there is nothing to resume.
    private func end() {
        ended = true
        sessions.clear()
        onDone()
    }

    var body: some View {
        Group {
            if viewModel.finished {
                QuizResultsView(viewModel: viewModel, onDone: end) { missed in
                    viewModel = QuizViewModel(questions: missed, recorder: recorder)
                    attempt += 1
                    save()
                }
            } else if let question = viewModel.currentQuestion {
                QuizQuestionView(viewModel: viewModel, question: question, onDone: end)
            }
        }
        .onAppear(perform: save)
        .onChange(of: viewModel.results.count) { save() }
        .onChange(of: viewModel.index) { save() }
        // Catches the time left, which isn't saved every tick.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { save() }
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
            guard finished else { return }
            sessions.clear()
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onDisappear {
            // Left for another page (a link, notification or Siri) rather than quit: keep it,
            // unless a quiz started from a link has already saved itself in its place.
            if sessions.session == nil || sessions.session?.questions == viewModel.questions.map(QuizSession.Question.init) {
                save()
            }
            Speaker.shared.stop()
            WidgetCenter.shared.reloadAllTimelines()
        }
        // Immersive fullscreen takeover per spec section 10 — hides the
        // home indicator for the duration of the quiz.
        .persistentSystemOverlays(.hidden)
    }
}
