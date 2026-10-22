import SwiftUI
import VerbKit

/// A sheet that picks grammar points to add to a lesson of My course.
struct GrammarPointPicker: View {
    let points: [GrammarPoint]
    /// Ids already in the lesson; shown ticked and not selectable.
    let existing: Set<String>
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String] = []
    @State private var query = ""

    private var filtered: [GrammarPoint] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return points }
        return points.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.summary.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { point in
                let isExisting = existing.contains(point.id)
                let isSelected = selected.contains(point.id)
                Button {
                    if let i = selected.firstIndex(of: point.id) { selected.remove(at: i) } else { selected.append(point.id) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            JapaneseText(point.title)
                            Text(point.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if isExisting || isSelected {
                            Image(systemName: "checkmark").foregroundStyle(isExisting ? Color.secondary : Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isExisting)
            }
            .searchable(text: $query)
            .navigationTitle("Add grammar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd(selected); dismiss() }.disabled(selected.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 440)
        #endif
    }
}
