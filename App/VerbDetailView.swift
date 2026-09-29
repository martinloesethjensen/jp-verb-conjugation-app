import SwiftUI
import VerbKit

struct VerbDetailView: View {
    let verb: Verb
    var onExamples: () -> Void
    var onQuiz: () -> Void

    private var accent: Color {
        verb.teGroup?.accentColor ?? verb.type.accentColor
    }

    private var jishoURL: URL {
        let encoded = verb.dict.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verb.dict
        return URL(string: "https://jisho.org/search/\(encoded)")!
    }

    private var hasAdvancedForms: Bool {
        let f = verb.forms
        return [f.potential, f.volitional, f.passive, f.causative, f.causativePassive, f.conditionalBa, f.conditionalTara, f.imperative, f.tai]
            .contains { $0 != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                if let notes = verb.notes {
                    notesBox(notes)
                }
                Text(verb.description)
                    .font(.body)
                formGroups
            }
            .padding()
        }
        .navigationTitle(verb.dict)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verb.label)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .foregroundStyle(verb.type.accentColor)
                    .glassEffect(.regular.tint(verb.type.accentColor.opacity(0.7)), in: Capsule())
                if let teGroup = verb.teGroup {
                    Text(teGroup.rawValue)
                        .font(.caption)
                        .foregroundStyle(teGroup.accentColor)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verb.dict).font(.system(size: 34, weight: .heavy)).foregroundStyle(accent)
                if let kanji = verb.kanji {
                    Text(kanji).font(.title2).foregroundStyle(.secondary)
                }
            }
            Text(verb.meaning).font(.headline).foregroundStyle(.secondary).italic()
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Examples", systemImage: "book", action: onExamples)
            Button("Test this verb", systemImage: "gamecontroller", action: onQuiz)
                .buttonStyle(.glassProminent)
                .tint(accent)
            Link(destination: jishoURL) {
                Label("Jisho", systemImage: "link")
            }
        }
        .buttonStyle(.glass)
    }

    private func notesBox(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
            Text(notes).font(.footnote)
        }
        .padding(12)
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    private var formGroups: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormGroupSection(title: "Polite", forms: [
                ("ます (polite +)", verb.forms.masuPos),
                ("ません (polite −)", verb.forms.masuNeg),
                ("ました (polite past +)", verb.forms.masuPast),
                ("ませんでした (polite past −)", verb.forms.masuPastNeg),
            ], defaultExpanded: true)

            FormGroupSection(title: "Plain", forms: [
                ("short (present +)", verb.forms.shortPos),
                ("short (present −)", verb.forms.shortNeg),
                ("short (past +)", verb.forms.shortPast),
                ("short (past −)", verb.forms.shortPastNeg),
            ], defaultExpanded: true)

            FormGroupSection(title: "て-form", forms: [
                ("て-form", verb.forms.te),
            ], defaultExpanded: true)

            if hasAdvancedForms {
                FormGroupSection(
                    title: "Advanced",
                    forms: [
                        ("Potential", verb.forms.potential),
                        ("Volitional", verb.forms.volitional),
                        ("Passive", verb.forms.passive),
                        ("Causative", verb.forms.causative),
                        ("Causative-passive", verb.forms.causativePassive),
                        ("Conditional (ば)", verb.forms.conditionalBa),
                        ("Conditional (たら)", verb.forms.conditionalTara),
                        ("Imperative", verb.forms.imperative),
                        ("たい (want to)", verb.forms.tai),
                    ].compactMap { label, value in value.map { (label, $0) } },
                    defaultExpanded: false
                )
            }

            if verb.forms.hasNdForms {
                NdesuFormsSection(forms: verb.forms)
            }
        }
    }
}
