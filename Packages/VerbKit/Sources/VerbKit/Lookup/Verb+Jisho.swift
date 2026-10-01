extension Verb {
    /// What to search for in a dictionary: the kanji spelling when the verb has
    /// one (見せる), otherwise the kana dictionary form (する).
    public var jishoQuery: String {
        guard let kanji, !kanji.trimmingCharacters(in: .whitespaces).isEmpty else { return dict }
        return kanji
    }
}
