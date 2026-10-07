import SwiftUI
import VerbKit

extension CustomTagColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }

    var title: String { rawValue.capitalized }
}

/// A small capsule for a tag. Dialect tags use the accent colour and a map-pin glyph,
/// custom tags their own colour and a number sign, so the two kinds read differently
/// without relying on colour alone.
struct TagPill: View {
    let text: String
    let color: Color
    var systemImage: String?

    init(_ text: String, color: Color, systemImage: String? = nil) {
        self.text = text
        self.color = color
        self.systemImage = systemImage
    }

    init(_ tag: DialectTagValue) {
        self.init(tag.name, color: .accentColor, systemImage: "mappin.and.ellipse")
    }

    init(_ tag: CustomTagValue) {
        self.init(tag.name, color: tag.color.color, systemImage: "number")
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2).accessibilityHidden(true)
            }
            Text(text).font(.caption.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color == .yellow ? Color.primary : color)
        .background(color.opacity(0.15), in: Capsule())
    }
}

/// Lays pills out left to right, wrapping to a new line when the row is full.
struct PillFlow: Layout {
    var spacing: CGFloat = 6

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // The slack absorbs rounding: placement gets back exactly the width measured
            // here, and re-adding the pill widths can exceed it by a hair, which would wrap
            // a pill onto a line the row never made room for.
            if x > 0, x + size.width > width + 0.5 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (frames, CGSize(width: maxX, height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }
}
