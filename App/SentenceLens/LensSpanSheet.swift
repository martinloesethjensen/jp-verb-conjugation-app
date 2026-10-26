import SwiftUI
import VerbKit

/// The Sentence lens tap sheet: the verb's card from "What form is this?" (#110), then the
/// one-step transform chips (#146) and a preview of the sentence with Play and Copy. Links
/// close this sheet and the lens before they navigate.
struct LensSpanSheet: View {
    @Bindable var lens: SentenceLensModel
    let item: FormLookup.Item
    /// Stops the live mic, so it doesn't hear the app speak, then speaks the text.
    let onPlay: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openRoute) private var openRoute

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VerbSpanCard(item: item, selection: $lens.chosenReadingID)
                    if item.status != .notInApp {
                        TransformChips(lens: lens)
                    }
                    LensPreviewCard(lens: lens, onPlay: onPlay)
                }
                .padding()
            }
            .navigationTitle(item.surface)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(\.openRoute, OpenRouteAction { route in
            dismiss()
            openRoute(route)
        })
    }
}

/// The Register, Polarity and Tense rows. A chip shows the new form; a disabled one says
/// why in words, never by greying alone.
private struct TransformChips: View {
    let lens: SentenceLensModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change it")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            switch lens.transforms {
            case .unavailable(let reason):
                Label(reason.message, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .available(let transforms):
                ForEach(transforms, id: \.step) { transform in
                    row(transform)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .formCard()
    }

    private func row(_ transform: FormTransform) -> some View {
        let applied = lens.applied == transform
        let target = lens.label(for: transform.step.to)
        return VStack(alignment: .leading, spacing: 4) {
            Text(transform.step.facet.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if let rewrite = transform.rewrite {
                Button {
                    if applied { lens.resetPreview() } else { lens.apply(transform) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: applied ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rewrite.surface)
                                .font(.headline)
                            Text(target)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("\(transform.step.facet.title): \(rewrite.surface), \(target)")
                .accessibilityHint(applied ? "Shows the original sentence" : "Shows the sentence with this form")
                .accessibilityAddTraits(applied ? .isSelected : [])
            } else if let reason = transform.disabledReason {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "nosign")
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target)
                            .font(.subheadline.weight(.semibold))
                        Text(reason.message)
                            .font(.caption)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(transform.step.facet.title): \(target), unavailable. \(reason.message)")
            }
        }
    }
}

/// The sentence as it is, or with the applied transform's verb swapped in and marked,
/// with Play, Copy and Original.
private struct LensPreviewCard: View {
    let lens: SentenceLensModel
    let onPlay: (String) -> Void
    @State private var copied = false

    private var attributed: AttributedString {
        guard let preview = lens.preview else { return AttributedString(lens.sentence) }
        var replacement = AttributedString(preview.replacement)
        replacement.font = .title3.weight(.bold)
        replacement.underlineStyle = .single
        replacement.backgroundColor = .yellow.opacity(0.35)
        return AttributedString(preview.before) + replacement + AttributedString(preview.after)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lens.preview == nil ? "Sentence" : "Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Text(attributed)
                .font(.title3)
                .textSelection(.enabled)
                .accessibilityLabel(lens.outputText)
            if let note = lens.preview?.note {
                Label(note.message, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Play", systemImage: "speaker.wave.2") {
                    onPlay(lens.outputText)
                }
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    Clipboard.copy(lens.outputText)
                    copied = true
                }
                if lens.preview != nil {
                    Button("Original", systemImage: "arrow.uturn.backward") {
                        lens.resetPreview()
                    }
                }
            }
            .buttonStyle(.glass)
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .formCard()
        .onChange(of: lens.outputText) { copied = false }
    }
}

extension FormFacet {
    var title: String {
        switch self {
        case .register: "Politeness"
        case .polarity: "Positive / negative"
        case .tense: "Tense"
        }
    }
}
