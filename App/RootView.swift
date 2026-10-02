import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(FuriganaStore.self) private var furiganaStore
    @Environment(QuizHistoryStore.self) private var quizHistory
    @AppStorage("appearanceMode", store: .appGroup) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @AppStorage("showFurigana", store: .appGroup) private var showFurigana = true
    @State private var selection: Verb?
    @State private var showingExamples = false
    @State private var showingSettings = false
    @State private var showingGuide = false
    @State private var showingProgress = false
    @State private var quizQuestions: [QuizQuestion]?
    @State private var topicSheetVerbs: [Verb]?
    @State private var pendingQuestions: [QuizQuestion]?
    @State private var incomingRoute: Route?

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
        .onOpenURL { url in
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

    /// The existing Verbs experience — moved here unchanged, including the
    /// sheets and quiz presentation chained onto it — so `MainTabView`
    /// can host it as one tab.
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
                    weakSpotCount: weakPairs(in: topicSheetVerbs).count,
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
            return buildQuestions(verbs: verbs, topics: topics, count: quizQuestionCount)
        case .weakSpots:
            // Takes the first N buildable pairs in rank order, then shuffles the quiz.
            return buildQuestions(pairs: weakPairs(in: verbs), among: verbs, count: quizQuestionCount).shuffled()
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
