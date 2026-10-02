import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(FuriganaStore.self) private var furiganaStore
    @Environment(QuizHistoryStore.self) private var quizHistory
    @AppStorage("appearanceMode", store: .appGroup) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @AppStorage("showFurigana", store: .appGroup) private var showFurigana = true
    @AppStorage(ReminderScheduler.enabledKey, store: .appGroup) private var reminderEnabled = false
    @AppStorage(ReminderScheduler.minutesKey, store: .appGroup) private var reminderMinutes = ReminderScheduler.defaultMinutes
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminderRouter = ReminderRouter.shared
    @State private var selection: Verb?
    @State private var showingExamples = false
    @State private var showingSettings = false
    @State private var showingGuide = false
    @State private var showingProgress = false
    @State private var quizQuestions: [QuizQuestion]?
    @State private var topicSheetVerbs: [Verb]?
    @State private var pendingQuestions: [QuizQuestion]?
    @State private var incomingRoute: Route?

    /// What a link or tapped notification opens.
    private func open(_ url: URL) {
        guard let route = Route(url: url) else { return }
        // Anything presented over the list would hide the page the link opens.
        showingExamples = false
        showingSettings = false
        showingGuide = false
        showingProgress = false
        topicSheetVerbs = nil
        pendingQuestions = nil
        quizQuestions = nil
        incomingRoute = route
    }

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some View {
        Group {
            if verbStore.hasLocalData {
                MainTabView(verbSelection: $selection, incomingRoute: $incomingRoute, onSettings: { showingSettings = true }) {
                    verbsTab
                }
            } else {
                DataLoadingView(state: verbStore.firstLaunchState) {
                    Task { await verbStore.retryFirstLaunch() }
                }
            }
        }
        .onOpenURL { open($0) }
        .onChange(of: reminderRouter.pendingURL) { _, url in
            guard let url else { return }
            reminderRouter.pendingURL = nil
            open(url)
        }
        // Keep the next days of reminders current: the pick depends on the verbs and levels.
        .task(id: ReminderRefresh(verbs: verbStore.verbs, enabled: reminderEnabled, minutes: reminderMinutes, hiddenLevels: hiddenLevelsRaw, phase: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await ReminderScheduler.refresh(verbs: verbStore.verbs)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
        .environment(\.furiganaEnabled, showFurigana)
        .environment(\.furiganaDictionary, furiganaStore.dictionary)
        // Applied to the windows rather than with preferredColorScheme: see AppearanceApplier.
        .onChange(of: appearanceModeRaw, initial: true) { _, _ in
            AppearanceApplier.apply(appearance)
        }
    }

    /// The Verbs experience, including the sheets and quiz presentation chained
    /// onto it, so `MainTabView` can host it as one tab. The Settings sheet lives
    /// on the root instead, so the Grammar tab can open it too.
    @ViewBuilder
    private var verbsTab: some View {
        NavigationSplitView {
            VerbListView(
                selection: $selection,
                showGuide: $showingGuide,
                onProgress: { showingProgress = true },
                onRandomQuiz: { topicSheetVerbs = verbStore.verbs.visible(in: LevelSettings.load()) },
                onSettings: { showingSettings = true }
            )
        } detail: {
            if let selection {
                VerbDetailView(
                    verb: selection,
                    onExamples: { showingExamples = true },
                    onQuiz: { topicSheetVerbs = [selection] }
                )
            } else {
                ContentUnavailableView("Select a Verb", systemImage: "text.book.closed")
            }
        }
        .sheet(isPresented: $showingExamples) {
            if let selection {
                ExamplesView(verb: selection)
            }
        }
        .sheet(isPresented: $showingProgress) { QuizProgressView() }
        .sheet(isPresented: topicSheetBinding, onDismiss: {
            if let pendingQuestions {
                quizQuestions = pendingQuestions
                self.pendingQuestions = nil
            }
        }) {
            if let topicSheetVerbs {
                QuizTopicSheet(
                    verbs: topicSheetVerbs,
                    weakSpotCount: { weakPairs(in: $0).count },
                    onStart: { verbs, selection in
                        let questions = questions(for: selection, verbs: verbs)
                        pendingQuestions = questions.isEmpty ? nil : questions
                        self.topicSheetVerbs = nil
                    },
                    onCancel: { self.topicSheetVerbs = nil }
                )
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: quizPresentationBinding) {
            if let quizQuestions {
                QuizView(questions: quizQuestions, recorder: { quizHistory.record($0) }, onDone: { self.quizQuestions = nil })
            }
        }
        #else
        .sheet(isPresented: quizPresentationBinding) {
            if let quizQuestions {
                QuizView(questions: quizQuestions, recorder: { quizHistory.record($0) }, onDone: { self.quizQuestions = nil })
                    .frame(minWidth: 560, minHeight: 640)
            }
        }
        #endif
    }

    /// The ranked weak (verb, form) pairs among `verbs`, skipping any whose verb or form no longer exists.
    private func weakPairs(in verbs: [Verb]) -> [(verb: Verb, form: QuizForm)] {
        let verbsByDict = Dictionary(verbs.map { ($0.dict, $0) }, uniquingKeysWith: { first, _ in first })
        let formsByID = Dictionary(QuizForm.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return QuizProgress(attempts: quizHistory.attempts)
            .weakPairs(among: Set(verbs.map(\.dict)))
            .compactMap { weak in
                guard let verb = verbsByDict[weak.verb], let form = formsByID[weak.formID] else { return nil }
                return (verb, form)
            }
    }

    private func questions(for selection: QuizSelection, verbs: [Verb]) -> [QuizQuestion] {
        switch selection {
        case .topics(let topics):
            return buildQuestions(verbs: verbs, topics: topics, count: quizQuestionCount, kinds: QuizQuestionKind.allCases)
        case .weakSpots:
            // Takes the first N buildable pairs in rank order, then shuffles the quiz.
            return buildQuestions(pairs: weakPairs(in: verbs), among: verbs, count: quizQuestionCount, kinds: QuizQuestionKind.allCases).shuffled()
        }
    }

    private var topicSheetBinding: Binding<Bool> {
        Binding(
            get: { topicSheetVerbs != nil },
            set: { isPresented in if !isPresented { topicSheetVerbs = nil } }
        )
    }

    private var quizPresentationBinding: Binding<Bool> {
        Binding(
            get: { quizQuestions != nil },
            set: { isPresented in if !isPresented { quizQuestions = nil } }
        )
    }
}

/// Everything that changes which reminders should exist; `.task(id:)` reruns when it changes.
private struct ReminderRefresh: Equatable {
    var verbs: [Verb]
    var enabled: Bool
    var minutes: Int
    var hiddenLevels: String
    var phase: Bool
}
