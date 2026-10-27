import Foundation

/// The mistake a learner keeps making, read from the tags on recent wrong answers.
/// Pure: no I/O. Shown on Progress only when `dominant(in:)` returns a value.
///
/// Rules:
/// - Only wrong answers (not timeouts) with a tag count. Untagged attempts (history from before
///   tags) and `generic` are ignored before the window is taken, so they never fill it.
/// - The window is the most recent `windowSize` such attempts, ordered by date; equal dates keep
///   input order, the later one counting as newer.
/// - Tags group by category, so `wrong_te_group:tte` and `wrong_te_group:nde` are one mistake
///   (the wrong て-form ending), as are all `other_form:*` and all `other_verb:*`.
/// - The category with the most attempts in the window is dominant when it has at least
///   `minimumCount`. A tie goes to the category whose mistake is more recent.
public struct QuizConfusion: Equatable, Sendable {
    public static let windowSize = 20
    public static let minimumCount = 3

    public enum Category: String, CaseIterable, Sendable {
        case ruUConfusion, wrongTeGroup, aruNegative, passivePotential
        case causativePassiveLongShort, otherForm, otherVerb

        init?(_ tag: QuizErrorTag) {
            switch tag {
            case .ruUConfusion: self = .ruUConfusion
            case .wrongTeGroup: self = .wrongTeGroup
            case .aruNegative: self = .aruNegative
            case .passivePotential: self = .passivePotential
            case .causativePassiveLongShort: self = .causativePassiveLongShort
            case .otherForm: self = .otherForm
            case .otherVerb: self = .otherVerb
            case .generic: return nil
            }
        }

        /// The line shown to the learner.
        public var headline: String {
            switch self {
            case .ruUConfusion: "You often confuse ru- and u-verbs"
            case .wrongTeGroup: "You often mix up the て-form endings"
            case .aruNegative: "You often write あらない for the negative of ある"
            case .passivePotential: "You often mix up the passive and the potential"
            case .causativePassiveLongShort: "You often mix up the long and short causative-passive"
            case .otherForm: "You often pick a different form from the one asked"
            case .otherVerb: "You often pick another verb's conjugation"
            }
        }

        /// One kind sentence on what to try.
        public var advice: String {
            switch self {
            case .ruUConfusion: "Look at the verb's type first: ru-verbs drop る, u-verbs change it."
            case .wrongTeGroup: "Each verb group has its own て-form ending, so check the group first."
            case .aruNegative: "The plain negative of ある is ない."
            case .passivePotential: "They can look alike, so read the question's form label twice."
            case .causativePassiveLongShort: "Both are real forms, so check which one is asked."
            case .otherForm: "Take a moment to read which form the question asks for."
            case .otherVerb: "Check that the answer belongs to the verb in the question."
            }
        }

        /// Same rule as the quiz explanation: the verb guide covers these two mistakes.
        public var opensVerbGuide: Bool { self == .ruUConfusion || self == .wrongTeGroup }
    }

    public let category: Category
    /// Wrong answers with this category in the window.
    public let count: Int
    /// Tagged wrong answers in the window (at most `windowSize`).
    public let windowSize: Int

    public static func dominant(in attempts: [QuizAttempt]) -> QuizConfusion? {
        let recent = attempts.enumerated()
            .compactMap { index, attempt -> (category: Category, date: Date, index: Int)? in
                guard attempt.outcome == .wrong, let tag = attempt.errorTag, let category = Category(tag) else { return nil }
                return (category, attempt.date, index)
            }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.index > $1.index }
            .prefix(Self.windowSize)

        var counts: [Category: Int] = [:]
        var newestRank: [Category: Int] = [:]
        for (rank, entry) in recent.enumerated() {
            counts[entry.category, default: 0] += 1
            if newestRank[entry.category] == nil { newestRank[entry.category] = rank }
        }
        // Most attempts first; on a tie the lower newest-rank (more recent mistake) wins.
        guard let top = counts.max(by: { a, b in
            a.value != b.value ? a.value < b.value : newestRank[a.key]! > newestRank[b.key]!
        }), top.value >= Self.minimumCount else { return nil }
        return QuizConfusion(category: top.key, count: top.value, windowSize: recent.count)
    }
}
