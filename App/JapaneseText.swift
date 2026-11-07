import SwiftUI
import VerbKit

/// A drop-in replacement for `Text` for strings that may contain kanji: with
/// furigana on, readings are drawn above the kanji the dictionary knows.
///
/// It is plain `Text` whenever there is nothing to annotate (furigana is off,
/// the dictionary hasn't loaded, or no kanji in the string has a reading), so
/// kana-only strings keep SwiftUI's normal wrapping. Callers style it like a
/// `Text`: `.font`, `.foregroundStyle`, `.bold()`, `.multilineTextAlignment`
/// and `.lineLimit` all come through the environment.
struct JapaneseText: View {
    private let text: String
    /// Readings given by the caller instead of looked up (a verb's own dictionary form).
    private let fixedUnits: [TextUnit]?
    /// Characters drawn bold and underlined (the verb form in an example sentence).
    private let emphasis: Range<Int>?
    @Environment(\.furiganaEnabled) private var enabled
    @Environment(\.furiganaDictionary) private var dictionary
    @Environment(\.multilineTextAlignment) private var alignment
    @Environment(\.lineLimit) private var lineLimit
    @Environment(\.palette) private var palette

    init(_ text: String) {
        self.init(text, emphasizing: nil)
    }

    /// `text` with the characters in `emphasizing` bold and underlined in ink, with furigana on
    /// or off. `nil` draws it like `init(_:)`.
    init(_ text: String, emphasizing: Range<Int>?) {
        self.text = text
        self.fixedUnits = nil
        self.emphasis = emphasizing
    }

    /// `units` already carry their readings; they still follow the furigana setting.
    init(units: [TextUnit]) {
        self.text = units.map(\.text).joined()
        self.fixedUnits = units
        self.emphasis = nil
    }

    var body: some View {
        let looked = enabled ? (fixedUnits ?? dictionary?.units(for: text) ?? []) : []
        let units = emphasis.map { TextUnit.emphasizing(looked, characters: $0) } ?? looked
        if units.contains(where: { $0.reading != nil }) {
            let flow = RubyFlowLayout(glue: units.map(\.glueToPrevious), alignment: alignment, maxLines: lineLimit) {
                ForEach(units.indices, id: \.self) { index in
                    UnitView(unit: units[index])
                }
            }
            if lineLimit != nil {
                flow.clipped()
            } else {
                flow
            }
        } else if let emphasis, let parts = Self.split(text, at: emphasis) {
            Text("\(Text(parts.before))\(Text(parts.middle).bold().underline(color: palette.ink))\(Text(parts.after))")
        } else {
            Text(text)
        }
    }

    /// `text` cut around `range` (clamped), or nil when the clamped range is empty.
    private static func split(_ text: String, at range: Range<Int>) -> (before: String, middle: String, after: String)? {
        let chars = Array(text)
        let lower = min(max(range.lowerBound, 0), chars.count)
        let upper = min(max(range.upperBound, lower), chars.count)
        guard lower < upper else { return nil }
        return (String(chars[..<lower]), String(chars[lower..<upper]), String(chars[upper...]))
    }

    private struct UnitView: View {
        let unit: TextUnit
        @Environment(\.palette) private var palette

        var body: some View {
            if let reading = unit.reading {
                RubyPairLayout {
                    Text(reading).lineLimit(1).fixedSize().scaleEffect(RubyPairLayout.scale)
                    base
                }
            } else {
                base
            }
        }

        /// The emphasised base is bold and underlined; its reading above stays plain.
        private var base: some View {
            Text(unit.text)
                .bold(unit.isEmphasized)
                .underline(unit.isEmphasized, color: palette.ink)
                .lineLimit(1)
                .fixedSize()
        }
    }
}
