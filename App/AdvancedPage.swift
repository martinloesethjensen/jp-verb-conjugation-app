import SwiftUI
import VerbKit

/// The optional advanced forms (volitional, passive, causative, conditionals,
/// imperative, たい, and the everyday ないで / てもいい / なければならない family),
/// generated into the data by scripts/update_data.py. The row that opens
/// this page stays hidden for a verb that has none (ある has only some).
struct AdvancedPage: View {
    let verb: Verb

    private var rows: [FormTableRow] {
        let f = verb.forms
        let all: [(String, String?)] = [
            ("Volitional", f.volitional),
            ("Passive", f.passive),
            ("Causative", f.causative),
            ("Causative-passive", f.causativePassive),
            ("Causative-passive (short)", f.causativePassiveShort),
            ("Conditional (ば)", f.conditionalBa),
            ("Conditional (たら)", f.conditionalTara),
            ("Imperative (blunt)", f.imperative),
            ("たい (want to)", f.tai),
            ("Polite volitional (ましょう)", f.masuVolitional),
            ("Negative て-form (ないで)", f.negTe),
            ("Negative て-form (なくて)", f.nakute),
            ("Permission (てもいい)", f.teMoIi),
            ("Prohibition (てはいけない)", f.teWaIkenai),
            ("Casual prohibition (ちゃだめ)", f.teChaDame),
            ("Obligation (なければならない)", f.nakerebaNaranai),
            ("Obligation (なくてはいけない)", f.nakuteWaIkenai),
            ("Casual obligation (なきゃ)", f.nakya),
            ("Casual obligation (なくちゃ)", f.nakucha),
            ("Not necessary (なくてもいい)", f.nakuteMoIi),
            ("Negative imperative (〜な, blunt)", f.negImperative),
            ("Soft command (なさい)", f.nasai),
            ("Conditional (と)", f.conditionalTo),
            ("Conditional (なら)", f.conditionalNara),
        ]
        return all.compactMap { label, value in
            value.map { FormTableRow(label: label, values: [$0]) }
        }
    }

    var body: some View {
        ScrollView {
            FormTable(columns: ["Form"], rows: rows, dict: verb.dict)
                .padding()
        }
        .navigationTitle(VerbSubPage.advanced.title)
    }
}

extension VerbForms {
    /// True when at least one advanced form is populated.
    var hasAdvancedForms: Bool {
        [volitional, passive, causative, causativePassive, causativePassiveShort, conditionalBa,
         conditionalTara, imperative, tai, masuVolitional, negTe, nakute, teMoIi, teWaIkenai,
         teChaDame, nakerebaNaranai, nakuteWaIkenai, nakya, nakucha, nakuteMoIi, negImperative,
         nasai, conditionalTo, conditionalNara]
            .contains { $0 != nil }
    }
}
