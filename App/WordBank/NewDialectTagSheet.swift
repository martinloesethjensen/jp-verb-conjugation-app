import SwiftUI
import VerbKit

/// What the new-dialect-tag sheet starts from: the text typed in the tag field, and a
/// prefecture when that text named one.
struct NewDialectRequest: Identifiable {
    let id = UUID()
    var name: String
    var preselected: Prefecture?
}

/// A dialect tag made by hand: name, optional romaji, a prefecture (which sets the region) or,
/// for a dialect spoken across several, just a region.
struct NewDialectTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WordBankStore.self) private var store
    let request: NewDialectRequest
    let onCreated: (DialectTagValue) -> Void
    @State private var name = ""
    @State private var romaji = ""
    @State private var prefecture: Prefecture?
    @State private var region: Region = .kanto
    @State private var error: WordBankError?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name (熊本弁)", text: $name)
                        .autocorrectionDisabled()
                    TextField("Romaji (Kumamoto-ben)", text: $romaji)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
                Section {
                    Picker("Prefecture", selection: $prefecture) {
                        Text("None (region only)").tag(Prefecture?.none)
                        ForEach(Region.allCases, id: \.self) { region in
                            Section(region.name) {
                                ForEach(region.prefectures, id: \.self) { Text($0.name).tag(Prefecture?.some($0)) }
                            }
                        }
                    }
                    if prefecture == nil {
                        Picker("Region", selection: $region) {
                            ForEach(Region.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                    }
                } footer: {
                    if let error {
                        Label(FolderNameSheet.message(error), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Dialect Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: name) { error = nil }
            .onAppear {
                name = request.name
                prefecture = request.preselected
                region = request.preselected?.region ?? .kanto
            }
        }
    }

    private func save() {
        let trimmedRomaji = romaji.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = DialectTagValue(
            name: name, romaji: trimmedRomaji.isEmpty ? nil : trimmedRomaji,
            prefectures: prefecture.map { [$0] } ?? [], region: prefecture?.region ?? region
        )
        do {
            let created = try store.createDialectTag(tag)
            onCreated(created)
            dismiss()
        } catch let failure as WordBankError {
            error = failure
        } catch {}
    }
}
