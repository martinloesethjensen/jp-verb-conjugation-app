import SwiftUI

/// The content button of the paper-and-ink look: a full-width capsule, filled with ink for the
/// primary action or outlined on `card` for a secondary one. Use it for buttons inside content
/// (Test this verb, lesson links, results actions) instead of glass, which stays on chrome.
struct PaperButtonStyle: ButtonStyle {
    enum Prominence { case primary, secondary }

    var prominence: Prominence

    init(_ prominence: Prominence = .primary) {
        self.prominence = prominence
    }

    func makeBody(configuration: Configuration) -> some View {
        PaperButtonBody(configuration: configuration, prominence: prominence)
    }
}

private struct PaperButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: PaperButtonStyle.Prominence
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominence == .primary ? palette.onButton : palette.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(prominence == .primary ? palette.button : palette.card, in: Capsule())
            .overlay {
                if prominence == .secondary {
                    Capsule().strokeBorder(palette.rule, lineWidth: contrast == .increased ? 1.5 : 1)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == PaperButtonStyle {
    /// The ink-filled primary capsule.
    static var paper: Self { PaperButtonStyle(.primary) }
    /// The outlined secondary capsule on `card`.
    static var paperSecondary: Self { PaperButtonStyle(.secondary) }
}
