import SwiftUI
import VerbKit

/// A `.wordbank` file waiting to be imported: picked in the app or opened from outside it.
struct WordBankImportRequest: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Import, export and backups for the Word Bank, shared by the tab, the Settings screen and
/// the code that receives files from outside the app.
@MainActor
@Observable
final class WordBankTransferHub {
    let transfer: WordBankTransfer
    let backups: WordBankBackupStore
    /// Set to show the import sheet.
    var pendingImport: WordBankImportRequest?
    /// A one-line result ("Added 3 entries") shown once.
    var notice: String?

    init(store: WordBankStore) {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: VerbModelContainer.appGroupIdentifier)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let backups = WordBankBackupStore(directory: base.appendingPathComponent("WordBankBackups", isDirectory: true))
        self.backups = backups
        transfer = WordBankTransfer(store: store, backups: backups)
    }
}
