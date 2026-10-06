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
    func slotForm(_ id: FormID) -> String?
}

extension Word: SlotSource {
    public func slotForm(_ id: FormID) -> String? { forms[id] }
}

extension Verb: SlotSource {
    public var wordClass: WordClass { .verb }

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
