import SwiftUI
import VerbKit

/// A form learners get wrong. Not colour alone: a ✗, strikethrough and a spoken "wrong".
struct WrongForm: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "xmark").font(.caption.weight(.bold)).accessibilityHidden(true)
            JapaneseText(text)
                .strikethrough()
        }
        .foregroundStyle(.red)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wrong: \(text)")
    }
}

/// The だ / です table.
struct CopulaSection: View {
    var body: some View {
        Section {
            DisclosureGroup("だ / です (plain and polite)", isExpanded: .constant(true)) {
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
            }
        } header: {
            Text("Plain · Polite")
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
                block(Text("い-adjective"), rows: rows)
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
                        Text("The past goes on the い-adjective, not on です.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let naAdjective, let rows = PoliteForms.rows(for: naAdjective) {
                block(Text("な-adjective"), rows: rows)
            }
        } header: {
            Text("Polite adjectives")
        } footer: {
            Text("Words change with the example words above.")
        }
    }

    private func block(_ title: Text, rows: [PolitePair]) -> some View {
        DisclosureGroup(isExpanded: .constant(true)) {
            ForEach(rows, id: \.label) { row in
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack {
                            JapaneseText(row.polite).font(.title3.weight(.semibold))
                            SpeakButton(text: row.polite)
                        }
                        if let alt = row.politeAlt {
                            JapaneseText(alt).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(row.label)
                        JapaneseText(row.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            title
        }
    }
}
