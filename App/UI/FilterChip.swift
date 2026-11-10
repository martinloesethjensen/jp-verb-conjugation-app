import SwiftUI

/// The shared pill of a filter row: a menu or a single-choice chip. Off, it is outlined in ink on
/// the card colour; on, it fills with the theme's button colour. An `accent` adds a leading dot
/// in that colour (the て groups) rather than a pastel fill.
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
        HStack(spacing: 6) {
            if let accent {
                Circle().fill(accent).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            // Dialect tags and て endings are Japanese: furigana when it is on.
            JapaneseText(title)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
        }
        .font(.callout.weight(isOn ? .semibold : .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .chipBackground(isOn: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension View {
    /// The filter-chip capsule: `button`-filled while on, `card` with a 1 pt `ink` outline while off.
    func chipBackground(isOn: Bool) -> some View {
        modifier(ChipBackground(isOn: isOn))
    }
}

private struct ChipBackground: ViewModifier {
    let isOn: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isOn ? palette.onButton : palette.ink)
            .background(isOn ? palette.button : palette.card, in: Capsule())
            .overlay { if !isOn { Capsule().strokeBorder(palette.ink, lineWidth: 1) } }
    }
}
