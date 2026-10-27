import SwiftUI

extension View {
    /// The quiet Liquid Glass card for grouped detail content: 12 pt padding and a
    /// rounded glass surface. Turn `fillsWidth` off for a box that hugs its content.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 10, fillsWidth: Bool = true) -> some View {
        if fillsWidth {
            padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            padding(12)
                .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
