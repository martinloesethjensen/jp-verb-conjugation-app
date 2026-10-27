import SwiftUI
import VerbKit

struct QuizQuestionView: View {
    var viewModel: QuizViewModel
    let question: QuizQuestion
    var onDone: () -> Void

    @State private var confirmingQuit = false
    @State private var showGuide = false

    var body: some View {
        // A ScrollView here (matching QuizResultsView) is what makes the
        // Next/See Results button reachable once `feedback` grows this
        // screen's content past whatever height the presenting container
        // actually offers on this SDK — a plain VStack silently clips the
        // overflow instead of resizing, taking the button with it.
        ScrollView {
            VStack(spacing: 20) {
                QuizHeader(index: viewModel.index, count: viewModel.questions.count, score: viewModel.score) {
                    confirmingQuit = true
                }
                promptCard
                QuizChoiceGrid(
                    choices: question.choices,
                    isCorrect: { $0 == question.correct },
                    selected: viewModel.selected,
                    isAnswered: viewModel.isAnswered
                ) { choice in
                    viewModel.choose(choice)
                }
                if viewModel.isAnswered {
                    feedback
                }
            }
            .padding()
        }
        .quizAdvanceBar(
            isVisible: viewModel.isAnswered,
            title: viewModel.index + 1 >= viewModel.questions.count ? "See Results" : "Next"
        ) {
            viewModel.advance()
        }
        .quizQuitDialog(isPresented: $confirmingQuit, onQuit: onDone)
    }

    private var promptCard: some View {
        QuizPromptCard {
            VStack(spacing: 8) {
                switch question.kind {
                case .conjugate:
                    Text(.init("What is the **\(question.form.label)** form of…"))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    verbBlock
                case .fillIn:
                    Text(.init("Fill in the blank with the **\(question.form.label)** form of \(question.verb.dict)"))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                    JapaneseText(question.sentence ?? "")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                    if let translation = question.translation {
                        Text(translation)
                            .italic()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                case .connect, .counterChoice, .counterReading, .counterAsk, .spotMistake:
                    // Never shown here: connection and counter questions have their own screens.
                    EmptyView()
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
        }
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

    private var feedback: some View {
        VStack(spacing: 10) {
            feedbackBanner
            if let result = viewModel.results.last, !result.ok, !viewModel.timedOut,
               let why = result.errorExplanation {
                Text(why)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if result.error?.opensVerbGuide == true {
                    Button("See the verb guide", systemImage: "book") { showGuide = true }
                        .buttonStyle(.bordered)
                }
            }
        }
        .sheet(isPresented: $showGuide) { VerbGuideSheet() }
    }

    private var feedbackBanner: some View {
        QuizFeedbackCard(tone: feedbackTone, alignment: .center) {
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
        }
    }

    private var feedbackTone: QuizFeedbackTone {
        viewModel.timedOut ? .timeout : (viewModel.selected == question.correct ? .correct : .wrong)
    }
}
