import SwiftUI
import VerbKit

/// A Japanese example whose English translation is hidden until tapped,
/// so a grammar page doubles as self-testing.
struct ExampleRow: View {
    let example: GrammarExample
    /// What the speaker says when it should not be the written sentence (a counter example that
    /// overrides a reading, so the voice cannot choose the wrong one). Defaults to the sentence.
    var speech: String?
    @State private var revealed = false

    var body: some View {
        HStack(alignment: .top) {
            Button {
                revealed.toggle()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    JapaneseText(example.jp)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    Text(revealed ? example.en : "Tap to show English")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textActions(example.jp, translate: true)
            SpeakButton(text: speech ?? example.jp)
        }
    }
}
