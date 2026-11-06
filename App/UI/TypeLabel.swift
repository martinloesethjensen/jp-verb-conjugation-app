import SwiftUI
import VerbKit

extension VerbType {
    /// The singular type name on a verb's label: "Irregular", "Ru-verb", "U-verb".
    var typeLabel: String {
        switch self {
        case .irregular: "Irregular"
        case .ru: "Ru-verb"
        case .u: "U-verb"
        }
    }

    /// The shape that stands in for the type colour with Differentiate Without Color on.
    var shapeSymbol: String {
        switch self {
        case .irregular: "diamond.fill"
        case .ru: "circle.fill"
        case .u: "triangle.fill"
        }
    }
}

/// A verb's type as an ink label with a small dot in the type colour, and optionally its て group
/// (a second dot and the て ending). Pastel themes fill the pill with the type colour instead.
/// With Differentiate Without Color on, dots become shapes and the て ending gets a box, so the
/// colour is never the only cue.
struct TypeLabel: View {
    let type: VerbType
    var teGroup: TeGroup?
    var emphasis: LevelBadge.Emphasis = .row
    /// Overrides the type name, for the guide's longer headings.
    var title: String?

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityDifferentiateWithoutColor) private var withoutColor
    @ScaledMetric(relativeTo: .caption) private var dotSize: CGFloat = 8

    init(_ type: VerbType, teGroup: TeGroup? = nil, emphasis: LevelBadge.Emphasis = .row, title: String? = nil) {
        self.type = type
        self.teGroup = teGroup
        self.emphasis = emphasis
        self.title = title
    }

    private var font: Font {
        emphasis == .row ? .caption.weight(.semibold) : .footnote.weight(.semibold)
    }

    private var teEnding: String? {
        guard let teGroup else { return nil }
        return TeFormRule.all.first { $0.group == teGroup }?.result
    }

    var body: some View {
        HStack(spacing: 6) {
            if palette.fillsTypePills {
                Text(title ?? type.typeLabel)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .accentPill(type.accentColor)
            } else {
                marker(color: type.accentColor, symbol: type.shapeSymbol)
                Text(title ?? type.typeLabel).foregroundStyle(palette.ink)
            }
            if let teGroup, let teEnding {
                Text("·").foregroundStyle(palette.muted).accessibilityHidden(true)
                if withoutColor {
                    Text(teEnding)
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(palette.ink, lineWidth: 1))
                } else {
                    marker(color: teGroup.accentColor, symbol: nil)
                    Text(teEnding).foregroundStyle(palette.muted)
                }
            }
        }
        .font(font)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func marker(color: Color, symbol: String?) -> some View {
        if withoutColor, let symbol {
            Image(systemName: symbol)
                .font(.system(size: dotSize + 2))
                .foregroundStyle(color)
                .overlay(Image(systemName: symbol.replacingOccurrences(of: ".fill", with: "")).font(.system(size: dotSize + 2)).foregroundStyle(palette.ink))
                .accessibilityHidden(true)
        } else {
            Circle().fill(color).frame(width: dotSize, height: dotSize).accessibilityHidden(true)
        }
    }
}
