import Foundation
import SwiftData

public enum VerbModelContainerError: Error {
    case appGroupUnavailable
}

public enum VerbModelContainer {
    public static let appGroupIdentifier = "group.dev.martinloeseth.jpverbconjugation"

    /// The real, on-disk, App Group-shared store — used by the app and,
    /// later, the widget/Shortcuts extension.
    public static func make() throws -> ModelContainer {
        let schema = Schema([VerbEntity.self, GrammarEntity.self])
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw VerbModelContainerError.appGroupUnavailable
        }
        let storeURL = groupURL.appendingPathComponent("VerbKit.sqlite")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An in-memory store for tests and previews — never touches disk.
    public static func makeInMemory() throws -> ModelContainer {
        let schema = Schema([VerbEntity.self, GrammarEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
