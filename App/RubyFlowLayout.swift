import SwiftUI

/// One kanji-with-reading unit: the reading sits above the base, centred.
///
/// SwiftUI can't tell us a font's point size, so the reading is rendered in
/// the inherited font and scaled to half. The scale is a render transform,
/// which doesn't change layout, so this layout reserves half the reading's
/// height above the base and centres the (unscaled) reading subview on the
/// spot where the scaled one should appear. The unit is as wide as the wider
/// of its base and its scaled reading, so neighbours never collide.
struct RubyPairLayout: Layout {
    static let scale: CGFloat = 0.5

    /// Subviews: [reading, base].
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let reading = subviews[0].sizeThatFits(.unspecified)
        let base = subviews[1].sizeThatFits(.unspecified)
        return CGSize(
            width: max(base.width, reading.width * Self.scale),
            height: base.height + reading.height * Self.scale
        )
    }

    /// The pair sits on its base text's baseline, so rows that align on text
    /// baselines (kana beside kanji) line up the same as they do with `Text`.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        let base = subviews[1]
        return bounds.maxY - base.sizeThatFits(.unspecified).height + base.dimensions(in: .unspecified)[guide]
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let reading = subviews[0].sizeThatFits(.unspecified)
        let base = subviews[1].sizeThatFits(.unspecified)
        subviews[1].place(
            at: CGPoint(x: bounds.midX - base.width / 2, y: bounds.maxY - base.height),
            anchor: .topLeading,
            proposal: ProposedViewSize(base)
        )
        subviews[0].place(
            at: CGPoint(x: bounds.midX, y: bounds.minY + reading.height * Self.scale / 2),
            anchor: .center,
            proposal: ProposedViewSize(reading)
        )
    }
}

/// Flows units left to right and wraps them into lines.
///
/// - Units flagged as glued to the previous one (closing punctuation) are
///   never separated from it, so a line never starts with 。 or 、.
/// - Every line is as tall as the tallest unit in the whole string, and units
///   sit on the line's bottom edge, so lines don't jitter and every base
///   shares a baseline.
/// - `maxLines` clips the text after that many lines (no ellipsis).
struct RubyFlowLayout: Layout {
    var glue: [Bool]
    var alignment: TextAlignment
    var maxLines: Int?

    private struct Arrangement {
        var lines: [[Int]]      // subview indices per line
        var lineWidths: [CGFloat]
        var lineHeight: CGFloat
        var sizes: [CGSize]
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> Arrangement {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let lineHeight = sizes.map(\.height).max() ?? 0

        // Group each unit with the glued units after it; a group never splits.
        var groups: [[Int]] = []
        for index in subviews.indices {
            if index > 0, index < glue.count, glue[index], !groups.isEmpty {
                groups[groups.count - 1].append(index)
            } else {
                groups.append([index])
            }
        }

        var lines: [[Int]] = []
        var widths: [CGFloat] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        for group in groups {
            let groupWidth = group.reduce(0) { $0 + sizes[$1].width }
            if !current.isEmpty, currentWidth + groupWidth > maxWidth {
                lines.append(current)
                widths.append(currentWidth)
                current = []
                currentWidth = 0
            }
            current.append(contentsOf: group)
            currentWidth += groupWidth
        }
        if !current.isEmpty {
            lines.append(current)
            widths.append(currentWidth)
        }
        return Arrangement(lines: lines, lineWidths: widths, lineHeight: lineHeight, sizes: sizes)
    }

    private func visibleLineCount(_ arrangement: Arrangement) -> Int {
        min(arrangement.lines.count, maxLines ?? .max)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let arrangement = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let visible = visibleLineCount(arrangement)
        let width = arrangement.lineWidths.prefix(visible).max() ?? 0
        return CGSize(width: width, height: CGFloat(visible) * arrangement.lineHeight)
    }

    /// The first (or last) visible line's text baseline, taken from the first
    /// unit on that line, so this lines up with neighbouring `Text` in a row.
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline, !subviews.isEmpty else { return nil }
        let arrangement = arrange(subviews, maxWidth: bounds.width)
        let visible = visibleLineCount(arrangement)
        guard visible > 0 else { return nil }
        let lineIndex = guide == .firstTextBaseline ? 0 : visible - 1
        guard let index = arrangement.lines[lineIndex].first else { return nil }
        let lineBottom = bounds.minY + CGFloat(lineIndex + 1) * arrangement.lineHeight
        return lineBottom - arrangement.sizes[index].height + subviews[index].dimensions(in: .unspecified)[guide]
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews, maxWidth: bounds.width)
        let visible = visibleLineCount(arrangement)

        for (lineIndex, line) in arrangement.lines.enumerated() {
            if lineIndex >= visible {
                // Past the line limit: park off-screen (the caller clips).
                for index in line {
                    subviews[index].place(at: CGPoint(x: bounds.minX, y: bounds.minY - 10_000), proposal: .zero)
                }
                continue
            }
            let lineWidth = arrangement.lineWidths[lineIndex]
            var x: CGFloat
            switch alignment {
            case .leading: x = bounds.minX
            case .center: x = bounds.minX + (bounds.width - lineWidth) / 2
            case .trailing: x = bounds.maxX - lineWidth
            }
            let lineBottom = bounds.minY + CGFloat(lineIndex + 1) * arrangement.lineHeight
            for index in line {
                let size = arrangement.sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: lineBottom - size.height),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width
            }
        }
    }
}
