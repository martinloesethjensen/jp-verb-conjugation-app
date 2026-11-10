import SwiftUI

/// An empty screen on paper (canvas board "Proposed: empty states"): a faint kanji, a title, one
/// line, and up to two paper buttons, on a ruled card. Use instead of `ContentUnavailableView`.
struct PaperEmptyState<Actions: View>: View {
    private let title: String
    private let message: String
    private let glyph: String
    private let actions: Actions
    @Environment(\.palette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ title: String, message: String, glyph: String = "空", @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.glyph = glyph
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            JapaneseText(glyph)
                .font(.headword(.largeTitle, scale: 1.6))
                .foregroundStyle(palette.rule)
                .accessibilityHidden(true)
            // A search query or a name may be Japanese: furigana when it is on.
            JapaneseText(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.ink)
            if !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
            layout { actions }
                .buttonStyle(.paperSecondaryInline)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 22)
        .paperCard(cornerRadius: 16, ruled: true)
        .padding()
        .frame(maxWidth: 520)
        .accessibilityElement(children: .contain)
    }
}

extension PaperEmptyState where Actions == EmptyView {
    init(_ title: String, message: String = "", glyph: String = "空") {
        self.init(title, message: message, glyph: glyph) { EmptyView() }
    }
}
