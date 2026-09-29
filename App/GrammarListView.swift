import SwiftUI
import VerbKit

struct GrammarRow: View {
    let point: GrammarPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(point.title)
                    .font(.title3.weight(.bold))
                Text(point.level.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .glassEffect(in: Capsule())
            }
            Text(point.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct GrammarListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var selection: GrammarPoint?
    @State private var search = ""

    private var filtered: [GrammarPoint] {
        verbStore.grammarPoints.filter { matchesGrammarSearch($0, query: search) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { point in
                // Same row pattern as VerbListView: an explicit Button
                // sets the selection, and .tag keeps List's own selection
                // in sync (List(selection:) alone matches the row's id,
                // not the element, so taps would silently do nothing).
                Button {
                    selection = point
                } label: {
                    GrammarRow(point: point)
                }
                .buttonStyle(.plain)
                .tag(point)
            }
        }
        .searchable(text: $search, prompt: "Search grammar…")
        .navigationTitle("Grammar")
        .overlay {
            if !verbStore.hasGrammar {
                ContentUnavailableView {
                    Label("Grammar Not Downloaded Yet", systemImage: "icloud.and.arrow.down")
                } description: {
                    Text("Grammar lessons download in the background. Check your connection and try again.")
                } actions: {
                    Button("Try Again") {
                        Task { await verbStore.retryGrammarSync() }
                    }
                    .buttonStyle(.glassProminent)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}
