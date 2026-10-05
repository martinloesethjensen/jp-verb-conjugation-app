import SwiftUI
import VerbKit

/// Reads a `.wordbank` file, shows what importing it would do, and does it on Import.
/// Nothing is saved until then, and a backup of the current bank is made first.
struct WordBankImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    @Environment(WordBankTransferHub.self) private var hub
    let request: WordBankImportRequest

    private enum Phase {
        case loading
        case failed(String)
        case ready(WordBankArchive)
    }

    @State private var phase = Phase.loading
    @State private var destination = ImportDestination.root
    @State private var plan: WordBankImportPlan?
    @State private var choosingFolder = false
    @State private var importError: String?

    private var destinationName: String {
        if case .folder(let id) = destination, let folder = store.tree.folder(id) {
            return store.tree.path(of: folder.id).map(\.name).joined(separator: " › ")
        }
        return "Word Bank"
    }

    private var destinationFolder: UUID? {
        if case .folder(let id) = destination { id } else { nil }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Import")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import", action: runImport).disabled(plan?.summary.changesAnything != true)
                    }
                }
        }
        .task { load() }
        .sheet(isPresented: $choosingFolder) {
            FolderPicker(title: "Import into…", current: destinationFolder) { target in
                destination = target.map(ImportDestination.folder) ?? .root
            }
        }
        .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onChange(of: destination) { replan() }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Reading file…")
        case .failed(let message):
            ContentUnavailableView("Can't import this file", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready:
            if let plan { preview(plan.summary) }
        }
    }

    private func preview(_ summary: WordBankImportSummary) -> some View {
        Form {
            Section("Import into") {
                Button {
                    choosingFolder = true
                } label: {
                    HStack {
                        Label(destinationName, systemImage: destinationFolder == nil ? "books.vertical" : "folder")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if summary.changesAnything {
                Section {
                    countRow("New entries", summary.newEntries, "plus.circle")
                    countRow("Combined with entries you have", summary.combinedEntries, "arrow.triangle.merge")
                    countRow("Already in your Word Bank", summary.unchangedEntries, "checkmark.circle")
                    countRow("New folders", summary.newFolders.count, "folder.badge.plus")
                    countRow("New dialect tags", summary.newDialectTags.count, "mappin.and.ellipse")
                    countRow("New tags", summary.newCustomTags.count, "number")
                    countRow("New smart folders", summary.newSmartFolders.count, "gearshape.2")
                } header: {
                    Text("This will")
                } footer: {
                    Text("Nothing you have is overwritten or deleted. A backup is made first, so you can undo this in Settings › Word Bank › Restore backup.")
                }
                if !summary.newFolders.isEmpty {
                    Section("New folders") {
                        ForEach(Array(summary.newFolders.prefix(8).enumerated()), id: \.offset) { _, path in
                            Label(path.joined(separator: " › "), systemImage: "folder")
                        }
                        if summary.newFolders.count > 8 {
                            Text("and \(summary.newFolders.count - 8) more").foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Section {
                    Label("Everything in this file is already in your Word Bank.", systemImage: "checkmark.circle")
                }
            }
            if !summary.skipped.isEmpty {
                Section("Skipped") {
                    ForEach(Array(summary.skipped.enumerated()), id: \.offset) { _, skipped in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(skipped.section) #\(skipped.position)")
                            Text(skipped.reason).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func countRow(_ title: String, _ count: Int, _ systemImage: String) -> some View {
        if count > 0 {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Actions

    private func load() {
        let url = request.url
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let archive = try WordBankArchive.decode(try Data(contentsOf: url))
            phase = .ready(archive)
            replan()
        } catch let error as WordBankArchive.ArchiveError {
            switch error {
            case .newerVersion: phase = .failed("This file was made by a newer version of the app. Update the app to import it.")
            case .tooLarge: phase = .failed("This file is larger than 20 MB.")
            case .notAWordBank: phase = .failed("This isn't a Word Bank file.")
            }
        } catch {
            phase = .failed("The file couldn't be read.")
        }
    }

    private func replan() {
        guard case .ready(let archive) = phase else { return }
        plan = hub.transfer.plan(archive, destination: destination)
    }

    private func runImport() {
        guard let plan else { return }
        do {
            try hub.transfer.perform(plan)
            let added = plan.summary.newEntries, combined = plan.summary.combinedEntries
            hub.notice = [added > 0 ? "Added \(added) \(added == 1 ? "entry" : "entries")" : nil,
                          combined > 0 ? "combined \(combined)" : nil].compactMap { $0 }.joined(separator: ", ")
            dismiss()
        } catch WordBankTransferError.backupFailed {
            importError = "Couldn't make a backup first, so nothing was imported."
        } catch {
            importError = "Couldn't save. Nothing was changed."
        }
    }
}
