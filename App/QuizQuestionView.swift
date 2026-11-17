import SwiftUI
import VerbKit

struct QuizQuestionView: View {
    @Environment(\.palette) private var palette
    var viewModel: QuizViewModel
    let question: QuizQuestion
    var onDone: () -> Void

    @State private var confirmingQuit = false
    @State private var showGuide = false
    @AppStorage(QuizScript.defaultsKey, store: .appGroup) private var scriptRaw = QuizScript.kana.rawValue

    private var script: QuizScript { QuizScript(storedValue: scriptRaw) }

    var body: some View {
        // A ScrollView here (matching QuizResultsView) is what makes the
        // Next/See Results button reachable once `feedback` grows this
        // screen's content past whatever height the presenting container
        // actually offers on this SDK — a plain VStack silently clips the
        // overflow instead of resizing, taking the button with it.
        ScrollView {
            VStack(spacing: 20) {
                QuizHeader(index: viewModel.index, count: viewModel.questions.count, score: viewModel.score,
                           showsSoundToggle: true) {
                    confirmingQuit = true
                }
                promptCard
                QuizChoiceGrid(
                    choices: question.choices,
                    isCorrect: { $0 == question.correct },
                    selected: viewModel.selected,
                    isAnswered: viewModel.isAnswered,
                    // Identify choices are form names, not forms.
                    verb: question.kind == .identify ? nil : question.verb(of:)
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
                    Text(.init("Fill in the blank with the **\(question.form.label)** form of \(script.text(for: question.verb.dict, of: question.verb))"))
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
                case .connect, .counterChoice, .counterReading, .counterAsk, .spotMistake, .particle, .verbPair:
                    // Never shown here: connection and counter questions have their own screens.
                    EmptyView()
                case .identify:
                    Text("Which form is this?")
                        .font(.caption)
                    QuizVerbText(kana: question.formString, verb: question.verb, revealed: viewModel.isAnswered)
                        .font(.largeTitle.weight(.heavy))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    // The dictionary form would give the answer away when it is the question.
                    Text(question.verb.dict == question.formString
                         ? question.verb.meaning
                         : "\(script.text(for: question.verb.dict, of: question.verb)) · \(question.verb.meaning)")
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
            if script.usesKanji {
                QuizVerbText(kana: question.verb.dict, verb: question.verb, revealed: viewModel.isAnswered)
                    .font(.largeTitle.weight(.heavy))
            } else {
                Text(question.verb.dict)
                    .font(.largeTitle.weight(.heavy))
                if let kanji = question.verb.kanji {
                    JapaneseText(kanji).font(.title3).foregroundStyle(.secondary)
                }
            }
            Text(question.verb.meaning)
                .italic()
                .foregroundStyle(.secondary)
        }
    }

    private var timerColor: Color {
        viewModel.timeLeft > 10 ? palette.muted : viewModel.timeLeft > 5 ? palette.ink : palette.mark
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
                        .buttonStyle(.paperSecondaryInline)
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
                } else if question.kind == .identify {
                    Label("The answer was: \(question.correct)", systemImage: "xmark.circle.fill")
                } else {
                    Label {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("The answer was:")
                            QuizVerbText(kana: question.correct, verb: question.verb, revealed: true)
                        }
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
            }
            .font(.headline)
        }
    }

    private var feedbackTone: QuizFeedbackTone {
        viewModel.timedOut ? .timeout : (viewModel.selected == question.correct ? .correct : .wrong)
    }
}
