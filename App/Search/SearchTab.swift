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
    /// The last finished search. It stays on screen while the next one runs, so typing doesn't flash.
    @State private var shown: ShownResults?

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var recents: RecentSearches { RecentSearches(rawValue: recentsRaw) }

    /// Everything a search reads. A change to any of it starts a new search (`.task(id:)`); the data
    /// arrays compare by identity first, so an unchanged store costs almost nothing to compare.
    private var request: SearchRequest {
        SearchRequest(
            query: trimmed, scope: scope,
            levels: levelScope == .mine ? LevelSettings(rawValue: hiddenLevelsRaw) : LevelSettings(),
            verbs: verbStore.verbs, grammar: verbStore.grammarPoints,
            counters: countersStore.counters, groups: countersStore.groups,
            furigana: furigana.dictionary, formLookupReady: formLookup?.isReady == true,
            wordBankEntries: wordBank.entries, wordBankFolders: wordBank.folders,
            dialectTags: wordBank.dialectTags, customTags: wordBank.customTags
        )
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .paperBackground()
                .navigationTitle("Search")
                #if os(iOS)
                // The empty state draws the title with 検索 and its furigana; the bar stays for the field.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .title)
                #endif
        }
        .searchable(text: $query, prompt: "Search everything")
        .onSubmit(of: .search) { record() }
        .onChange(of: GlobalSearch.isSearchable(trimmed)) { _, searchable in
            if !searchable { levelScope = .mine }
        }
        .task(id: request) { await search(request) }
    }

    /// Runs `request` off the main actor after a short pause, so a burst of typing searches once. A newer
    /// request cancels this one (`.task(id:)`), and a cancelled search never replaces the results.
    private func search(_ request: SearchRequest) async {
        guard GlobalSearch.isSearchable(request.query) else {
            shown = nil
            return
        }
        // Typing waits; a scope or level change (same query) answers at once.
        if shown?.query != request.query {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
        }
        // Both are main-actor stores; the index is cached and the form lookup is quick.
        let dictionary = request.furigana
        let index = wordBank.searchIndex(readingKey: dictionary?.readings.count ?? 0) { dictionary?.reading(of: $0) }
        let extra = (formLookup?.items(in: request.query) ?? []).flatMap(\.verbs)
        let results = await Task.detached(priority: .userInitiated) {
            GlobalSearch.results(
                for: request.query, scope: request.scope, levels: request.levels,
                verbs: request.verbs, grammar: request.grammar,
                counters: request.counters, groups: request.groups,
                wordBank: index, furigana: dictionary, extraVerbs: extra
            )
        }.value
        guard !Task.isCancelled else { return }
        shown = ShownResults(query: request.query, results: results)
    }

    @ViewBuilder
    private var content: some View {
        if !GlobalSearch.isSearchable(trimmed) {
            SearchEmptyState(
                scope: $scope,
                recents: recents.items.map(\.text),
                onPick: { query = $0 },
                onClear: { updateRecents { $0.clear() } }
            )
        } else if let shown {
            let results = shown.results
            if results.isEmpty && results.hiddenCount == 0 {
                VStack(spacing: 12) {
                    SearchScopeChips(scope: $scope).padding(.top, 12)
                    ContentUnavailableView {
                        Label { JapaneseText(SearchDisplay.noResults(shown.query)) } icon: { Image(systemName: "magnifyingglass") }
                    }
                }
            } else {
                SearchResultsList(
                    query: shown.query, results: results, scope: $scope,
                    onShowHidden: { levelScope = .all },
                    open: open
                )
            }
        } else {
            // The first search of this query is still running.
            Color.clear
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
        guard GlobalSearch.isSearchable(trimmed) else { return }
        updateRecents { $0.record(WordBankQuery(text: trimmed)) }
    }

    private func updateRecents(_ change: (inout RecentSearches) -> Void) {
        var updated = recents
        change(&updated)
        recentsRaw = updated.rawValue
    }
}

/// What the Search tab searches with; see `SearchTab.request`.
private struct SearchRequest: Equatable, Sendable {
    var query: String
    var scope: SearchScope
    var levels: LevelSettings
    var verbs: [Verb]
    var grammar: [GrammarPoint]
    var counters: [Counter]
    var groups: [CounterGroup]
    var furigana: FuriganaDictionary?
    var formLookupReady: Bool
    var wordBankEntries: [WordBankEntryValue]
    var wordBankFolders: [WordBankFolderValue]
    var dialectTags: [DialectTagValue]
    var customTags: [CustomTagValue]
}

/// A finished search and the query it was for (the field may already say something newer).
private struct ShownResults {
    var query: String
    var results: GlobalSearchResults
}
