import os

/// One thing the quiz can ask about: a form of a verb, with the label the quiz
/// shows for it. Comes from the form catalogue, so a form a synced catalogue adds reaches
/// the quiz without an app release.
public struct QuizForm: Hashable, Sendable {
    /// The form's JSON key, e.g. "pot_masu_past".
    public let id: String
    public let topic: QuizTopic
    /// The catalogue's label: "Potential · polite · past".
    public let label: String

    public init(id: String, topic: QuizTopic, label: String) {
        self.id = id
        self.topic = topic
        self.label = label
    }

    /// The form's string for a verb, or nil when the verb has none (nil or empty).
    public func value(in forms: VerbForms) -> String? {
        guard let value = forms[id: FormID(rawValue: id)], !value.isEmpty else { return nil }
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

    /// Every verb form of the catalogue in use (`FormCatalogue.current`).
    public static var all: [QuizForm] {
        let catalogue = FormCatalogue.current
        return cache.withLock { cached in
            if let cached, cached.sha256 == catalogue.sha256 { return cached.forms }
            let forms = forms(in: catalogue)
            cached = (catalogue.sha256, forms)
            return forms
        }
    }

    private static let cache = OSAllocatedUnfairLock<(sha256: String, forms: [QuizForm])?>(initialState: nil)

    /// The verb forms of `catalogue` the quiz can ask about: grouped by family in the
    /// catalogue's family order, each family in catalogue order. A family without a quiz
    /// topic (one this build does not know) is left out.
    public static func forms(in catalogue: FormCatalogue) -> [QuizForm] {
        let verbForms = catalogue.specs(for: .verb)
        return catalogue.families.flatMap { family -> [QuizForm] in
            guard let topic = QuizTopic(family: family.id) else { return [] }
            return verbForms
                .filter { $0.family == family.id }
                .map { QuizForm(id: $0.id.rawValue, topic: topic, label: $0.label) }
        }
    }
}
