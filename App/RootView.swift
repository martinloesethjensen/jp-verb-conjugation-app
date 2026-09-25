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
        } else {
            DataLoadingView(state: verbStore.firstLaunchState) {
                Task { await verbStore.retryFirstLaunch() }
            }
        }
    }
}
