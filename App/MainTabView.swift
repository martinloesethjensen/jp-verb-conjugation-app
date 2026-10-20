import SwiftUI
import VerbKit

enum AppTab: Hashable {
    case verbs
    case grammar
    case counters
    case wordBank
}

/// Verbs, Grammar, Counters and the Word Bank as four tabs, each its own `NavigationSplitView`
/// (list/detail at regular width, a stack on iPhone). Also owns the
/// `openRoute` action, so a verb page can jump to a lesson and a lesson
/// can jump to a related one.
struct MainTabView<VerbsTab: View>: View {
    @Environment(VerbStore.self) private var verbStore
    @Environment(CountersStore.self) private var countersStore
    @Environment(WordBankTransferHub.self) private var wordBankTransfer
    @Binding var verbSelection: Verb?
    @Binding var incomingRoute: Route?
    @State private var tab: AppTab = .verbs
    @State private var grammarSelection: GrammarPoint?
    /// On iPhone a `NavigationSplitView` shows its list until told
    /// otherwise; `open` sets this to `.detail` so a cross-link lands on
    /// the lesson even when the Grammar tab hasn't been visited yet.
    @State private var grammarColumn: NavigationSplitViewColumn = .sidebar
    @State private var counterDestination: CounterDestination?
    @State private var counterColumn: NavigationSplitViewColumn = .sidebar
    @State private var wordBankSelection: UUID?
    @State private var wordBankColumn: NavigationSplitViewColumn = .sidebar
    let onSettings: () -> Void
    private let verbsTab: VerbsTab

    init(verbSelection: Binding<Verb?>, incomingRoute: Binding<Route?>, onSettings: @escaping () -> Void, @ViewBuilder verbsTab: () -> VerbsTab) {
        _verbSelection = verbSelection
        _incomingRoute = incomingRoute
        self.onSettings = onSettings
        self.verbsTab = verbsTab()
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Verbs", systemImage: "character.book.closed", value: AppTab.verbs) {
                verbsTab
            }
            Tab("Grammar", systemImage: "text.book.closed", value: AppTab.grammar) {
                GrammarTab(selection: $grammarSelection, preferredColumn: $grammarColumn, onSettings: onSettings)
            }
            Tab("Counters", systemImage: "textformat.123", value: AppTab.counters) {
                CountersTab(destination: $counterDestination, preferredColumn: $counterColumn, onSettings: onSettings)
            }
            Tab("Word Bank", systemImage: "books.vertical", value: AppTab.wordBank) {
                WordBankTab(selection: $wordBankSelection, preferredColumn: $wordBankColumn, onSettings: onSettings)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.openRoute, OpenRouteAction { open($0) })
        .onChange(of: wordBankTransfer.pendingImport?.id, initial: true) { _, id in
            if id != nil { tab = .wordBank }
        }
        .onChange(of: incomingRoute, initial: true) { _, route in
            guard let route else { return }
            open(route)
            incomingRoute = nil
        }
    }

    private func open(_ route: Route) {
        let target = route.resolve(
            verbs: verbStore.verbs, grammarPoints: verbStore.grammarPoints,
            counters: countersStore.counters, groups: countersStore.groups
        )
        switch target {
        case let .verb(verb)?:
            verbSelection = verb
            tab = .verbs
        case let .grammar(point)?:
            grammarSelection = point
            grammarColumn = .detail
            tab = .grammar
        case let .counter(counter)?:
            counterDestination = .counter(counter, focus: nil)
            counterColumn = .detail
            tab = .counters
        case let .counterGroup(group)?:
            counterDestination = .group(group)
            counterColumn = .detail
            tab = .counters
        case nil:
            break
        }
    }
}

struct GrammarTab: View {
    @Binding var selection: GrammarPoint?
    @Binding var preferredColumn: NavigationSplitViewColumn
    let onSettings: () -> Void

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredColumn) {
            GrammarListView(selection: $selection, onSettings: onSettings)
        } detail: {
            if let selection {
                GrammarDetailView(point: selection)
            } else {
                ContentUnavailableView("Select a Grammar Point", systemImage: "text.book.closed")
            }
        }
    }
}
