import SwiftUI
import VerbKit

/// What the Counters detail column shows. `focus` lands a counter page on one number.
enum CounterDestination: Hashable {
    case group(CounterGroup)
    case section(CounterSection)
    case counter(Counter, focus: CounterNumber?)
    case patterns
}

/// Starts a counter quiz from anywhere in the Counters tab (Practise this counter).
struct StartCounterQuiz {
    var handler: ([CounterQuestion]) -> Void = { _ in }

    func callAsFunction(_ questions: [CounterQuestion]) {
        handler(questions)
    }
}

private struct StartCounterQuizKey: EnvironmentKey {
    static let defaultValue = StartCounterQuiz()
}

extension EnvironmentValues {
    var startCounterQuiz: StartCounterQuiz {
        get { self[StartCounterQuizKey.self] }
        set { self[StartCounterQuizKey.self] = newValue }
    }
}

/// The Counters tab: search and the counter directory in the sidebar, a compare table, counter page or
/// Sound patterns in the detail column. Moving from a group table to a counter pushes inside the
/// detail stack.
struct CountersTab: View {
    @Binding var destination: CounterDestination?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let onSettings: () -> Void
    @Environment(CountersStore.self) private var store
    @Environment(QuizHistoryStore.self) private var quizHistory
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @State private var showingQuizSheet = false
    /// Set by the sheet and moved to `quizQuestions` once the sheet is gone, so the two never overlap.
    @State private var pendingQuestions: [CounterQuestion]?
    @State private var quizQuestions: [CounterQuestion]?

    private var visibleCounters: [Counter] {
        store.counters.visible(in: LevelSettings(rawValue: hiddenLevelsRaw))
    }

    private func available(_ kind: QuizQuestionKind) -> Bool {
        !buildCounterQuestions(counters: visibleCounters, groups: store.groups, kind: kind, count: 1).isEmpty
    }

    /// The weak reading pairs among the visible counters, ranked, as (counter, number).
    private var weakPairs: [(counter: Counter, number: CounterNumber)] {
        let byID = Dictionary(visibleCounters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return QuizProgress(attempts: quizHistory.attempts)
            .weakCounterPairs(among: Set(byID.keys))
            .compactMap { pair in byID[pair.counterID].map { ($0, pair.number) } }
    }

    private func questions(for selection: CounterQuizSelection) -> [CounterQuestion] {
        let counters = visibleCounters
        let count = quizQuestionCount
        func built(_ kind: QuizQuestionKind) -> [CounterQuestion] {
            buildCounterQuestions(counters: counters, groups: store.groups, kind: kind, count: count)
        }
        switch selection {
        case .whichCounter: return built(.counterChoice)
        case .readIt: return built(.counterReading)
        case .mixed: return Array((built(.counterChoice) + built(.counterReading)).shuffled().prefix(count))
        case .weakSpots: return buildCounterQuestions(pairs: weakPairs, count: count).shuffled()
        }
    }

    var body: some View {
        splitView
            .environment(\.startCounterQuiz, StartCounterQuiz { quizQuestions = $0 })
            .sheet(isPresented: $showingQuizSheet, onDismiss: {
                if let pendingQuestions {
                    quizQuestions = pendingQuestions
                    self.pendingQuestions = nil
                }
            }) {
                CounterQuizSheet(
                    whichCounterAvailable: available(.counterChoice),
                    readItAvailable: available(.counterReading),
                    weakSpotCount: buildCounterQuestions(pairs: weakPairs, count: 1000).count,
                    onStart: { selection in
                        let built = questions(for: selection)
                        pendingQuestions = built.isEmpty ? nil : built
                        showingQuizSheet = false
                    },
                    onCancel: { showingQuizSheet = false }
                )
            }
            #if os(iOS)
            .fullScreenCover(isPresented: quizPresentationBinding) { quizScreen }
            #else
            .sheet(isPresented: quizPresentationBinding) { quizScreen.frame(minWidth: 560, minHeight: 640) }
            #endif
    }

    @ViewBuilder private var quizScreen: some View {
        if let quizQuestions {
            CounterQuizView(questions: quizQuestions, recorder: { quizHistory.record($0) }, onDone: { self.quizQuestions = nil })
        }
    }

    private var quizPresentationBinding: Binding<Bool> {
        Binding(
            get: { quizQuestions != nil },
            set: { isPresented in if !isPresented { quizQuestions = nil } }
        )
    }

    private var splitView: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            CountersHomeView(
                destination: $destination, column: $preferredColumn, onSettings: onSettings,
                onQuiz: { showingQuizSheet = true }
            )
        } detail: {
            NavigationStack {
                if let destination {
                    CounterDestinationView(destination: destination)
                        .navigationDestination(for: CounterDestination.self) {
                            CounterDestinationView(destination: $0)
                        }
                } else {
                    ContentUnavailableView("Choose a Counter", systemImage: "textformat.123")
                }
            }
            // A new choice in the sidebar starts a fresh stack.
            .id(destination)
        }
    }
}

/// The page for one destination.
struct CounterDestinationView: View {
    let destination: CounterDestination

    var body: some View {
        switch destination {
        case let .group(group):
            GroupTableView(group: group)
        case let .section(section):
            GroupTableView(section: section)
        case let .counter(counter, focus):
            CounterDetailView(counter: counter, focus: focus)
        case .patterns:
            SoundPatternsView()
        }
    }
}
