import SwiftUI
import VerbKit

extension QuizScript {
    /// The choice's name in the quiz sheet's "Show verbs as" picker.
    var title: String {
        switch self {
        case .kana: "Kana"
        case .kanjiWithFurigana: "Kanji with furigana"
        case .kanjiOnly: "Kanji only"
        }
    }

    /// The picker's footer for this choice.
    var explanation: String {
        switch self {
        case .kana: "Verbs are written in kana, with the kanji as a hint."
        case .kanjiWithFurigana: "Verbs are written with their kanji, the reading above."
        case .kanjiOnly: "Verbs are written with their kanji. The reading shows once you answer."
        }
    }
}

/// One of a verb's forms in the verb quiz, written in the script picked in the quiz sheet
/// (`QuizScript`). Kana is plain `Text`; the kanji scripts always draw their own readings,
/// whatever the app's furigana setting, since the readings are part of the choice. Style it
/// like `Text`.
struct QuizVerbText: View {
    let kana: String
    let verb: Verb
    /// The question is answered: Kanji only shows the reading too.
    var revealed = false
    @AppStorage(QuizScript.defaultsKey, store: .appGroup) private var scriptRaw = QuizScript.kana.rawValue

    var body: some View {
        let script = QuizScript(storedValue: scriptRaw)
        if script.usesKanji {
            JapaneseText(units: script.units(for: kana, of: verb, revealed: revealed))
                .environment(\.furiganaEnabled, true)
        } else {
            Text(kana)
        }
    }
}
