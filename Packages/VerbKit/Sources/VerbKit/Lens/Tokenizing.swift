import Foundation

/// A word of a sentence as a morphological tokenizer splits it: 食べ / させ / られ / なかっ / た.
/// The Sentence lens (#142) only lets a verb start and end where a token does, which keeps
/// 十分かかります from holding 借ります.
public struct Token: Hashable, Sendable {
    public let range: Range<String.Index>
    public let surface: String
    /// The token's reading in hiragana (入れ → いれ), or nil when the tokenizer gives none.
    /// Tokenizers slip on some words (私 → わたくし, 日本 → にっぽん), so the matcher only
    /// uses a reading to choose between verbs the spelling can't tell apart.
    public let reading: String?

    public init(range: Range<String.Index>, surface: String, reading: String?) {
        self.range = range
        self.surface = surface
        self.reading = reading
    }
}

/// Splits a sentence into tokens, in order, skipping punctuation and spaces. A protocol so
/// tests can inject fixed tokens, independent of the OS tokenizer's version, and Android
/// can bring its own (Kuromoji).
public protocol Tokenizing: Sendable {
    func tokens(in text: String) -> [Token]
}

/// `CFStringTokenizer` with the Japanese locale: correct morpheme boundaries plus a Latin
/// transcription, turned into a hiragana reading. `NLTagger` is no use here; it returns no
/// lemma and tags every Japanese token `OtherWord`. CoreFoundation keeps VerbKit
/// platform-neutral.
public struct SystemTokenizer: Tokenizing {
    public init() {}

    public func tokens(in text: String) -> [Token] {
        let string = text as CFString
        let length = CFStringGetLength(string)
        guard length > 0,
              let tokenizer = CFStringTokenizerCreate(
                nil, string, CFRangeMake(0, length), kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale
              )
        else { return [] }
        var tokens: [Token] = []
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard let range = Range(NSRange(location: cfRange.location, length: cfRange.length), in: text) else { continue }
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            let reading = latin?.applyingTransform(.latinToHiragana, reverse: false)
            tokens.append(Token(range: range, surface: String(text[range]), reading: reading?.isEmpty == false ? reading : nil))
        }
        return tokens
    }
}
