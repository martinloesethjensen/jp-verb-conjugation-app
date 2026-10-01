import SwiftUI

extension View {
    /// Speaks `text` when the view is tapped. Long-press menus are unaffected.
    func speakOnTap(_ text: String) -> some View {
        onTapGesture { Speaker.shared.speak(text) }
    }
}

/// A small speaker icon that speaks `text`.
struct SpeakButton: View {
    let text: String

    var body: some View {
        Button("Speak", systemImage: "speaker.wave.2") {
            Speaker.shared.speak(text)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }
}
