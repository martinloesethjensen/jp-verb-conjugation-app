import SwiftUI

extension View {
    /// Colours a switch's "on" track with the theme's `accent`, as the spec reserves `accent` for
    /// switches. Use on every `Toggle` shown as a switch: the root tint is `button`, which is a light
    /// colour in dark halves and would hide the white knob. (Menu toggles draw a checkmark; skip them.)
    func paperSwitch() -> some View {
        modifier(PaperSwitch())
    }
}

private struct PaperSwitch: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.tint(palette.accent)
    }
}
