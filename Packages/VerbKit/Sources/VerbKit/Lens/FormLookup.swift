import Foundation

/// "What form is this?" (#110): turns the matcher's spans into what the result view shows.
/// Each span becomes an `Item` with its readings labelled from the catalogue, the chain
/// parts that say which ones the tail rules built, and the lessons to link to. The Sentence
/// lens tap sheet (#147) and the derivation strip (#115) show the same items.
public struct FormLookup: Sendable {
    /// One part of a chain, labelled: 食べさせられ "Causative-passive", なかった "Plain · past ·
    /// negative" (built by rule).
    public struct Part: Hashable, Sendable {
        public let surface: String
        public let label: String
        /// The `GrammarPoint.id` of the part's form, when the catalogue names one.
        public let lessonID: String?
        public let isRuleBuilt: Bool
    }

    /// One way to read a span: this verb, in this form, built from these parts.
    public struct Reading: Hashable, Sendable, Identifiable {
        public let verb: Verb
        /// The catalogue form when the span is exactly one generated form; nil for a chain.
        public let formID: FormID?
        /// "Polite · past", or the part labels joined for a chain: "Causative-passive +
        /// Plain · past · negative".
        public let label: String
        public let parts: [Part]
        /// The lessons of the parts' forms, without repeats, in chain order.
        public let lessonIDs: [String]

        public var id: String { verb.id + "|" + parts.map { $0.surface + "/" + $0.label }.joined(separator: "+") }
        public var isRuleBuilt: Bool { parts.contains(where: \.isRuleBuilt) }
        /// True for the plain dictionary form itself (食べる), which needs no lookup.
        public var isDictionaryForm: Bool { formID == "short_pos" }
    }

    /// One verb found in the text.
    public struct Item: Hashable, Sendable, Identifiable {
        /// The span as the matcher found it, for callers that need its range.
        public let span: VerbSpan
        /// For `.known` one reading; for `.ambiguous` every reading, for the learner to
        /// choose; for `.notInApp` none.
        public let readings: [Reading]

        public var id: String { span.surface + "@" + String(describing: span.range.lowerBound) }
        public var surface: String { span.surface }
        public var status: VerbSpan.Status { span.status }
        /// For `.notInApp`, the probable dictionary forms, best first.
        public var guesses: [String] { span.guesses }
        /// The distinct verbs of the readings, in order.
        public var verbs: [Verb] {
            var seen = Set<String>()
            return readings.map(\.verb).filter { seen.insert($0.id).inserted }
        }
    }

    private let verbsByID: [String: Verb]
    private let catalogue: FormCatalogue

    public init(verbs: [Verb], catalogue: FormCatalogue) {
        self.verbsByID = Dictionary(verbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.catalogue = catalogue
    }

    /// The items for `spans`, in order. A candidate whose verb isn't in `verbs` is left out;
    /// a span left with no readings that way is dropped rather than shown empty.
    public func items(for spans: [VerbSpan]) -> [Item] {
        spans.compactMap { span in
            let readings = span.candidates.compactMap(reading)
            if span.status != .notInApp, readings.isEmpty { return nil }
            return Item(span: span, readings: readings)
        }
    }

    /// The label the catalogue gives a chain part.
    public func label(for part: ChainPart) -> String {
        switch part.kind {
        case .form(let id): catalogue.spec(for: id)?.label ?? id.rawValue
        case .stem: "ます stem (purpose)"
        case .auxiliary(let label): label
        }
    }

    /// The lesson of a part's form. An auxiliary the catalogue has no form id for
    /// ("てしまう · polite past") takes the lesson of the catalogue form it names (てしまう).
    private func lessonID(for part: ChainPart) -> String? {
        switch part.kind {
        case .form(let id):
            return catalogue.spec(for: id)?.grammar
        case .auxiliary(let label):
            let name = label.components(separatedBy: " · ").first
            return catalogue.forms.first { $0.name == name && $0.grammar != nil }?.grammar
        case .stem:
            return nil
        }
    }

    private func reading(for candidate: VerbCandidate) -> Reading? {
        guard let verb = verbsByID[candidate.verbID] else { return nil }
        let parts = candidate.chain.map { part in
            Part(surface: part.surface, label: label(for: part), lessonID: lessonID(for: part), isRuleBuilt: part.isRuleBuilt)
        }
        var seen = Set<String>()
        let lessons = parts.compactMap(\.lessonID).filter { seen.insert($0).inserted }
        return Reading(
            verb: verb, formID: candidate.formID,
            label: parts.map(\.label).joined(separator: " + "),
            parts: parts, lessonIDs: lessons
        )
    }

    // MARK: Word Bank

    /// The verbs to offer as the dictionary form of `text` in the Word Bank editor: when
    /// the whole text is one conjugated verb the app has (食べさせられなかった → 食べる).
    /// Empty when the text is a sentence, isn't a verb, or already is the dictionary form.
    public static func dictionaryForms(of text: String, in items: [Item]) -> [Verb] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard items.count == 1, let item = items.first, item.status != .notInApp,
              item.surface == trimmed.filter({ !$0.isWhitespace })
        else { return [] }
        return item.verbs.filter { verb in trimmed != verb.dict && trimmed != verb.kanji }
    }
}

public extension Verb {
    /// The dictionary form as ruby units: the kanji stem with its reading, then the
    /// okurigana (食 over た, then べる). Kana alone for a verb without kanji (する).
    var dictionaryUnits: [TextUnit] {
        guard let kanji, let spelling = KanjiSpelling(self), let reading = spelling.readingStems.first else {
            return [TextUnit(text: dict)]
        }
        return [
            TextUnit(text: spelling.kanjiStem, reading: reading),
            TextUnit(text: String(kanji.dropFirst(spelling.kanjiStem.count))),
        ].filter { !$0.text.isEmpty }
    }
}
