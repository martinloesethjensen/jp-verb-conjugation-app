import SwiftUI

extension View {
    /// A counter reading whose sound changes: semibold with a 2 pt ink underline (spec "Coherency
    /// pass", rule 2). Not colour alone: the weight and the line carry it, and VoiceOver labels say
    /// "sound changes". No-op when `changed` is false.
    func soundChangeMark(_ changed: Bool) -> some View {
        modifier(SoundChangeMark(changed: changed))
    }
}

private struct SoundChangeMark: ViewModifier {
    let changed: Bool
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        if changed {
            content
                .fontWeight(.bold)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(palette.ink)
                        .frame(height: 2)
                        .offset(y: 3)
                        .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}
