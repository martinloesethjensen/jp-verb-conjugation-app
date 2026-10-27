import SwiftUI
import CoreSpotlight
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(FuriganaStore.self) private var furiganaStore
    @Environment(QuizHistoryStore.self) private var quizHistory
    @Environment(WordsStore.self) private var wordsStore
    @Environment(CountersStore.self) private var countersStore
    @Environment(DataSyncStatus.self) private var dataSyncStatus
    @Environment(FormCatalogueStore.self) private var formCatalogueStore
    @AppStorage("appearanceMode", store: .appGroup) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @AppStorage("showFurigana", store: .appGroup) private var showFurigana = true
    @AppStorage(ReminderScheduler.enabledKey, store: .appGroup) private var reminderEnabled = false
    @AppStorage(ReminderScheduler.minutesKey, store: .appGroup) private var reminderMinutes = ReminderScheduler.defaultMinutes
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminderRouter = ReminderRouter.shared
    /// "What form is this?" (#110): its index is built here once the verbs are in, not per lookup.
    @State private var formLookup = FormLookupStore()
    @State private var selection: Verb?
    @State private var showingExamples = false
    @State private var showingSettings = false
    @State private var showingGuide = false
    @State private var showingProgress = false
    @State private var quiz: QuizLaunch?
    @State private var topicSheetVerbs: [Verb]?
    @State private var pendingQuiz: QuizLaunch?
    @State private var connectionQuestions: [ConnectionQuestion]?
    @State private var pendingConnections: [ConnectionQuestion]?
    @State private var spotQuestions: [SpotMistakeQuestion]?
    @State private var pendingSpot: [SpotMistakeQuestion]?
    @State private var incomingRoute: Route?
    /// A link that arrived during a quiz, waiting for "Leave the quiz?" to be answered.
    @State private var linkLeavingQuiz: URL?
    @Environment(WordBankTransferHub.self) private var wordBankTransfer
    @Environment(QuizSessionStore.self) private var quizSessions

    /// What a link opens: a verb or lesson page, or a quiz (from Siri and Shortcuts).
    /// During a quiz it asks first, unless `confirmed`; a verb quiz left this way can be resumed.
    private func open(_ url: URL, confirmed: Bool = false) {
        // A .wordbank file from Files, AirDrop or Mail: show what importing it would do.
        if url.isFileURL, url.pathExtension.lowercased() == "wordbank" {
            showingSettings = false
            wordBankTransfer.pendingImport = WordBankImportRequest(url: url)
            return
        }
        let quizLink = QuizLink(url: url)
        // A link from outside the app must not dismiss anything for a page that doesn't exist.
        let route = Route(url: url).flatMap { route in
            route.resolve(
                verbs: verbStore.verbs, grammarPoints: verbStore.grammarPoints,
                counters: countersStore.counters, groups: countersStore.groups
            ) == nil ? nil : route
        }
        guard quizLink != nil || route != nil else { return }
        if !confirmed && (quiz != nil || connectionQuestions != nil || spotQuestions != nil) {
            linkLeavingQuiz = url
            return
        }
        // Anything presented over the list would hide the page the link opens.
        showingExamples = false
        showingSettings = false
        showingGuide = false
        showingProgress = false
        topicSheetVerbs = nil
        pendingQuiz = nil
        quiz = nil
        connectionQuestions = nil
        pendingConnections = nil
        spotQuestions = nil
        pendingSpot = nil
        if let quizLink {
            let verbs = verbStore.verbs.visible(in: LevelSettings.load())
            let topics = quizLink.topic.map { Set([$0]) } ?? Set(QuizTopic.allCases)
            let questions = buildQuestions(verbs: verbs, topics: topics, count: quizQuestionCount, kinds: QuizQuestionKind.verbKinds)
            if !questions.isEmpty { quiz = QuizLaunch(questions: questions, topic: QuizSessionTopic(topics: topics)) }
        } else {
            incomingRoute = route
        }
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
        // `initial`: a tap that launched the app can arrive before this view exists.
        .onChange(of: reminderRouter.pendingURL, initial: true) { _, url in
            guard let url else { return }
            reminderRouter.pendingURL = nil
            open(url)
        }
        // Keep the next days of reminders current: the pick depends on the verbs and levels.
        .task(id: ReminderRefresh(verbs: verbStore.verbs, enabled: reminderEnabled, minutes: reminderMinutes, hiddenLevels: hiddenLevelsRaw, phase: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await ReminderScheduler.refresh(verbs: verbStore.verbs)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let url = SpotlightIndexer.url(from: activity) { open(url) }
        }
        // Keep Spotlight in step with the data (replaces the whole index, so only when ids change).
        .task(id: verbStore.verbs.map(\.id) + verbStore.grammarPoints.map(\.id)
            + countersStore.counters.map(\.id) + countersStore.groups.map(\.id)) {
            await SpotlightIndexer.index(
                verbs: verbStore.verbs, grammarPoints: verbStore.grammarPoints,
                counters: countersStore.counters, groups: countersStore.groups
            )
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
        // Rebuilds only when the verb data's or the form catalogue's version changes (FormIndexCache).
        .onChange(of: verbStore.verbs, initial: true) { updateFormLookup() }
        .onChange(of: formCatalogueStore.catalogue.version) { updateFormLookup() }
        .environment(formLookup)
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
            if let pendingQuiz {
                quiz = pendingQuiz
                self.pendingQuiz = nil
            }
            if let pendingConnections {
                connectionQuestions = pendingConnections
                self.pendingConnections = nil
            }
            if let pendingSpot {
                spotQuestions = pendingSpot
                self.pendingSpot = nil
            }
        }) {
            if let topicSheetVerbs {
                QuizTopicSheet(
                    verbs: topicSheetVerbs,
                    connectionPatterns: verbStore.grammarPoints.visible(in: LevelSettings.load()).filter(\.hasConnections).count,
                    spotMistakeQuestions: spotMistakeQuestions(count: .max).count,
                    weakSpotCount: { weakPairs(in: $0).count },
                    resumable: quizSessions.resumable(verbs: verbStore.verbs) == nil ? nil : quizSessions.session,
                    onResume: resumeQuiz,
                    onStart: { verbs, selection in
                        if case .spotMistake = selection {
                            let built = spotMistakeQuestions(count: quizQuestionCount)
                            pendingSpot = built.isEmpty ? nil : built
                        } else if case .connections = selection {
                            let levels = LevelSettings.load()
                            let built = buildConnectionQuestions(
                                points: verbStore.grammarPoints.visible(in: levels), verbs: verbs,
                                words: wordsStore.words.visible(in: levels), count: quizQuestionCount
                            )
                            pendingConnections = built.isEmpty ? nil : built
                        } else {
                            let questions = questions(for: selection, verbs: verbs)
                            pendingQuiz = questions.isEmpty ? nil : QuizLaunch(questions: questions, topic: QuizSessionTopic(selection))
                        }
                        self.topicSheetVerbs = nil
                    },
                    onCancel: { self.topicSheetVerbs = nil }
                )
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: quizPresentationBinding) {
            if let quiz { quizScreen(quiz) }
        }
        .fullScreenCover(isPresented: connectionPresentationBinding) {
            if let connectionQuestions { connectionScreen(connectionQuestions) }
        }
        .fullScreenCover(isPresented: spotPresentationBinding) {
            if let spotQuestions { spotScreen(spotQuestions) }
        }
        #else
        .sheet(isPresented: quizPresentationBinding) {
            if let quiz {
                quizScreen(quiz)
                    .frame(minWidth: 560, minHeight: 640)
            }
        }
        .sheet(isPresented: connectionPresentationBinding) {
            if let connectionQuestions {
                connectionScreen(connectionQuestions)
                    .frame(minWidth: 560, minHeight: 640)
            }
        }
        .sheet(isPresented: spotPresentationBinding) {
            if let spotQuestions {
                spotScreen(spotQuestions)
                    .frame(minWidth: 560, minHeight: 640)
            }
        }
        #endif
        // A saved quiz whose verbs or forms have since changed can't be resumed.
        .onChange(of: verbStore.verbs, initial: true) {
            quizSessions.discardIfStale(verbs: verbStore.verbs)
        }
    }

    private func quizScreen(_ launch: QuizLaunch) -> some View {
        QuizView(
            questions: launch.questions, progress: launch.progress, topic: launch.topic,
            recorder: { quizHistory.record($0) }, onDone: { quiz = nil }
        )
        // A quiz link during a quiz replaces it: a new identity gives the new quiz fresh state.
        .id(launch.id)
        // On the quiz itself: a cover can't show an alert presented from beneath it.
        .alert("Leave the quiz?", isPresented: leavingQuizBinding) {
            leaveQuizButtons
        } message: {
            Text("Your place is saved. Pick it up again with Resume from the quiz button.")
        }
    }

    private func connectionScreen(_ questions: [ConnectionQuestion]) -> some View {
        ConnectionQuizView(questions: questions, recorder: { quizHistory.record($0) },
                           onDone: { connectionQuestions = nil })
            .alert("Leave the quiz?", isPresented: leavingQuizBinding) {
                leaveQuizButtons
            } message: {
                Text("This quiz ends here. The answers you have given are kept in your progress.")
            }
    }

    private func spotScreen(_ questions: [SpotMistakeQuestion]) -> some View {
        SpotMistakeQuizView(questions: questions, recorder: { quizHistory.record($0) },
                            onDone: { spotQuestions = nil })
            .alert("Leave the quiz?", isPresented: leavingQuizBinding) {
                leaveQuizButtons
            } message: {
                Text("This quiz ends here. The answers you have given are kept in your progress.")
            }
    }

    /// Spot the mistake questions for the levels the user has switched on, as Common mistakes shows them.
    private func spotMistakeQuestions(count: Int) -> [SpotMistakeQuestion] {
        buildSpotMistakeQuestions(
            mistakes: CommonMistakes.build(grammar: verbStore.grammarPoints, counters: countersStore.counters),
            counters: countersStore.counters, levels: LevelSettings.load(), count: count
        )
    }

    @ViewBuilder
    private var leaveQuizButtons: some View {
        Button("Leave") {
            guard let url = linkLeavingQuiz else { return }
            linkLeavingQuiz = nil
            open(url, confirmed: true)
        }
        Button("Keep Practising", role: .cancel) {}
    }

    /// Picks up the saved quiz, if it still fits the data.
    private func resumeQuiz() {
        if let saved = quizSessions.session, let resumable = quizSessions.resumable(verbs: verbStore.verbs) {
            pendingQuiz = QuizLaunch(questions: resumable.questions, progress: resumable.progress, topic: saved.topic)
        }
        topicSheetVerbs = nil
    }

    /// The ranked weak (verb, form) pairs among `verbs`, skipping any whose verb or form no longer exists.
    private func weakPairs(in verbs: [Verb]) -> [(verb: Verb, form: QuizForm)] {
        let verbsByID = Dictionary(verbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let formsByID = Dictionary(QuizForm.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return QuizProgress(attempts: quizHistory.attempts)
            .weakPairs(among: Set(verbs.map(\.id)))
            .compactMap { weak in
                guard let verb = verbsByID[weak.verb], let form = formsByID[weak.formID] else { return nil }
                return (verb, form)
            }
    }

    private func questions(for selection: QuizSelection, verbs: [Verb]) -> [QuizQuestion] {
        switch selection {
        case .topics(let topics):
            return buildQuestions(verbs: verbs, topics: topics, count: quizQuestionCount, kinds: QuizQuestionKind.verbKinds)
        case .weakSpots:
            // Takes the first N buildable pairs in rank order, then shuffles the quiz.
            return buildQuestions(pairs: weakPairs(in: verbs), among: verbs, count: quizQuestionCount, kinds: QuizQuestionKind.verbKinds).shuffled()
        case .connections, .spotMistake:
            return []  // started from onStart instead
        }
    }

    private func updateFormLookup() {
        let catalogue = formCatalogueStore.catalogue
        formLookup.update(
            verbs: verbStore.verbs, verbsVersion: dataSyncStatus.status(for: .verbs).version,
            catalogue: catalogue, catalogueVersion: catalogue.version
        )
    }

    private var topicSheetBinding: Binding<Bool> {
        Binding(
            get: { topicSheetVerbs != nil },
            set: { isPresented in if !isPresented { topicSheetVerbs = nil } }
        )
    }

    private var connectionPresentationBinding: Binding<Bool> {
        Binding(
            get: { connectionQuestions != nil },
            set: { isPresented in if !isPresented { connectionQuestions = nil } }
        )
    }

    private var spotPresentationBinding: Binding<Bool> {
        Binding(
            get: { spotQuestions != nil },
            set: { isPresented in if !isPresented { spotQuestions = nil } }
        )
    }

    private var quizPresentationBinding: Binding<Bool> {
        Binding(
            get: { quiz != nil },
            set: { isPresented in if !isPresented { quiz = nil } }
        )
    }

    private var leavingQuizBinding: Binding<Bool> {
        Binding(
            get: { linkLeavingQuiz != nil },
            set: { isPresented in if !isPresented { linkLeavingQuiz = nil } }
        )
    }
}

/// A verb quiz to present: new, or resumed from a saved `QuizSession` with its progress.
private struct QuizLaunch {
    let id = UUID()
    var questions: [QuizQuestion]
    var progress: QuizProgressState?
    var topic: QuizSessionTopic
}

/// Everything that changes which reminders should exist; `.task(id:)` reruns when it changes.
private struct ReminderRefresh: Equatable {
    var verbs: [Verb]
    var enabled: Bool
    var minutes: Int
    var hiddenLevels: String
    var phase: Bool
}
