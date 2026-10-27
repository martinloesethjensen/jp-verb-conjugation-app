extension Verb {
    /// `form`, one of this verb's kana forms, as written with the verb's kanji: 食べます for
    /// たべます, 行って for いって, 来ます for きます. Nil when the verb has no kanji, or when
    /// `form` does not start with the verb's kana stem.
    ///
    /// The stem is the part of `dict` that `kanji` writes in kanji (た of たべる for 食べる). An
    /// irregular verb's stem changes its vowel (く, き, こ for 来る), so there the form's first
    /// characters are replaced whatever they are.
    public func kanjiSpelling(of form: String) -> String? {
        guard let kanji, !kanji.isEmpty, kanji != dict else { return nil }
        let okurigana = zip(kanji.reversed(), dict.reversed()).prefix { $0 == $1 }.count
        let kanjiStem = kanji.dropLast(okurigana)
        let kanaStem = dict.dropLast(okurigana)
        guard !kanjiStem.isEmpty, !kanaStem.isEmpty, form.count > kanaStem.count else { return nil }
        guard type == .irregular || form.hasPrefix(kanaStem) else { return nil }
        return String(kanjiStem) + form.dropFirst(kanaStem.count)
    }
}
