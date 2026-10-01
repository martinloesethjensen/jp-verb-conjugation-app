import Foundation

public func matchesSearch(_ verb: Verb, query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }

    if verb.dict.contains(trimmed) { return true }
    if let kanji = verb.kanji, kanji.contains(trimmed) { return true }
    if verb.meaning.localizedCaseInsensitiveContains(trimmed) { return true }
    for key in FormKey.allCases where verb.forms[key].contains(trimmed) {
        return true
    }
    if let converted = Romaji.toHiragana(trimmed) {
        let kana = converted.filter { !$0.isWhitespace }   // "atama ga itai" -> あたまがいたい
        if verb.dict.contains(kana) { return true }
        for key in FormKey.allCases where verb.forms[key].contains(kana) {
            return true
        }
    }
    return false
}

public func matchesType(_ verb: Verb, filter: VerbType?) -> Bool {
    guard let filter else { return true }
    return verb.type == filter
}

public func matchesTeGroup(_ verb: Verb, filter: TeGroup?) -> Bool {
    guard let filter else { return true }
    return verb.teGroup == filter
}
