import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(FuriganaStore.self) private var furiganaStore
    @AppStorage("appearanceMode", store: .appGroup) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @AppStorage("showFurigana", store: .appGroup) private var showFurigana = true
    @State private var selection: Verb?
    @State private var showingExamples = false
    @State private var showingSettings = false
    @State private var quizQuestions: [QuizQuestion]?

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some View {
        Group {
            if verbStore.hasLocalData {
                MainTabView(verbSelection: $selection) {
                    verbsTab
                }
            } else {
                DataLoadingView(state: verbStore.firstLaunchState) {
                    Task { await verbStore.retryFirstLaunch() }
                }
            }
        }
        .environment(\.furiganaEnabled, showFurigana)
        .environment(\.furiganaDictionary, furiganaStore.dictionary)
        .preferredColorScheme(appearance.colorScheme)
    }

    /// The existing Verbs experience — moved here unchanged, including the
    /// sheets and quiz presentation chained onto it — so `MainTabView`
    /// can host it as one tab.
    @ViewBuilder
    private var verbsTab: some View {
        NavigationSplitView {
            VerbListView(
                selection: $selection,
                onRandomQuiz: { quizQuestions = buildQuestions(verbs: verbStore.verbs, count: quizQuestionCount) },
                onSettings: { showingSettings = true }
            )
        } detail: {
            if let selection {
                VerbDetailView(
                    verb: selection,
                    onExamples: { showingExamples = true },
                    onQuiz: { quizQuestions = buildQuestions(verbs: [selection], count: min(quizQuestionCount, 9)) }
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
        #if os(iOS)
        .fullScreenCover(isPresented: quizPresentationBinding) {
            if let quizQuestions {
                QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
            }
        }
        #else
        .sheet(isPresented: quizPresentationBinding) {
            if let quizQuestions {
                QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
                    .frame(minWidth: 560, minHeight: 640)
            }
        }
        #endif
    }

    private var quizPresentationBinding: Binding<Bool> {
        Binding(
            get: { quizQuestions != nil },
            set: { isPresented in if !isPresented { quizQuestions = nil } }
        )
    }
}
