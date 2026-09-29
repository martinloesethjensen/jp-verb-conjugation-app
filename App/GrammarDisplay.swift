import VerbKit

// Presentation strings for grammar enums. They live in the app target,
// not VerbKit, because wording is a UI concern.

extension WordClass {
    var displayName: String {
        switch self {
        case .verb: return "Verb"
        case .iAdjective: return "い-adjective"
        case .naAdjective: return "な-adjective"
        case .noun: return "Noun"
        }
    }
}

extension GrammarLevel {
    var displayName: String {
        switch self {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        }
    }
}

extension GrammarRegister {
    var displayName: String {
        switch self {
        case .polite: return "Polite"
        case .casual: return "Casual"
        case .formal: return "Formal / written"
        }
    }
}
