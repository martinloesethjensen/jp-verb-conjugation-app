import SwiftUI

extension View {
    /// The card surface for grouped detail content: 12 pt padding on the theme's `card`, outlined
    /// by a hairline in `rule` (1.5 pt with Increase Contrast). Turn `fillsWidth` off for a box
    /// that hugs its content. Turn `ruled` on for genkō paper: a faint square grid under the
    /// content, for example sentences and results. Replaces the old glass card: glass stays on
    /// bars and toolbars.
    func paperCard(cornerRadius: CGFloat = 12, fillsWidth: Bool = true, ruled: Bool = false) -> some View {
        modifier(PaperCard(cornerRadius: cornerRadius, fillsWidth: fillsWidth, ruled: ruled))
    }

    /// The theme's paper behind a screen's `List`, `ScrollView` or `Form`, edge to edge.
    func paperBackground() -> some View {
        modifier(PaperBackground())
    }

    /// Card-coloured rows with `rule` separators, for rows of grouped lists and forms.
    func paperRow() -> some View {
        modifier(PaperRow())
    }
}

private struct PaperCard: ViewModifier {
    let cornerRadius: CGFloat
    let fillsWidth: Bool
    let ruled: Bool
    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .background {
                ZStack {
                    palette.card
                    if ruled { GenkoGrid(color: palette.rule.opacity(0.6)) }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(palette.rule, lineWidth: contrast == .increased ? 1.5 : 1)
            }
    }
}

/// Lines every 28 pt both ways, like the squares of genkō yōshi.
private struct GenkoGrid: View {
    let color: Color
    private let step: CGFloat = 28

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = step
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y = step
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct PaperBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { palette.paper.ignoresSafeArea() }
    }
}

private struct PaperRow: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .listRowBackground(palette.card)
            .listRowSeparatorTint(palette.rule)
    }
}
