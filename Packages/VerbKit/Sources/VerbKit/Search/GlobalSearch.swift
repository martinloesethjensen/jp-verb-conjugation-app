import Foundation

/// Which part of the app the Search tab looks in.
public enum SearchScope: String, CaseIterable, Sendable {
    case everything, verbs, grammar, counters, wordBank

    func includes(_ part: SearchScope) -> Bool { self == .everything || self == part }
}

/// What one search found, section by section, after the level setting.
public struct GlobalSearchResults: Sendable {
    public var verbs: [Verb]
    public var grammar: [GrammarPoint]
    public var counters: CounterSearchResults
    public var wordBank: [WordBankMatch]
    /// Matches the level setting left out (verbs, grammar points, counters and counter rows).
    public var hiddenCount: Int
    /// The levels of those matches, N5 first.
    public var hiddenLevels: [JLPTLevel]
    /// The kana the query was read as, when reading it as romaji found something the text alone did not.
    public var readingAs: String?

    public static let empty = GlobalSearchResults(
        verbs: [], grammar: [], counters: .empty, wordBank: [], hiddenCount: 0, hiddenLevels: [], readingAs: nil
    )

    /// No shown results (there may still be hidden ones).
    public var isEmpty: Bool { count == 0 }

    public var count: Int {
        verbs.count + grammar.count + counters.groups.count + counters.counters.count + counters.forms.count
            + counters.things.count + wordBank.count
    }
}

/// One search over verbs, grammar, counters and the Word Bank, for the Search tab. Each part uses its
/// own search (`matchesSearch`, `searched(for:)`, `searchCounters`, `WordBankSearchIndex`), so a query
/// finds the same things here as in that part's tab.
public enum GlobalSearch {
    /// Where the Search tab keeps its recent searches (`RecentSearches` of `WordBankQuery(text:)`), on this
    /// device only and apart from the Word Bank's own.
    public static let recentsKey = "search.recentQueries"

    /// - Parameter extraVerbs: verbs found another way, such as a conjugated form the form lookup reads
    ///   (飲んだ → 飲む); added after the text matches, once each.
    public static func results(
        for query: String, scope: SearchScope, levels: LevelSettings,
        verbs: [Verb], grammar: [GrammarPoint], counters: [Counter], groups: [CounterGroup],
        wordBank: WordBankSearchIndex?, furigana: FuriganaDictionary?, extraVerbs: [Verb] = []
    ) -> GlobalSearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: \.isLetter) else { return .empty }

        var results = GlobalSearchResults.empty
        var hidden: [any Leveled] = []

        if scope.includes(.verbs) {
            var matched = verbs.filter { matchesSearch($0, query: trimmed) }
            let ids = Set(matched.map(\.id))
            matched += extraVerbs.filter { !ids.contains($0.id) }.uniqued(by: \.id)
            results.verbs = matched.filter { $0.isVisible(in: levels) }
            hidden += matched.filter { !$0.isVisible(in: levels) } as [any Leveled]
        }
        if scope.includes(.grammar) {
            let matched = grammar.searched(for: trimmed, furigana: furigana)
            results.grammar = matched.filter { $0.isVisible(in: levels) }
            hidden += matched.filter { !$0.isVisible(in: levels) } as [any Leveled]
        }
        if scope.includes(.counters) {
            let found = searchCounters(counters, groups: groups, query: trimmed)
            let visibleThings = found.things.compactMap { match -> CounterThingMatch? in
                let shown = match.counters.filter { $0.isVisible(in: levels) }
                return shown.isEmpty ? nil : CounterThingMatch(thing: match.thing, counters: shown)
            }
            results.counters = CounterSearchResults(
                groups: found.groups,
                counters: found.counters.filter { $0.isVisible(in: levels) },
                forms: found.forms.filter { $0.counter.isVisible(in: levels) },
                things: visibleThings
            )
            hidden += found.counters.filter { !$0.isVisible(in: levels) } as [any Leveled]
            hidden += found.forms.map(\.counter).filter { !$0.isVisible(in: levels) } as [any Leveled]
            hidden += found.things.filter { match in !match.counters.contains { $0.isVisible(in: levels) } }
                .compactMap(\.counters.first) as [any Leveled]
        }
        if scope.includes(.wordBank), let wordBank {
            results.wordBank = wordBank.search(WordBankQuery(text: trimmed))
        }

        results.hiddenCount = hidden.count
        results.hiddenLevels = hidden.reduce(into: Set<JLPTLevel>()) { $0.formUnion($1.levelsTaught) }.sorted()
        results.readingAs = reading(of: trimmed, scope: scope, verbs: verbs, grammar: grammar,
                                    counters: counters, groups: groups)
        return results
    }

    /// The query as kana, when it reads as romaji and the kana finds a verb, grammar point or counter
    /// (any level) that the query's own text does not: "nomu" → のむ, but not "make" for まけ unless
    /// まけ finds something "make" in English does not.
    static func reading(
        of query: String, scope: SearchScope, verbs: [Verb], grammar: [GrammarPoint],
        counters: [Counter], groups: [CounterGroup]
    ) -> String? {
        guard query.contains(where: { $0.isASCII && $0.isLetter }),
              let kana = Romaji.toHiragana(query)?.filter({ !$0.isWhitespace }), !kana.isEmpty
        else { return nil }
        func plain(_ text: String) -> Bool { text.localizedCaseInsensitiveContains(query) }

        if scope.includes(.verbs) {
            let byText = Set(verbs.filter { verb in
                plain(verb.dict) || verb.kanji.map(plain) == true || plain(verb.meaning)
                    || verb.collocations.contains { plain($0.en) || plain($0.jp) }
            }.map(\.id))
            if verbs.contains(where: { !byText.contains($0.id) && matchesSearch($0, query: kana) }) { return kana }
        }
        if scope.includes(.grammar) {
            func byText(_ point: GrammarPoint) -> Bool {
                ([point.title, point.summary] + point.keywords).contains(where: plain)
                    || point.usages.contains { usage in
                        plain(usage.heading) || usage.examples.contains { plain($0.jp) || plain($0.en) }
                    }
            }
            if grammar.contains(where: { !byText($0) && grammarSearchRank($0, query: kana) != nil }) { return kana }
        }
        if scope.includes(.counters), !searchCounters(counters, groups: groups, query: kana).isEmpty {
            return kana
        }
        return nil
    }
}

private extension Sequence {
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
