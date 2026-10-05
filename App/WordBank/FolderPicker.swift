import SwiftUI
import VerbKit

/// A tree of folders to move something into. `disabled` greys out folders that can't take
/// the item (a folder itself and its descendants). Picking "Top level" files an entry as
/// Unfiled, or makes a folder top-level.
struct FolderPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    var title: String = "Move to…"
    var current: UUID?
    var disabled: Set<UUID> = []
    let onPick: (UUID?) -> Void

    private struct Row: Identifiable {
        let folder: WordBankFolderValue
        let depth: Int
        var id: UUID { folder.id }
    }

    private var rows: [Row] {
        let tree = store.tree
        func walk(_ parent: UUID?, _ depth: Int) -> [Row] {
            tree.children(of: parent).flatMap { [Row(folder: $0, depth: depth)] + walk($0.id, depth + 1) }
        }
        return walk(nil, 0)
    }

    var body: some View {
        NavigationStack {
            List {
                pick(nil, name: "Top level", subtitle: "Unfiled", systemImage: "tray", depth: 0, enabled: true)
                ForEach(rows) { row in
                    pick(row.folder.id, name: row.folder.name, subtitle: nil, systemImage: "folder", depth: row.depth,
                         enabled: !disabled.contains(row.folder.id))
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pick(_ id: UUID?, name: String, subtitle: String?, systemImage: String, depth: Int, enabled: Bool) -> some View {
        Button {
            onPick(id)
            dismiss()
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(name)
                        if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                } icon: {
                    Image(systemName: systemImage)
                }
                Spacer()
                if current == id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
            .padding(.leading, CGFloat(depth) * 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.primary : Color.secondary)
    }
}
