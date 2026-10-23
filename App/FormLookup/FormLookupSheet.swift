import SwiftUI
import VerbKit

/// A request to open "What form is this?", optionally with the text to look up.
struct FormLookupRequest: Identifiable {
    let id = UUID()
    var text: String = ""
}

/// "What form is this?" (#110): type or paste a conjugated verb, see which verb it is,
/// which form, and how it is built. Opened from the Verbs search, the "Look up form" text
/// action and the Verbs menu. A link out dismisses the sheet before it navigates.
struct FormLookupSheet: View {
    @Environment(FormLookupStore.self) private var store: FormLookupStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openRoute) private var openRoute
    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(request: FormLookupRequest) {
        _text = State(initialValue: request.text)
    }

    private var items: [FormLookup.Item] { store?.items(in: text) ?? [] }
    private var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Type or paste a verb (食べさせられなかった)", text: $text, axis: .vertical)
                        .font(.title3)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .focused($fieldFocused)
                        .formCard()
                        .accessibilityLabel("Verb to look up")
                    results
                }
                .padding()
            }
            .navigationTitle("What form is this?")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { if isBlank { fieldFocused = true } }
        }
        .environment(\.openRoute, OpenRouteAction { route in
            dismiss()
            openRoute(route)
        })
    }

    @ViewBuilder
    private var results: some View {
        if isBlank {
            Text("Paste a word from your reading, in kanji or kana, to see its dictionary form and how the ending is built.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if items.isEmpty {
            ContentUnavailableView {
                Label("No verb found", systemImage: "magnifyingglass")
            } description: {
                Text("The app doesn't recognise a verb in “\(text)”. It knows the verbs in its table and the endings its lessons teach.")
            } actions: {
                if let url = TextLookupURL.jisho(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Link("Look up in Jisho", destination: url)
                }
            }
        } else {
            ForEach(items) { item in
                VerbSpanCard(item: item)
            }
        }
    }
}

/// One line for a verb found in the search text: 食べる · Causative-passive + Plain · past ·
/// negative. Tapping it opens the full result.
struct FormLookupRow: View {
    let item: FormLookup.Item

    private var summary: String {
        switch item.status {
        case .known:
            let reading = item.readings.first
            return [reading?.verb.jishoQuery, reading?.label].compactMap { $0 }.joined(separator: " · ")
        case .ambiguous:
            return item.verbs.map(\.jishoQuery).joined(separator: " or ") + " · \(item.readings.count) readings"
        case .notInApp:
            return "Not in the app yet" + (item.guesses.first.map { " · probably \($0)" } ?? "")
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.status == .notInApp ? "circle.dashed" : "text.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.surface)
                    .font(.headline)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the form and how it's built")
    }
}

extension View {
    /// Presents "What form is this?" for `request`.
    func formLookupSheet(_ request: Binding<FormLookupRequest?>) -> some View {
        sheet(item: request) { FormLookupSheet(request: $0) }
    }
}
