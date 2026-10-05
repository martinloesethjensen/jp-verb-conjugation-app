import Foundation
import SwiftData

public enum VerbModelContainerError: Error {
    case appGroupUnavailable
}

public enum VerbModelContainer {
    public static let appGroupIdentifier = "group.dev.martinloeseth.jpverbconjugation"

    /// The synced data and quiz history: VerbKit.sqlite, unchanged since before the Word Bank.
    static let verbModels: [any PersistentModel.Type] = [
        VerbEntity.self, GrammarEntity.self, FuriganaEntity.self, QuizAttemptEntity.self,
    ]

    /// The user's Word Bank: its own file, WordBank.sqlite, so a data re-sync can never touch it.
    static let wordBankModels: [any PersistentModel.Type] = [
        WordBankEntryEntity.self, WordBankFolderEntity.self, DialectTagEntity.self, CustomTagEntity.self,
        WordBankSmartFolderEntity.self,
    ]

    public static let wordBankSchema = Schema(wordBankModels)

    private static let schema = Schema(verbModels + wordBankModels)

    /// The real, on-disk, App Group-shared store used by the app, the widgets and
    /// the Siri intents.
    public static func make() throws -> ModelContainer {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw VerbModelContainerError.appGroupUnavailable
        }
        return try make(directory: groupURL)
    }

    /// Both stores in `directory`: VerbKit.sqlite and WordBank.sqlite.
    static func make(directory: URL) throws -> ModelContainer {
        let verbs = ModelConfiguration(
            "VerbKit", schema: Schema(verbModels), url: directory.appendingPathComponent("VerbKit.sqlite")
        )
        let wordBank = ModelConfiguration(
            "WordBank", schema: wordBankSchema, url: directory.appendingPathComponent("WordBank.sqlite")
        )
        return try ModelContainer(for: schema, configurations: [verbs, wordBank])
    }

    /// An in-memory store for tests and previews; never touches disk.
    public static func makeInMemory() throws -> ModelContainer {
        let verbs = ModelConfiguration("VerbKit", schema: Schema(verbModels), isStoredInMemoryOnly: true)
        let wordBank = ModelConfiguration("WordBank", schema: wordBankSchema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [verbs, wordBank])
    }
}
