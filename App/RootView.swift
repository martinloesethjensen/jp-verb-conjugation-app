import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore
    @State private var selection: Verb?

    var body: some View {
        if verbStore.hasLocalData {
            NavigationSplitView {
                VerbListView(selection: $selection)
            } detail: {
                // Task 13 replaces this placeholder with the real
                // VerbDetailView (forms, description, examples/quiz/Jisho).
                if let selection {
                    Text(selection.dict)
                        .font(.largeTitle)
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
