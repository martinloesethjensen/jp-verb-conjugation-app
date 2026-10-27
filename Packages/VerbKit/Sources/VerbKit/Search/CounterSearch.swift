import Foundation

/// A counted form found by search: 本 at 3 (三本, さんぼん).
public struct CounterFormMatch: Equatable, Sendable {
    public var counter: Counter
    public var number: CounterNumber
    /// The accepted reading that matched, or the preferred one when the written form matched.
    public var reading: String
}

/// A thing found by search, with every counter that lists it, primary fit first.
public struct CounterThingMatch: Equatable, Sendable {
    public var thing: CountedThing
    public var counters: [Counter]
}

public struct CounterSearchResults: Equatable, Sendable {
    public var groups: [CounterGroup]
    public var counters: [Counter]
    public var forms: [CounterFormMatch]
    public var things: [CounterThingMatch]

    public var isEmpty: Bool {
        groups.isEmpty && counters.isEmpty && forms.isEmpty && things.isEmpty
    }

    public static let empty = CounterSearchResults(groups: [], counters: [], forms: [], things: [])
}

/// The most form rows a search returns.
private let maxFormRows = 20

/// Kana that, typed alone or as a prefix, would match every counter at some number (さん finds
/// every counter at 3). A hiragana query that is a prefix of one of these matches no forms.
private let noisyFormPrefixes = [
    "いち", "に", "さん", "よん", "し", "ご", "ろく", "なな", "しち", "はち", "きゅう", "く", "じゅう", "なん",
    "いっ", "ろっ", "はっ", "じゅっ", "じっ",
    "にじゅう", "さんじゅう", "よんじゅう", "ごじゅう", "ろくじゅう", "ななじゅう", "はちじゅう", "きゅうじゅう",
    "ひゃく", "ひゃっ",
]

/// Searches everything in the Counters tab: groups, counters, counted forms and things.
/// Each section keeps data order. An empty query gives empty results (the home screen then
/// shows the groups grid instead).
///
/// - Groups: the title or summary contains the query, or a member counter matches.
/// - Counters: the counter or its reading equals the query, or the meaning contains it.
/// - Forms: the written form equals the query (3本 and 三本 both work), or the query, as
///   hiragana or romaji of at least 2 kana, starts one of the accepted readings at that number.
/// - Things: the word or kana equals the query, or the meaning contains it.
public func searchCounters(_ counters: [Counter], groups: [CounterGroup], query: String) -> CounterSearchResults {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .empty }

    let written = kanjiNumerals(in: trimmed)
    let kana = kanaQuery(for: trimmed)

    let matchedCounters = counters.filter { counter in
        counter.counter == trimmed
            || (kana != nil && counter.reading == kana)
            || counter.meaning.localizedCaseInsensitiveContains(trimmed)
    }
    let matchedCounterIDs = Set(matchedCounters.map(\.id))

    let matchedGroups = groups.filter { group in
        group.title.localizedCaseInsensitiveContains(trimmed)
            || group.summary.localizedCaseInsensitiveContains(trimmed)
            || group.members.contains { matchedCounterIDs.contains($0.counter) }
    }

    return CounterSearchResults(
        groups: matchedGroups,
        counters: matchedCounters,
        forms: formMatches(in: counters, written: written, kana: kana),
        things: thingMatches(in: counters, query: trimmed, kana: kana)
    )
}

private func formMatches(in counters: [Counter], written: String, kana: String?) -> [CounterFormMatch] {
    let usableKana: String? = kana.flatMap { kana in
        kana.count >= 2 && !noisyFormPrefixes.contains { $0.hasPrefix(kana) } ? kana : nil
    }
    var matches: [CounterFormMatch] = []
    for counter in counters {
        for number in CounterNumber.allCases + counter.extendedNumbers {
            let readings = counter.readings(for: number)
            if counter.written(number) == written {
                matches.append(CounterFormMatch(counter: counter, number: number, reading: readings.first ?? ""))
            } else if let usableKana, let hit = readings.first(where: { $0.hasPrefix(usableKana) }) {
                matches.append(CounterFormMatch(counter: counter, number: number, reading: hit))
            }
            if matches.count == maxFormRows { return matches }
        }
    }
    return matches
}

private func thingMatches(in counters: [Counter], query: String, kana: String?) -> [CounterThingMatch] {
    var order: [String] = []
    var entries: [String: [(counter: Counter, thing: CountedThing)]] = [:]
    for counter in counters {
        for thing in counter.things where thingMatches(thing, query: query, kana: kana) {
            if entries[thing.word] == nil { order.append(thing.word) }
            entries[thing.word, default: []].append((counter, thing))
        }
    }
    return order.compactMap { word in
        // A word listed under a counter is listed under every counter, not only where it matched.
        let all = counters.flatMap { counter in
            counter.things.filter { $0.word == word }.map { (counter: counter, thing: $0) }
        }
        let sorted = all.enumerated()
            .sorted { ($0.element.thing.fit.rank, $0.offset) < ($1.element.thing.fit.rank, $1.offset) }
            .map(\.element)
        guard let first = sorted.first else { return nil }
        return CounterThingMatch(thing: first.thing, counters: sorted.map(\.counter))
    }
}

private func thingMatches(_ thing: CountedThing, query: String, kana: String?) -> Bool {
    if thing.word == query { return true }
    if let kana, hiragana(thing.kana) == kana { return true }
    return thing.meaning.localizedCaseInsensitiveContains(query)
}

/// The query as hiragana when it is romaji or kana, else nil.
private func kanaQuery(for query: String) -> String? {
    if let converted = Romaji.toHiragana(query) {
        return converted.filter { !$0.isWhitespace }
    }
    let kana = hiragana(query).filter { !$0.isWhitespace }
    let isKana = !kana.isEmpty && kana.allSatisfy { character in
        character == "ー" || character.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) }
    }
    return isKana ? kana : nil
}

private func hiragana(_ text: String) -> String {
    text.applyingTransform(.hiraganaToKatakana, reverse: true) ?? text
}

/// "3本" -> "三本", "15分" -> "十五分", "3000円" -> "三千円", "何本" unchanged. Full-width digits too. 1 to 10000.
func kanjiNumerals(in query: String) -> String {
    let ascii = query.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? query
    var result = ""
    var digits = ""
    func flush() {
        if let value = Int(digits), (1...10_000).contains(value), digits.first != "0" {
            result += CounterNumber.n(value).kanji
        } else {
            result += digits
        }
        digits = ""
    }
    for character in ascii {
        if character.isASCII, character.isNumber {
            digits.append(character)
        } else {
            flush()
            result.append(character)
        }
    }
    flush()
    return result
}
