import SwiftUI
import VerbKit

/// What can be exported from where the user opened the sheet.
struct WordBankExportOption: Identifiable {
    let id = UUID()
    let title: String
    let scope: WordBankExportScope
}

struct WordBankExportRequest: Identifiable {
    let id = UUID()
    let options: [WordBankExportOption]
}

/// Pick what to export, then share it or save it to Files. The archive is rebuilt when the
/// choice changes, so what is shared is always what is selected.
struct WordBankExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    let request: WordBankExportRequest

    @State private var selected: UUID?
    @State private var prepared: Prepared?
    @State private var failed = false
    @State private var saving = false

    private struct Prepared {
        let url: URL
        let data: Data
        let name: String
    }

    private var option: WordBankExportOption? {
        request.options.first { $0.id == selected } ?? request.options.first
    }

    private func count(_ option: WordBankExportOption) -> Int {
        WordBankArchive(snapshot: store.snapshot, scope: option.scope).entries.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Export") {
                    ForEach(request.options) { option in
                        Button {
                            selected = option.id
                        } label: {
                            HStack {
                                Text(option.title)
                                Spacer()
                                Text("\(count(option))").foregroundStyle(.secondary).monospacedDigit()
                                if option.id == (self.option?.id) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Selected")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    if let prepared {
                        ShareLink(item: prepared.url) { Label("Share…", systemImage: "square.and.arrow.up") }
                        Button("Save to Files…", systemImage: "folder") { saving = true }
                    } else if failed {
                        Label("Couldn't prepare the file.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                } footer: {
                    Text("A .wordbank file holds entries, folders and tags. Importing it again, here or on another device, never overwrites anything.")
                }
            }
            .navigationTitle("Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: option?.id) { prepare() }
            .fileExporter(
                isPresented: $saving,
                document: WordBankFile(data: prepared?.data ?? Data()),
                contentType: .wordBank,
                defaultFilename: prepared?.name ?? "Word Bank"
            ) { _ in }
        }
        .presentationDetents([.medium, .large])
    }

    private func prepare() {
        guard let option else { return }
        let snapshot = store.snapshot
        let name = WordBankArchive.suggestedFileName(for: option.scope, in: snapshot)
        do {
            let data = try WordBankArchive(snapshot: snapshot, scope: option.scope).encoded()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).wordbank")
            try data.write(to: url, options: .atomic)
            prepared = Prepared(url: url, data: data, name: name)
            failed = false
        } catch {
            prepared = nil
            failed = true
        }
    }
}
