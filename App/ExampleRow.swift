import SwiftUI
import VerbKit

/// A Japanese example whose English translation is hidden until tapped,
/// so a grammar page doubles as self-testing.
struct ExampleRow: View {
    let example: GrammarExample
    @State private var revealed = false

    var body: some View {
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
    }
}
