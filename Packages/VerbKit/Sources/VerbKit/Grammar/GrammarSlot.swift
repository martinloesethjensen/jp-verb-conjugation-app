import Foundation

/// A building block a grammar pattern attaches to: one of the plain forms, the stem or
/// the て-form. A grammar rule names its slots, so the app can build the pattern for any
/// word (しずか + ので → しずかなので) and say which block a lesson takes.
public enum GrammarSlot: String, Codable, CaseIterable, Sendable {
    case plain, plainNeg, plainPast, plainPastNeg, stem, te

    /// The form that holds this slot, for every word class that has it.
    public var formID: FormID {
        switch self {
        case .plain: "short_pos"
        case .plainNeg: "short_neg"
        case .plainPast: "short_past"
        case .plainPastNeg: "short_past_neg"
        case .stem: "stem"
        case .te: "te"
        }
    }
}

/// Anything with a word class and forms by id: a curated verb or a word from words.json.
public protocol SlotSource {
    var wordClass: WordClass { get }
    var dict: String { get }
    /// The kanji spelling, if it has one. It tells apart words spelled the same in kana.
    var kanji: String? { get }
    /// What identifies the word within its class: the explicit id when there is one (`きる:切る`),
    /// otherwise the citation form. Quiz history and pickers use it, never `dict`, so two words
    /// spelled the same stay apart.
    var stableKey: String { get }
    func slotForm(_ id: FormID) -> String?
}

extension Word: SlotSource {
    public var stableKey: String { explicitID ?? dict }
    public func slotForm(_ id: FormID) -> String? { forms[id] }
}

extension Verb: SlotSource {
    public var wordClass: WordClass { .verb }
    public var stableKey: String { id }

    public func slotForm(_ id: FormID) -> String? {
        switch id.rawValue {
        case "short_pos": forms.shortPos
        case "short_neg": forms.shortNeg
        case "short_past": forms.shortPast
        case "short_past_neg": forms.shortPastNeg
        case "te": forms.te
        case "stem": forms.stem
        default: nil
        }
    }
}

public extension SlotSource {
    /// The word's form for `slot`, or nil if it has none (a noun has no stem). With
    /// `daToNa`, a な-adjective's or noun's plain form drops だ and takes な (しずかな,
    /// あめな); no other slot or class changes.
    func form(for slot: GrammarSlot, daToNa: Bool = false) -> String? {
        guard let form = slotForm(slot.formID) else { return nil }
        if daToNa, slot == .plain, wordClass == .naAdjective || wordClass == .noun, form.hasSuffix("だ") {
            return String(form.dropLast()) + "な"
        }
        return form
    }
}

public extension AttachmentRule {
    /// The verb forms this rule spells out in `slot`: each form some of `verbs` have, whose
    /// value is the built pattern for every verb that has it (stem + ましょう is the polite
    /// volitional). Empty when no stored form matches (short form + ので).
    func practisedForms(_ slot: GrammarSlot, among verbs: [Verb]) -> [QuizForm] {
        guard wordClass == .verb, slots.contains(slot), then != nil else { return [] }
        let built = verbs.map { (forms: $0.forms, built: build($0, slot: slot)) }
        return QuizForm.all.filter { form in
            var matched = false
            for verb in built {
                guard let value = form.value(in: verb.forms) else { continue }
                guard value == verb.built else { return false }
                matched = true
            }
            return matched
        }
    }

    /// The verbs this rule can be practised with in `slot`: those that have every form it
    /// spells out. The data leaves a form out on purpose (わかる has no ましょう form, since
    /// わかる is not volitional), so a verb without it is not asked for わかりましょう.
    func eligibleVerbs(_ slot: GrammarSlot, among verbs: [Verb]) -> [Verb] {
        let practised = practisedForms(slot, among: verbs)
        return verbs.filter { verb in
            build(verb, slot: slot) != nil && practised.allSatisfy { $0.value(in: verb.forms) != nil }
        }
    }
}
