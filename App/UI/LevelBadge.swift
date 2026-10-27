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

    @ViewBuilder
    var body: some View {
        if let level {
            Text(level.displayName)
                .font(emphasis == .row ? .caption2.weight(.semibold) : .caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .glassEffect(in: Capsule())
        }
    }
}
