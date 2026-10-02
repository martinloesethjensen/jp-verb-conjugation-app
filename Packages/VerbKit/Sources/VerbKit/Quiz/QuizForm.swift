/// One thing the quiz can ask about: a form of a verb, with the label the quiz
/// shows for it and the way to read it from a verb's `VerbForms`.
public struct QuizForm: Hashable, Sendable {
    /// The form's JSON key, e.g. "pot_masu_past".
    public let id: String
    public let topic: QuizTopic
    /// Built from parts: "Potential · polite · past".
    public let label: String
    private let read: @Sendable (VerbForms) -> String?

    /// The form's string for a verb, or nil when the verb has none (nil or empty).
    public func value(in forms: VerbForms) -> String? {
        guard let value = read(forms), !value.isEmpty else { return nil }
        return value
    }

    public static func == (a: QuizForm, b: QuizForm) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The forms of these topics that `forms` actually has, in catalogue order.
    public static func available(
        in forms: VerbForms, topics: Set<QuizTopic>
    ) -> [(form: QuizForm, value: String)] {
        all.compactMap { form in
            guard topics.contains(form.topic), let value = form.value(in: forms) else { return nil }
            return (form, value)
        }
    }

    private static func make(
        _ id: String, _ topic: QuizTopic, name: String?, register: String?,
        past: Bool = false, negative: Bool = false,
        _ read: @escaping @Sendable (VerbForms) -> String?
    ) -> QuizForm {
        let label = [name, register, past ? "past" : nil, negative ? "negative" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
        return QuizForm(id: id, topic: topic, label: label, read: read)
    }

    public static let all: [QuizForm] = [
        // Basic: the name is left out, so the labels read "Polite · past".
        make("masu_pos", .basic, name: nil, register: "Polite") { $0.masuPos },
        make("masu_neg", .basic, name: nil, register: "Polite", negative: true) { $0.masuNeg },
        make("masu_past", .basic, name: nil, register: "Polite", past: true) { $0.masuPast },
        make("masu_past_neg", .basic, name: nil, register: "Polite", past: true, negative: true) { $0.masuPastNeg },
        make("te", .basic, name: nil, register: "て-form") { $0.te },
        make("short_pos", .basic, name: nil, register: "Plain") { $0.shortPos },
        make("short_neg", .basic, name: nil, register: "Plain", negative: true) { $0.shortNeg },
        make("short_past", .basic, name: nil, register: "Plain", past: true) { $0.shortPast },
        make("short_past_neg", .basic, name: nil, register: "Plain", past: true, negative: true) { $0.shortPastNeg },

        // Potential
        make("potential", .potential, name: "Potential", register: "plain") { $0.potential },
        make("pot_masu_pos", .potential, name: "Potential", register: "polite") { $0.potMasuPos },
        make("pot_masu_neg", .potential, name: "Potential", register: "polite", negative: true) { $0.potMasuNeg },
        make("pot_masu_past", .potential, name: "Potential", register: "polite", past: true) { $0.potMasuPast },
        make("pot_masu_past_neg", .potential, name: "Potential", register: "polite", past: true, negative: true) { $0.potMasuPastNeg },
        make("pot_te", .potential, name: "Potential", register: "て-form") { $0.potTe },
        make("pot_short_neg", .potential, name: "Potential", register: "plain", negative: true) { $0.potShortNeg },
        make("pot_short_past", .potential, name: "Potential", register: "plain", past: true) { $0.potShortPast },
        make("pot_short_past_neg", .potential, name: "Potential", register: "plain", past: true, negative: true) { $0.potShortPastNeg },

        // んです
        make("nd_pos", .nDesu, name: "んです", register: "polite") { $0.ndPos },
        make("nd_neg", .nDesu, name: "んです", register: "polite", negative: true) { $0.ndNeg },
        make("nd_past", .nDesu, name: "んです", register: "polite", past: true) { $0.ndPast },
        make("nd_past_neg", .nDesu, name: "んです", register: "polite", past: true, negative: true) { $0.ndPastNeg },
        make("nd_casual_pos", .nDesu, name: "んです", register: "casual") { $0.ndCasualPos },
        make("nd_casual_neg", .nDesu, name: "んです", register: "casual", negative: true) { $0.ndCasualNeg },
        make("nd_casual_past", .nDesu, name: "んです", register: "casual", past: true) { $0.ndCasualPast },
        make("nd_casual_past_neg", .nDesu, name: "んです", register: "casual", past: true, negative: true) { $0.ndCasualPastNeg },

        // Auxiliaries: ている in full, then a plain and a polite form for most, ながら alone.
        make("teiru", .auxiliaries, name: "ている", register: "plain") { $0.teiru },
        make("teiru_neg", .auxiliaries, name: "ている", register: "plain", negative: true) { $0.teiruNeg },
        make("teiru_past", .auxiliaries, name: "ている", register: "plain", past: true) { $0.teiruPast },
        make("teiru_past_neg", .auxiliaries, name: "ている", register: "plain", past: true, negative: true) { $0.teiruPastNeg },
        make("teiru_masu_pos", .auxiliaries, name: "ている", register: "polite") { $0.teiruMasuPos },
        make("teiru_masu_neg", .auxiliaries, name: "ている", register: "polite", negative: true) { $0.teiruMasuNeg },
        make("teiru_masu_past", .auxiliaries, name: "ている", register: "polite", past: true) { $0.teiruMasuPast },
        make("teiru_masu_past_neg", .auxiliaries, name: "ている", register: "polite", past: true, negative: true) { $0.teiruMasuPastNeg },
        make("teiru_te", .auxiliaries, name: "ている", register: "て-form") { $0.teiruTe },
        make("teshimau", .auxiliaries, name: "てしまう", register: "plain") { $0.teshimau },
        make("teshimau_polite", .auxiliaries, name: "てしまう", register: "polite") { $0.teshimauPolite },
        make("teoku", .auxiliaries, name: "ておく", register: "plain") { $0.teoku },
        make("teoku_polite", .auxiliaries, name: "ておく", register: "polite") { $0.teokuPolite },
        make("temiru", .auxiliaries, name: "てみる", register: "plain") { $0.temiru },
        make("temiru_polite", .auxiliaries, name: "てみる", register: "polite") { $0.temiruPolite },
        make("sugiru", .auxiliaries, name: "すぎる", register: "plain") { $0.sugiru },
        make("sugiru_polite", .auxiliaries, name: "すぎる", register: "polite") { $0.sugiruPolite },
        make("yasui", .auxiliaries, name: "やすい", register: "plain") { $0.yasui },
        make("yasui_polite", .auxiliaries, name: "やすい", register: "polite") { $0.yasuiPolite },
        make("nikui", .auxiliaries, name: "にくい", register: "plain") { $0.nikui },
        make("nikui_polite", .auxiliaries, name: "にくい", register: "polite") { $0.nikuiPolite },
        make("nagara", .auxiliaries, name: "ながら", register: nil) { $0.nagara },

        // More forms: one string each.
        make("volitional", .otherForms, name: "Volitional", register: nil) { $0.volitional },
        make("passive", .otherForms, name: "Passive", register: nil) { $0.passive },
        make("causative", .otherForms, name: "Causative", register: nil) { $0.causative },
        make("causative_passive", .otherForms, name: "Causative-passive", register: nil) { $0.causativePassive },
        make("conditional_ba", .otherForms, name: "Conditional (ば)", register: nil) { $0.conditionalBa },
        make("conditional_tara", .otherForms, name: "Conditional (たら)", register: nil) { $0.conditionalTara },
        make("imperative", .otherForms, name: "Imperative", register: nil) { $0.imperative },
        make("tai", .otherForms, name: "たい (want to)", register: nil) { $0.tai },
    ]
}
