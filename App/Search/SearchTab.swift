import SwiftUI
import VerbKit

/// The Search tab: one field over verbs, grammar, counters and the Word Bank (`GlobalSearch`), with
/// scope chips, recent searches and, when the level setting hides matches, a row to show them for this
/// search. Results open in their own tab.
struct SearchTab: View {
    let openWordBankEntry: (UUID) -> Void

    @Environment(VerbStore.self) private var verbStore
    @Environment(CountersStore.self) private var countersStore
    @Environment(WordBankStore.self) private var wordBank
    @Environment(FuriganaStore.self) private var furigana
    @Environment(FormLookupStore.self) private var formLookup: FormLookupStore?
    @Environment(\.openRoute) private var openRoute
    @Environment(\.palette) private var palette
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @AppStorage(GlobalSearch.recentsKey) private var recentsRaw = Data()

    @State private var query = ""
    @State private var scope: SearchScope = .everything
    @State private var levelScope: LevelScope = .mine

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recents: RecentSearches { RecentSearches(rawValue: recentsRaw) }

    private var results: GlobalSearchResults {
        let dictionary = furigana.dictionary
        let index = wordBank.searchIndex(readingKey: dictionary?.readings.count ?? 0) { dictionary?.reading(of: $0) }
        let extra = (formLookup?.items(in: trimmed) ?? []).flatMap(\.verbs)
        return GlobalSearch.results(
            for: trimmed, scope: scope,
            levels: levelScope == .mine ? LevelSettings(rawValue: hiddenLevelsRaw) : LevelSettings(),
            verbs: verbStore.verbs, grammar: verbStore.grammarPoints,
            counters: countersStore.counters, groups: countersStore.groups,
            wordBank: index, furigana: dictionary, extraVerbs: extra
        )
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .paperBackground()
                .navigationTitle("Search")
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
        }
        .searchable(text: $query, prompt: "Search everything")
        .onSubmit(of: .search) { record() }
        .onChange(of: trimmed.isEmpty) { _, isEmpty in
            if isEmpty { levelScope = .mine }
        }
    }

    @ViewBuilder
    private var content: some View {
        if trimmed.isEmpty {
            SearchEmptyState(
                scope: $scope,
                recents: recents.items.map(\.text),
                onPick: { query = $0 },
                onClear: { updateRecents { $0.clear() } }
            )
        } else {
            let results = results
            if results.isEmpty && results.hiddenCount == 0 {
                VStack(spacing: 12) {
                    SearchScopeChips(scope: $scope).padding(.top, 12)
                    ContentUnavailableView(SearchDisplay.noResults(trimmed), systemImage: "magnifyingglass")
                }
            } else {
                SearchResultsList(
                    query: trimmed, results: results, scope: $scope,
                    onShowHidden: { levelScope = .all },
                    open: open
                )
            }
        }
    }

    private func open(_ destination: SearchDestination) {
        record()
        switch destination {
        case let .route(route): openRoute(route)
        case let .wordBankEntry(id): openWordBankEntry(id)
        }
    }

    private func record() {
        updateRecents { $0.record(WordBankQuery(text: trimmed)) }
    }

    private func updateRecents(_ change: (inout RecentSearches) -> Void) {
        var updated = recents
        change(&updated)
        recentsRaw = updated.rawValue
    }
}
