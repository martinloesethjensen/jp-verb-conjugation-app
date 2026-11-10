import SwiftUI
import VerbKit

/// The on-device suggestion as one dashed card: what it would add (reading, standard form, meaning,
/// dialect, kind), then "Use all" and "Dismiss". Loading, nothing, unsure and failed states are a
/// line each; idle, unavailable and dismissed draw nothing.
struct EntrySuggestionCard: View {
    let state: EntrySuggestionModel.State
    /// The suggestion minus what the draft already has (`EntrySuggestion.removing(whatIsIn:…)`).
    let rest: EntrySuggestion?
    let dialectName: String?
    let onUseAll: () -> Void
    let onDismiss: () -> Void
    let onRetry: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        switch state {
        case .idle, .unavailable, .dismissed:
            EmptyView()
        default:
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Suggested on this device", systemImage: "sparkles")
                .font(.footnote)
                .foregroundStyle(palette.muted)
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(palette.muted, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Looking for suggestions…").font(.footnote).foregroundStyle(palette.muted)
            }
        case .nothing:
            note("No suggestions for this one.")
        case .unsure:
            note("The on-device model wasn't sure about this one and had nothing to suggest.")
        case .failed:
            HStack {
                note("Couldn't get suggestions")
                Spacer(minLength: 8)
                Button("Try again", action: onRetry).buttonStyle(.paperSecondaryInline)
            }
        case .ready:
            if let rest, !rest.isEmpty {
                lines(rest)
                if rest.isUnsure {
                    note("The on-device model wasn't sure about these. Check them before adding.")
                }
                HStack(spacing: 10) {
                    Button("Use all", action: onUseAll).buttonStyle(.paperInline)
                    Button("Dismiss", action: onDismiss).buttonStyle(.paperSecondaryInline)
                }
            } else {
                note("Nothing new to suggest: the entry already has it.")
            }
        case .idle, .unavailable, .dismissed:
            EmptyView()
        }
    }

    @ViewBuilder
    private func lines(_ rest: EntrySuggestion) -> some View {
        if let reading = rest.reading {
            Text("Reading: \(reading)").font(.subheadline).foregroundStyle(palette.ink)
        }
        if !rest.standardForms.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Standard:").font(.subheadline).foregroundStyle(palette.muted)
                JapaneseText(rest.standardForms.map(\.written).joined(separator: "・"))
                    .font(.headword(.body))
                    .foregroundStyle(palette.ink)
            }
            .accessibilityElement(children: .combine)
        }
        let parts = [
            rest.meanings.isEmpty ? nil : "Meaning: " + rest.meanings.joined(separator: ", "),
            dialectName.map { "Dialect: \($0)" },
            rest.kind.map { "Kind: \($0.rawValue.capitalized)" },
        ].compactMap { $0 }
        if !parts.isEmpty {
            // Dialect names are kanji (北海道弁).
            JapaneseText(parts.joined(separator: " · ")).font(.subheadline).foregroundStyle(palette.ink)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(palette.muted)
    }
}
