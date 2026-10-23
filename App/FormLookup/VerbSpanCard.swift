import SwiftUI
import VerbKit

/// One verb found in typed or pasted text: which verb, which form and how it is built,
/// with links to the verb page and the lessons. For an ambiguous span it lists every
/// reading to choose from; for a verb the app lacks it says so, with guesses and links.
///
/// Shared by "What form is this?" (#110), the Sentence lens tap sheet (#147) and the
/// derivation strip (#115). Links go through `openRoute`, so a presenter that is a sheet
/// overrides it to dismiss first.
struct VerbSpanCard: View {
    let item: FormLookup.Item
    @State private var chosenID: String?

    private var chosen: FormLookup.Reading? {
        item.readings.first { $0.id == chosenID } ?? item.readings.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            switch item.status {
            case .notInApp:
                NotInAppSection(item: item)
            case .known, .ambiguous:
                if item.readings.count > 1 {
                    readingChoice
                }
                if let chosen {
                    ReadingDetail(reading: chosen)
                        // A new identity per reading, so VoiceOver re-reads it after a choice.
                        .id(chosen.id)
                }
            }
        }
        .formCard()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.surface)
                .font(.title2.weight(.bold))
                .textSelection(.enabled)
            Spacer(minLength: 0)
            switch item.status {
            case .known:
                EmptyView()
            case .ambiguous:
                Label("\(item.readings.count) readings", systemImage: "questionmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .notInApp:
                Label("Not in the app yet", systemImage: "circle.dashed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Every reading as a radio row; the chosen one is shown in full below.
    private var readingChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This could be any of these. Choose one:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(item.readings) { reading in
                let selected = reading.id == chosen?.id
                Button {
                    chosenID = reading.id
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(reading.verb.jishoQuery) · \(reading.label)")
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                            Text(reading.verb.meaning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// The verb, its form and the chain of one reading, then its links.
private struct ReadingDetail: View {
    let reading: FormLookup.Reading
    @Environment(\.openRoute) private var openRoute

    private var verb: Verb { reading.verb }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            verbHeader
            VStack(alignment: .leading, spacing: 4) {
                Text("Form")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(reading.label)
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
            if reading.parts.count > 1 {
                ChainView(parts: reading.parts)
            }
            Button {
                openRoute(.verb(verb.id))
            } label: {
                Label {
                    Text("Open \(verb.jishoQuery)")
                } icon: {
                    Image(systemName: "character.book.closed")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .font(.subheadline)
            LessonLinks(ids: reading.lessonIDs)
        }
    }

    private var verbHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(verb.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .accentPill(verb.type.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                JapaneseText(units: verb.dictionaryUnits)
                    .font(.title3.weight(.bold))
                Text(verb.meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(verbLabel)
    }

    /// "食べる, たべる, to eat, る-verb": the reading spelled out, since VoiceOver may misread kanji.
    private var verbLabel: String {
        [verb.kanji, verb.dict, verb.meaning, verb.label].compactMap { $0 }.joined(separator: ", ")
    }
}

/// 食べさせられ + なかった as chips, each with its label. A part the tail rules built says
/// "built by rule" in words and has a dashed outline, so the mark never relies on colour.
private struct ChainView: View {
    let parts: [FormLookup.Part]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How it's built")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            PillFlow(spacing: 6) {
                ForEach(parts.indices, id: \.self) { index in
                    if index > 0 {
                        Text("+")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                    }
                    chip(parts[index], position: index + 1)
                }
            }
            if parts.contains(where: \.isRuleBuilt) {
                Text("Parts built by rule come from the app's ending rules, not from the verb's form table.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chip(_ part: FormLookup.Part, position: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(part.surface)
                .font(.body.weight(.semibold))
            Text(part.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if part.isRuleBuilt {
                Label("built by rule", systemImage: "gearshape")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            let shape = RoundedRectangle(cornerRadius: 10)
            if part.isRuleBuilt {
                shape.strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                shape.fill(.secondary.opacity(0.12))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Part \(position) of \(parts.count): \(part.surface), \(part.label)" + (part.isRuleBuilt ? ", built by rule" : "")
        )
    }
}

/// A verb the app doesn't have: the guesses at its dictionary form, Jisho and the
/// "Suggest a verb" form.
private struct NotInAppSection: View {
    let item: FormLookup.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This looks like a verb the app doesn't have yet.")
                .font(.subheadline)
            if !item.guesses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dictionary form, probably:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    PillFlow(spacing: 6) {
                        ForEach(item.guesses, id: \.self) { guess in
                            if let url = TextLookupURL.jisho(guess) {
                                Link(destination: url) {
                                    Text(guess)
                                        .font(.body.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.glass)
                                .accessibilityLabel("\(guess), look up in Jisho")
                            }
                        }
                    }
                }
                Text("A guess from the spelling: check it in a dictionary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let url = TextLookupURL.jisho(item.surface) {
                Link(destination: url) {
                    Label("Look up “\(item.surface)” in Jisho", systemImage: "book")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
                .font(.subheadline)
            }
            Link(destination: IssueReportURL.suggestVerb(kanji: item.guesses.first)) {
                Label("Suggest this verb", systemImage: "plus.bubble")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.glass)
            .font(.subheadline)
        }
    }
}
