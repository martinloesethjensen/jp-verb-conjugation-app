import Foundation

/// A facet of a finite form: what a one-step transform flips.
public enum FormFacet: String, CaseIterable, Hashable, Sendable {
    /// Plain ⇄ polite (んだ ⇄ んです).
    case register
    /// Positive ⇄ negative.
    case polarity
    /// Present ⇄ past.
    case tense
}

/// Two catalogue forms one facet apart: `masu_past` → `masu_past_neg` flips the polarity.
public struct FormStep: Hashable, Sendable {
    public let facet: FormFacet
    public let from: FormID
    public let to: FormID

    public init(facet: FormFacet, from: FormID, to: FormID) {
        self.facet = facet
        self.from = from
        self.to = to
    }
}

/// Why a transform, or every transform of a span, isn't offered. The UI shows `message`.
public enum TransformReason: Hashable, Sendable {
    /// The span is greyed: the app doesn't have the verb.
    case notInApp
    /// The span is ambiguous and no reading has been picked.
    case chooseReading
    /// The form has no facet neighbour in the catalogue: a derived or connective form (て,
    /// volitional, passive…) or a chain built by rule. Explicit pairings are #148.
    case noOneStepTransform
    /// The catalogue has the target form, but the data has no surface for this verb.
    case notInData
    /// Register change on a verb that doesn't end the sentence.
    case midSentence
    /// A marker after the verb fixes its form: 前に, 後で.
    case fixedBy(marker: String)
    /// …の？ ⇄ …んですか: the explanatory question changes more than one form.
    case explanatory

    /// A short, user-facing reason, localisable from VerbKit's bundle.
    public var message: String {
        switch self {
        case .notInApp:
            String(localized: "Not in the app yet", bundle: .module)
        case .chooseReading:
            String(localized: "Choose a reading first", bundle: .module)
        case .noOneStepTransform:
            String(localized: "No one-step change for this form yet", bundle: .module)
        case .notInData:
            String(localized: "Not in the data for this verb", bundle: .module)
        case .midSentence:
            String(localized: "Mid-sentence: only the last verb changes politeness", bundle: .module)
        case .fixedBy(let marker):
            String(localized: "Before \(marker), the verb keeps this form", bundle: .module)
        case .explanatory:
            String(localized: "…の？ and …んですか are more than one step apart", bundle: .module)
        }
    }
}

/// Something the learner should know about a rewrite.
public enum TransformNote: Hashable, Sendable {
    /// A polite question became a plain one: the か was dropped for ？.
    case plainQuestion

    public var message: String {
        switch self {
        case .plainQuestion:
            String(localized: "Plain か sounds blunt: drop it and raise your intonation", bundle: .module)
        }
    }
}

/// A transformed sentence: one span (and, for a question, its か) replaced.
public struct SentenceRewrite: Hashable, Sendable {
    /// The verb in its new form, from the data: 飲みませんでした, 行く.
    public let surface: String
    /// What replaces `range`: `surface`, plus ？ where a plain question dropped its か, or
    /// か where a polite question needs one.
    public let replacement: String
    /// The range of the text passed in that `replacement` replaces: the span, or the span
    /// and its question か.
    public let range: Range<String.Index>
    /// The whole text with only `range` replaced.
    public let sentence: String
    public let note: TransformNote?
}

/// One transform chip: a facet step, rewritten or disabled with a reason.
public struct FormTransform: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case rewrite(SentenceRewrite)
        case disabled(TransformReason)
    }

    /// `Verb.id`, never `dict`.
    public let verbID: String
    public let step: FormStep
    public let outcome: Outcome

    public var rewrite: SentenceRewrite? {
        if case .rewrite(let rewrite) = outcome { return rewrite }
        return nil
    }

    public var disabledReason: TransformReason? {
        if case .disabled(let reason) = outcome { return reason }
        return nil
    }
}

/// The transforms of one span.
public enum SpanTransforms: Hashable, Sendable {
    /// One chip per facet step the catalogue has for the span's form, in register,
    /// polarity, tense order; some may be disabled.
    case available([FormTransform])
    /// No chips: the span is greyed, unresolved, or its form has no one-step neighbour.
    case unavailable(TransformReason)

    public var transforms: [FormTransform] {
        if case .available(let transforms) = self { return transforms }
        return []
    }
}

/// Flips one facet of a verb span: 食べました → 食べませんでした, 行きます → 行く (#146).
///
/// Two forms are one step apart when they're finite forms of the same family and name
/// (the ている grid, the potential grid…) and differ in exactly one of register, polarity
/// and tense. That covers the four finite grids (basic, んです, ている, potential) and
/// every other facet pair the catalogue has (てしまう ⇄ polite). Forms without a neighbour
/// (て, volitional, passive…) and chains built by rule have no transform until #148 and
/// #149. The catalogue is injected, so a synced one (#100) brings its pairs with no code
/// change.
///
/// Surfaces come from the data only (`verb.forms[target]`), in the script of the span:
/// a kanji span gets the `KanjiSpelling`. A verb without the target form gets a disabled
/// chip, never a guess. `SentenceContext` keeps register changes to the sentence-final
/// verb and handles the question か.
public struct FormTransformer: Sendable {
    private struct Entry: Sendable {
        let forms: Conjugations
        let spelling: KanjiSpelling?
    }

