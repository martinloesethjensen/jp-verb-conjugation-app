import SwiftUI
import VerbKit

/// A form learners get wrong. Not colour alone: a ✗, strikethrough and a spoken "wrong". With
/// `right` (a correct example), only the part that differs (`MistakeMark`) is red and struck through;
/// without it, the whole form is.
struct WrongForm: View {
    let text: String
    var right: String?

    @Environment(\.palette) private var palette

    private var parts: (before: String, wrong: String, after: String) {
        let range = MistakeMark.wrongRange(wrong: text, right: right)
        let characters = Array(text)
        return (String(characters[..<range.lowerBound]), String(characters[range]),
                String(characters[range.upperBound...]))
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(palette.mark)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if !parts.before.isEmpty { JapaneseText(parts.before).foregroundStyle(palette.ink) }
                JapaneseText(parts.wrong).strikethrough(color: palette.mark).foregroundStyle(palette.mark)
                if !parts.after.isEmpty { JapaneseText(parts.after).foregroundStyle(palette.ink) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wrong: \(text)")
    }
}

/// The correct counterpart to a `WrongForm`: a ✓ in `good` and the sentence in ink.
struct RightForm: View {
    let text: String

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(palette.good)
                .accessibilityHidden(true)
            JapaneseText(text).font(.sentence(.body)).foregroundStyle(palette.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Right: \(text)")
    }
}

/// The だ / です table.
struct CopulaSection: View {
    var body: some View {
        Section {
            ForEach(Copula.rows, id: \.label) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.label).font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        cell(row.plain, alt: row.plainAlt, speak: false)
                        Spacer()
                        cell(row.polite, alt: row.politeAlt, speak: true)
                    }
                    if let note = row.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .contain)
            }
            ForEach(Copula.notes, id: \.self) { note in
                JapaneseText(note).font(.callout).foregroundStyle(.secondary)
            }
        } header: {
            Text("だ / です (plain · polite)")
        }
    }

    private func cell(_ text: String, alt: String?, speak: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                JapaneseText(text).font(.title3.weight(.semibold))
                if speak { SpeakButton(text: text) }
            }
            if let alt {
                JapaneseText(alt).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Polite adjective rows for the い- and な-adjective model words, with the ×高いでした trap.
struct PoliteAdjectiveSection: View {
    let iAdjective: SlotSource?
    let naAdjective: SlotSource?

    var body: some View {
        Section {
            if let iAdjective, let rows = PoliteForms.rows(for: iAdjective) {
                block(Text("い\u{2060}-adjective"), rows: rows)
                if let trap = PoliteForms.trap(for: iAdjective) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(trap.wrong, id: \.self) { WrongForm(text: $0) }
                        ForEach(trap.right, id: \.self) { right in
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark").font(.caption.weight(.bold))
                                    .accessibilityHidden(true)
                                JapaneseText(right)
                                SpeakButton(text: right)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Correct: \(right)")
                        }
                        Text("The past goes on the い\u{2060}-adjective, not on です.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let naAdjective, let rows = PoliteForms.rows(for: naAdjective) {
                block(Text("な\u{2060}-adjective"), rows: rows)
            }
        } header: {
            Text("Polite adjectives")
        } footer: {
            Text("Words change with the example words above.")
        }
    }

    private func block(_ title: Text, rows: [PolitePair]) -> some View {
        Group {
            title.font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows, id: \.label) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.label).font(.caption).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top) {
                            plainCell(row)
                            Spacer()
                            politeCell(row)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            plainCell(row)
                            politeCell(row)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func plainCell(_ row: PolitePair) -> some View {
        JapaneseText(row.plain).font(.callout).foregroundStyle(.secondary)
    }

    private func politeCell(_ row: PolitePair) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                JapaneseText(row.polite).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                SpeakButton(text: row.polite)
            }
            if let alt = row.politeAlt {
                JapaneseText(alt).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
