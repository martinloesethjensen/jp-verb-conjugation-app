import SwiftUI
import VerbKit

/// The automatic backups (one is made before every import and restore). Restoring replaces
/// the Word Bank with the backup, after a backup of the current one.
struct WordBankBackupsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankTransferHub.self) private var hub

    private struct Row: Identifiable {
        let backup: WordBankBackup
        let entryCount: Int?
        var id: String { backup.id }
    }

    @State private var rows: [Row] = []
    @State private var confirming: WordBankBackup?
    @State private var error: String?
    @State private var restored = false

    var body: some View {
        List {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No backups yet", systemImage: "clock.arrow.circlepath",
                    description: Text("One is made before every import.")
                )
            } else {
                Section {
                    ForEach(rows) { row in
                        Button { confirming = row.backup } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    if let count = row.entryCount {
                                        Text(count == 1 ? "1 entry" : "\(count) entries").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "arrow.uturn.backward").foregroundStyle(.tint).accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("The last three are kept. Restoring one replaces your Word Bank with it, after making a backup of the current one.")
                }
            }
        }
        .navigationTitle("Restore Backup")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { reload() }
        .confirmationDialog(
            "Replace your Word Bank with this backup?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let backup = confirming {
                Button("Restore", role: .destructive) { restore(backup) }
            }
        } message: {
            Text("A backup of your current Word Bank is made first.")
        }
        .alert("Restored", isPresented: $restored) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your Word Bank is back to that backup. The one you had before was saved as a backup too.")
        }
        .alert("Couldn't restore", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func reload() {
        rows = hub.backups.backups().map { Row(backup: $0, entryCount: (try? hub.backups.archive(of: $0))?.entries.count) }
    }

    private func restore(_ backup: WordBankBackup) {
        do {
            try hub.transfer.restore(backup)
            restored = true
            reload()
        } catch WordBankTransferError.backupFailed {
            error = "Couldn't make a backup of the current Word Bank first, so nothing was restored."
        } catch {
            self.error = "Couldn't save. Nothing was changed."
        }
    }
}