    private let catalogue: FormCatalogue
    private let entries: [String: Entry]
    private let stepsByForm: [FormID: [FormStep]]

    public init(verbs: [Verb], catalogue: FormCatalogue) {
        self.catalogue = catalogue
        var entries: [String: Entry] = [:]
        for verb in verbs {
            entries[verb.id] = Entry(forms: Word(verb).forms, spelling: KanjiSpelling(verb))
        }
        self.entries = entries
        stepsByForm = Self.steps(in: catalogue)
    }

    /// The one-step neighbours of `form`, in register, polarity, tense order; empty when
    /// it has none.
    public func steps(from form: FormID) -> [FormStep] {
        stepsByForm[form] ?? []
    }

    /// The transforms of `span`, found in `text`. An ambiguous span needs the `candidate`
    /// the learner picked; a known one uses its only candidate.
    public func transforms(for span: VerbSpan, in text: String, candidate: VerbCandidate? = nil) -> SpanTransforms {
        let chosen: VerbCandidate
        switch span.status {
        case .notInApp:
            return .unavailable(.notInApp)
        case .known, .ambiguous:
            if let candidate, span.candidates.contains(candidate) {
                chosen = candidate
            } else if candidate == nil, span.status == .known, let only = span.candidates.first {
                chosen = only
            } else {
                return .unavailable(.chooseReading)
            }
        }
        guard let source = chosen.formID else { return .unavailable(.noOneStepTransform) }
        let steps = steps(from: source)
        guard !steps.isEmpty else { return .unavailable(.noOneStepTransform) }
        guard let entry = entries[chosen.verbID], let kana = entry.forms[source] else {
            return .unavailable(.notInData)
        }
        let isKanji = span.surface != kana && entry.spelling?.spell(kana) == span.surface
        let context = SentenceContext(span: span.range, in: text)
        return .available(steps.map { step in
            FormTransform(verbID: chosen.verbID, step: step, outcome: outcome(
                of: step, entry: entry, kanji: isKanji, span: span.range, in: text, context: context
            ))
        })
    }

    private func outcome(
        of step: FormStep, entry: Entry, kanji: Bool, span: Range<String.Index>, in text: String, context: SentenceContext
    ) -> FormTransform.Outcome {
        if case .fixed(let marker) = context.position { return .disabled(.fixedBy(marker: marker)) }
        guard let kana = entry.forms[step.to], !kana.isEmpty else { return .disabled(.notInData) }
        let surface: String
        if kanji {
            guard let spelled = entry.spelling?.spell(kana) else { return .disabled(.notInData) }
            surface = spelled
        } else {
            surface = kana
        }
        func rewrite(_ range: Range<String.Index>, _ replacement: String, note: TransformNote? = nil) -> FormTransform.Outcome {
            var sentence = text
            sentence.replaceSubrange(range, with: replacement)
            return .rewrite(SentenceRewrite(
                surface: surface, replacement: replacement, range: range, sentence: sentence, note: note
            ))
        }
        guard step.facet == .register else { return rewrite(span, surface) }
        guard case .final(let ending) = context.position else { return .disabled(.midSentence) }
        let toPolite = catalogue.spec(for: step.to)?.register == .polite
        switch ending {
        case .statement:
            return rewrite(span, surface)
        case .explanatory:
            return .disabled(.explanatory)
        case .questionMark:
            // 行く？ → 行きますか？
            return rewrite(span, toPolite ? surface + "か" : surface)
        case .question(let question):
            if toPolite { return rewrite(span, surface) }
            // A casual んだ can't take the question か, and the plain explanatory question
            // is …の？: more than one step.
            if catalogue.spec(for: step.to)?.register == .casual { return .disabled(.explanatory) }
            // 行きますか。 → 行く？ Never 行くか.
            let mark = text[question].last.flatMap { SentenceContext.questionMarks.contains($0) ? String($0) : nil } ?? "？"
            return rewrite(span.lowerBound..<question.upperBound, surface + mark, note: .plainQuestion)
        }
    }

    // MARK: Steps

    /// Every finite form's one-facet neighbours. Forms pair within a family and name; a
    /// facet that differs must be set on both sides, and the other two must be equal (set
    /// or not). The first neighbour in catalogue order wins.
    static func steps(in catalogue: FormCatalogue) -> [FormID: [FormStep]] {
        let finite = catalogue.forms.filter { $0.role == .finite && $0.appliesTo.contains(.verb) }
        func value(_ spec: FormSpec, _ facet: FormFacet) -> String? {
            switch facet {
            case .register: spec.register?.rawValue
            case .polarity: spec.polarity?.rawValue
            case .tense: spec.tense?.rawValue
            }
        }
        var steps: [FormID: [FormStep]] = [:]
        for spec in finite {
            for facet in FormFacet.allCases {
                guard let own = value(spec, facet) else { continue }
                let others = FormFacet.allCases.filter { $0 != facet }
                let neighbour = finite.first { other in
                    other.family == spec.family && other.name == spec.name
                        && value(other, facet).map { $0 != own } == true
                        && others.allSatisfy { value(other, $0) == value(spec, $0) }
                }
                if let neighbour {
                    steps[spec.id, default: []].append(FormStep(facet: facet, from: spec.id, to: neighbour.id))
                }
            }
        }
        return steps
    }
}
