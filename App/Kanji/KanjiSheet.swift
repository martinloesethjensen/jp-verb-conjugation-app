import SwiftUI
import VerbKit

enum KanjiSheetMode: Hashable {
    case watch, trace
}

/// A request to open the stroke-order sheet for one kanji.
struct KanjiSheetRequest: Identifiable {
    let id = UUID()
    let character: Character
    var mode: KanjiSheetMode = .watch
}

/// One kanji's stroke order: Watch (the strokes drawn in order, with readings and the verbs that
/// use it) and Trace (draw each stroke with a finger). Opened from text menus, the verb page's
/// Kanji section and Word Bank kanji chips. A link out dismisses the sheet before it navigates.
struct KanjiSheet: View {
    let character: Character
    @State private var mode: KanjiSheetMode
    @State private var watchStep = 1

    @Environment(KanjiStore.self) private var store: KanjiStore?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openRoute) private var openRoute
    @Environment(\.palette) private var palette

    init(request: KanjiSheetRequest) {
        character = request.character
        _mode = State(initialValue: request.mode)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let entry = store?.entry(for: character) {
                    switch mode {
                    case .watch:
                        KanjiWatchView(entry: entry, step: $watchStep)
                    case .trace:
                        KanjiTraceView(entry: entry) { stroke in
                            watchStep = stroke
                            mode = .watch
                        }
                    }
                } else {
                    ContentUnavailableView("No stroke order for \(String(character))", systemImage: "paintbrush.pointed")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(palette.paper)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text(String(character))
                        .font(.headword(.title2))
                        .foregroundStyle(palette.ink)
                        .accessibilityHidden(true)
                }
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $mode) {
                        Text("Watch").tag(KanjiSheetMode.watch)
                        Text("Trace").tag(KanjiSheetMode.trace)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .environment(\.openRoute, OpenRouteAction { route in
            dismiss()
            openRoute(route)
        })
    }
}

extension View {
    /// Presents the stroke-order sheet for `request`'s kanji.
    func kanjiSheet(_ request: Binding<KanjiSheetRequest?>) -> some View {
        sheet(item: request) { KanjiSheet(request: $0) }
    }
}
