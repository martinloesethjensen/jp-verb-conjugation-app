import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore

    var body: some View {
        if verbStore.hasLocalData {
            // Task 12 replaces this placeholder with the real
            // search/filter/navigation shell.
            List(verbStore.verbs) { verb in
                Text(verb.dict)
            }
        } else {
            DataLoadingView(state: verbStore.firstLaunchState) {
                Task { await verbStore.retryFirstLaunch() }
            }
        }
    }
}
