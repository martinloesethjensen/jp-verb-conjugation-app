import SwiftUI

/// A labelled text field for paper editors: the label as a muted caption above a borderless field
/// in ink, with a muted placeholder. Put several in a `PaperFieldSection`, with `PaperDivider`s.
struct PaperField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var font: Font = .body
    var axis: Axis = .horizontal

    @Environment(\.palette) private var palette

    init(_ label: String, placeholder: String, text: Binding<String>, font: Font = .body, axis: Axis = .horizontal) {
        self.label = label
        self.placeholder = placeholder
        _text = text
        self.font = font
        self.axis = axis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(palette.muted)
                .accessibilityHidden(true)
            TextField(label, text: $text, prompt: Text(placeholder).foregroundStyle(palette.muted), axis: axis)
                .font(font)
                .foregroundStyle(palette.ink)
                .accessibilityLabel(label)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A full-width 1 pt `rule` line between rows of a paper card (1.5 pt with Increase Contrast).
struct PaperDivider: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(palette.rule)
            .frame(height: contrast == .increased ? 1.5 : 1)
            .accessibilityHidden(true)
    }
}

/// A group of editor rows: an optional uppercase muted header, then the rows on a card (`card`
/// fill, `rule` outline, 14 pt radius, no inner padding). Callers put `PaperDivider`s between rows.
struct PaperFieldSection<Content: View>: View {
    var title: String?
    @ViewBuilder let content: () -> Content

    @Environment(\.palette) private var palette
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0, content: content)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.rule, lineWidth: contrast == .increased ? 1.5 : 1))
        }
    }
}

#Preview("Paper fields") {
    @Previewable @State var text = "おおきに"
    @Previewable @State var reading = ""
    PaperFieldSection("Standard Japanese") {
        PaperField("Text", placeholder: "おおきに", text: $text, font: .headword(.title2))
        PaperDivider()
        PaperField("Reading", placeholder: "かな", text: $reading)
    }
    .padding()
    .themedRoot()
}
