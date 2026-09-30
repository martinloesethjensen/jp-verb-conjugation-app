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
    @Environment(\.furiganaEnabled) private var enabled
    @Environment(\.furiganaDictionary) private var dictionary
    @Environment(\.multilineTextAlignment) private var alignment
    @Environment(\.lineLimit) private var lineLimit

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        let units = enabled ? (dictionary?.units(for: text) ?? []) : []
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
        } else {
            Text(text)
        }
    }

    private struct UnitView: View {
        let unit: TextUnit

        var body: some View {
            if let reading = unit.reading {
                RubyPairLayout {
                    Text(reading).lineLimit(1).fixedSize().scaleEffect(RubyPairLayout.scale)
                    Text(unit.text).lineLimit(1).fixedSize()
                }
            } else {
                Text(unit.text).lineLimit(1).fixedSize()
            }
        }
    }
}
