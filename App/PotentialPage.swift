import SwiftUI
import VerbKit

/// The verb's potential form large, how it is made, its nine potential forms plain and
/// polite, its potential examples, and the link to the lesson.
struct PotentialPage: View {
    let verb: Verb
    @Environment(\.palette) private var palette

    private var rows: [FormTableRow] {
        let f = verb.forms
        return [
            FormTableRow(label: "present +", values: [f.potential, f.potMasuPos]),
            FormTableRow(label: "present −", values: [f.potShortNeg, f.potMasuNeg]),
            FormTableRow(label: "past +", values: [f.potShortPast, f.potMasuPast]),
            FormTableRow(label: "past −", values: [f.potShortPastNeg, f.potMasuPastNeg]),
            FormTableRow(label: "て-form", values: [f.potTe, nil]),
        ]
    }

    private var potentialExamples: [VerbExample] {
        verb.examples.filter { $0.form.rawValue.hasPrefix("pot") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VerbSubPageHeader(verb: verb, title: VerbSubPage.potential.title, headline: verb.forms.potential)
                if let potential = verb.forms.potential, let pattern = PotentialPattern(verb: verb) {
                    howItsMade(potential: potential, pattern: pattern)
                }
                FormTable(columns: ["Plain", "Polite"], rows: rows, dict: verb.dict)
                if !potentialExamples.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Examples")
                        VerbExampleCard(examples: potentialExamples, verb: verb)
                    }
                }
                LessonLinks(ids: [GrammarPoint.potentialID])
            }
            .padding()
        }
        .verbSubPage(title: VerbSubPage.potential.title)
    }

    private func howItsMade(potential: String, pattern: PotentialPattern) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW IT’S MADE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.muted)
            // Each side split against the other, so each bolds its own ending.
            // Side by side while it fits; stacked with a down arrow at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    FormCell(form: verb.dict, dict: potential).fixedSize()
                    arrow("arrow.right")
                    FormCell(form: potential, dict: verb.dict).fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    FormCell(form: verb.dict, dict: potential)
                    arrow("arrow.down")
                    FormCell(form: potential, dict: verb.dict)
                }
            }
            .font(.title3)
            Text(explanation(potential: potential, pattern: pattern))
                .font(.subheadline)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .paperCard()
    }

    private func arrow(_ name: String) -> some View {
        Image(systemName: name)
            .foregroundStyle(palette.muted)
            .accessibilityLabel("becomes")
    }

    private func explanation(potential: String, pattern: PotentialPattern) -> String {
        switch pattern {
        case .ru:
            return "Ru-verbs drop る and add られる. The result conjugates like a ru-verb itself."
        case .u:
            let dictEnding = FormSplit.split(verb.dict, from: potential).ending
            let potEnding = FormSplit.split(potential, from: verb.dict).ending
            return "U-verbs change the final \(dictEnding) to \(potEnding.dropLast()) and add る. The result conjugates like a ru-verb."
        case .suru:
            return "する becomes できる. The result conjugates like a ru-verb."
        case .kuru:
            return "くる becomes こられる. The result conjugates like a ru-verb."
        }
    }
}
