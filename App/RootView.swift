import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore
    @State private var selection: Verb?
    @State private var showingExamples = false
    @State private var quizQuestions: [QuizQuestion]?

    var body: some View {
        if verbStore.hasLocalData {
            NavigationSplitView {
                VerbListView(selection: $selection)
            } detail: {
                if let selection {
                    VerbDetailView(
                        verb: selection,
                        onExamples: { showingExamples = true },
                        onQuiz: { quizQuestions = buildQuestions(verbs: [selection], count: 9) }
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
        } else {
            DataLoadingView(state: verbStore.firstLaunchState) {
                Task { await verbStore.retryFirstLaunch() }
            }
        }
    }

    private var quizPresentationBinding: Binding<Bool> {
        Binding(
            get: { quizQuestions != nil },
            set: { isPresented in if !isPresented { quizQuestions = nil } }
        )
    }
}
