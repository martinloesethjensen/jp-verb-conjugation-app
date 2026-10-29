import SwiftUI
import VerbKit

/// The small JLPT pill shown beside a verb, grammar point or counter. A nil level
/// draws nothing, so callers do not need their own `if let`.
struct LevelBadge: View {
    enum Emphasis {
        /// Beside a row's title.
        case row
        /// In a detail page's header.
        case header
    }

    let level: JLPTLevel?
    var emphasis: Emphasis = .row
    /// The hardest level when the item spans several (a lesson whose usages differ); drawn as "N4–N3".
    var upTo: JLPTLevel?

    /// A badge for a level range: one level when the range is a single level.
    init(range: ClosedRange<JLPTLevel>?, emphasis: Emphasis = .row) {
        self.level = range?.lowerBound
        self.upTo = range?.upperBound
        self.emphasis = emphasis
    }

    init(level: JLPTLevel?, emphasis: Emphasis = .row) {
        self.level = level
        self.emphasis = emphasis
    }

    private var label: String {
        guard let level else { return "" }
        guard let upTo, upTo != level else { return level.displayName }
        return "\(level.displayName)–\(upTo.displayName)"
    }

    private var accessibilityText: String {
        guard let level, let upTo, upTo != level else { return "JLPT \(label)" }
        return "JLPT \(level.displayName) to \(upTo.displayName)"
    }

    @ViewBuilder
    var body: some View {
        if level != nil {
            Text(label)
                .font(emphasis == .row ? .caption2.weight(.semibold) : .caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .glassEffect(in: Capsule())
                .accessibilityLabel(accessibilityText)
        }
    }
}
