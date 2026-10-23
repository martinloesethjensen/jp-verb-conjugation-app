/// Spells a verb's kana forms the way real text writes them: kanji stem plus okurigana.
/// The data stores every form in kana only (たべさせられる), but sentences, pasted text
/// and speech output write 食べさせられる.
///
/// The okurigana is the kana ending that `kanji` and `dict` share (食べる / たべる share
/// べる), so the rest is the stem pair: 食 is read た. A form that starts with the reading
/// stem swaps it for the kanji stem. 来る is the one verb whose stem changes reading
/// (きます, こない), so a kanji stem ending in 来 accepts き and こ as well as く.
public struct KanjiSpelling: Hashable, Sendable {
    /// The written stem: 食, 来, 引っ越.
    public let kanjiStem: String
    /// The readings of `kanjiStem` a form can start with: [た], or [く, き, こ] for 来.
    public let readingStems: [String]

    /// Nil when there is no kanji spelling to derive: no `kanji` (する, ある), or one
    /// that is all okurigana.
    public init?(kanji: String?, dict: String) {
        guard let kanji, kanji != dict else { return nil }
        let shared = zip(kanji.reversed(), dict.reversed()).prefix { $0 == $1 }.count
        let kanjiStem = String(kanji.dropLast(shared))
        let readingStem = String(dict.dropLast(shared))
        guard !kanjiStem.isEmpty, !readingStem.isEmpty else { return nil }
        self.kanjiStem = kanjiStem
        if kanjiStem.hasSuffix("来"), readingStem.hasSuffix("く") {
            let base = readingStem.dropLast()
            readingStems = ["く", "き", "こ"].map { base + $0 }
        } else {
            readingStems = [readingStem]
        }
    }

    public init?(_ verb: Verb) {
        self.init(kanji: verb.kanji, dict: verb.dict)
    }

    /// The kanji spelling of `kana`, one of the verb's forms or a stem of one
    /// (たべさせられ → 食べさせられ). Nil when it doesn't start with a reading of the stem.
    public func spell(_ kana: String) -> String? {
        for reading in readingStems where kana.hasPrefix(reading) {
            return kanjiStem + kana.dropFirst(reading.count)
        }
        return nil
    }
}
