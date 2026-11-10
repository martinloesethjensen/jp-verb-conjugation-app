/// How the verb quiz writes a verb and its forms, picked in the quiz sheet and kept in the App
/// Group defaults under `defaultsKey`. Only verb forms change: form names, example sentences and
/// the other quizzes are written as they always were.
public enum QuizScript: String, CaseIterable, Sendable {
    /// Kana, with the dictionary form's kanji as a hint: the quiz as it always was.
    case kana
    /// The verb's kanji with its reading above, whatever the app's furigana setting.
    case kanjiWithFurigana
    /// The verb's kanji with no reading until the question is answered.
    case kanjiOnly

    public static let defaultsKey = "quizScript"

    /// The stored value, or `.kana` when it is missing or unknown.
    public init(storedValue: String) {
        self = QuizScript(rawValue: storedValue) ?? .kana
    }

    /// False for `.kana`, which keeps the kana headword with its kanji hint.
    public var usesKanji: Bool { self != .kana }

    /// `kana`, one of `verb`'s forms (or a made-up form starting like one), written in this
    /// script. A verb without kanji, or a form that doesn't start with a reading of the stem,
    /// stays in kana. `revealed` shows the reading in `.kanjiOnly`, once the question is answered.
    public func units(for kana: String, of verb: Verb, revealed: Bool = false) -> [TextUnit] {
        switch self {
        case .kana:
            return [TextUnit(text: kana)]
        case .kanjiWithFurigana:
            return verb.units(for: kana)
        case .kanjiOnly:
            let units = verb.units(for: kana)
            return revealed ? units : units.map { TextUnit(text: $0.text) }
        }
    }

    /// `units(for:of:)` as plain text, for lines with no room for readings.
    public func text(for kana: String, of verb: Verb) -> String {
        units(for: kana, of: verb).map(\.text).joined()
    }
}

public extension QuizQuestion {
    /// The verb `choice` is a form of: the question's verb, or another verb for a distractor
    /// taken from another verb's forms.
    func verb(of choice: String) -> Verb {
        choiceVerbs[choice] ?? verb
    }
}
