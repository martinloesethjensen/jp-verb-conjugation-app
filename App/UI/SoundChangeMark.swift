import SwiftUI

extension View {
    /// A counter reading whose sound changes: bold with an ink underline (spec "Coherency
    /// pass", rule 2). Not colour alone: the weight and the line carry it, and VoiceOver labels say
    /// "sound changes". No-op when `changed` is false.
    func soundChangeMark(_ changed: Bool) -> some View {
        modifier(SoundChangeMark(changed: changed))
    }
}

private struct SoundChangeMark: ViewModifier {
    let changed: Bool
    @Environment(\.palette) private var palette

    /// A text underline, so it scales with Dynamic Type and stays inside the text's own frame
    /// (a drawn line under the frame touched the alternate readings below it).
    func body(content: Content) -> some View {
        content
            .fontWeight(changed ? .bold : nil)
            .underline(changed, color: palette.ink)
    }
}
