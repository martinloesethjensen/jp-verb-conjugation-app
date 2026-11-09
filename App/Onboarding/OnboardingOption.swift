import SwiftUI

/// A selectable card for onboarding: `card` fill, a 2 pt ink border when selected (1 pt `rule`
/// otherwise) and the `.isSelected` trait, so selection never rests on colour alone.
struct OnboardingOption<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? palette.ink : palette.rule, lineWidth: isSelected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
