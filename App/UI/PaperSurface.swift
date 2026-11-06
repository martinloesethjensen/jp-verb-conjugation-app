import SwiftUI

extension View {
    /// The card surface for grouped detail content: 12 pt padding on the theme's `card`, outlined
    /// by a hairline in `rule` (1.5 pt with Increase Contrast). Turn `fillsWidth` off for a box
    /// that hugs its content. Replaces the old glass card: glass stays on bars and toolbars.
    func paperCard(cornerRadius: CGFloat = 12, fillsWidth: Bool = true) -> some View {
        modifier(PaperCard(cornerRadius: cornerRadius, fillsWidth: fillsWidth))
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
    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(palette.rule, lineWidth: contrast == .increased ? 1.5 : 1)
            }
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
