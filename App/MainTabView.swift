import SwiftUI
import VerbKit

enum AppTab: Hashable {
    case verbs
    case grammar
}

/// Verbs and Grammar as two tabs, each its own `NavigationSplitView`
/// (list/detail at regular width, a stack on iPhone). Also owns the
/// `openRoute` action, so a verb page can jump to a lesson and a lesson
/// can jump to a related one.
struct MainTabView<VerbsTab: View>: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var verbSelection: Verb?
    @Binding var incomingRoute: Route?
    @State private var tab: AppTab = .verbs
    @State private var grammarSelection: GrammarPoint?
    /// On iPhone a `NavigationSplitView` shows its list until told
    /// otherwise; `open` sets this to `.detail` so a cross-link lands on
    /// the lesson even when the Grammar tab hasn't been visited yet.
    @State private var grammarColumn: NavigationSplitViewColumn = .sidebar
    private let verbsTab: VerbsTab

    init(verbSelection: Binding<Verb?>, incomingRoute: Binding<Route?>, @ViewBuilder verbsTab: () -> VerbsTab) {
        _verbSelection = verbSelection
        _incomingRoute = incomingRoute
        self.verbsTab = verbsTab()
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Verbs", systemImage: "character.book.closed", value: AppTab.verbs) {
                verbsTab
            }
            Tab("Grammar", systemImage: "text.book.closed", value: AppTab.grammar) {
                GrammarTab(selection: $grammarSelection, preferredColumn: $grammarColumn)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.openRoute, OpenRouteAction { open($0) })
        .onChange(of: incomingRoute, initial: true) { _, route in
            guard let route else { return }
            open(route)
            incomingRoute = nil
        }
    }

    private func open(_ route: Route) {
        switch route.resolve(verbs: verbStore.verbs, grammarPoints: verbStore.grammarPoints) {
        case let .verb(verb)?:
            verbSelection = verb
            tab = .verbs
        case let .grammar(point)?:
            grammarSelection = point
            grammarColumn = .detail
            tab = .grammar
        case nil:
            break
        }
    }
}

struct GrammarTab: View {
    @Binding var selection: GrammarPoint?
    @Binding var preferredColumn: NavigationSplitViewColumn

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            GrammarListView(selection: $selection)
        } detail: {
            if let selection {
                GrammarDetailView(point: selection)
            } else {
                ContentUnavailableView("Select a Grammar Point", systemImage: "text.book.closed")
            }
        }
    }
}
