import SwiftUI

/// The shared pill of a filter row: a menu or a single-choice chip. It is bold and
/// outlined while `isOn`; `accent` fills it with a pastel colour instead of the
/// neutral background.
struct FilterChip: View {
    private let title: String
    private let accent: Color?
    private let isOn: Bool
    private let showsChevron: Bool

    init(_ title: String, accent: Color? = nil, isOn: Bool, showsChevron: Bool = false) {
        self.title = title
        self.accent = accent
        self.isOn = isOn
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
        }
        .font(.callout.weight(isOn ? .bold : .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .chipBackground(accent)
        .overlay { if isOn { Capsule().strokeBorder(Color.primary, lineWidth: 2) } }
    }
}

extension View {
    /// Plain filled capsules: a row of glass capsules draws a shaded band behind them.
    @ViewBuilder func chipBackground(_ accent: Color?) -> some View {
        if let accent {
            foregroundStyle(Color.black.opacity(0.85)).background(accent.opacity(0.85), in: Capsule())
        } else {
            foregroundStyle(.primary).background(Color.primary.opacity(0.1), in: Capsule())
        }
    }
}
