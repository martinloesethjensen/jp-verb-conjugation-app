/// Finds a verb form inside an example sentence, so the sentence can underline it.
public enum FormHighlight {
    /// The character offsets of `form` (a kana form, as published) in `sentence`: first as the
    /// verb's kanji spelling (たべます → 食べます, こない → 来ない), then as written in kana.
    /// Nil when the sentence contains neither.
    public static func range(of form: String, for verb: Verb, in sentence: String) -> Range<Int>? {
        let candidates = [KanjiSpelling(verb)?.spell(form), form].compactMap { $0 }
        for candidate in candidates where !candidate.isEmpty {
            if let found = sentence.range(of: candidate) {
                let start = sentence.distance(from: sentence.startIndex, to: found.lowerBound)
                return start..<(start + candidate.count)
            }
        }
        return nil
    }
}
