import Foundation
import SwiftData

@MainActor
public final class SwiftDataVerbPersisting: VerbPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadAllVerbs() throws -> [Verb] {
        let entities = try modelContext.fetch(FetchDescriptor<VerbEntity>(sortBy: [SortDescriptor(\VerbEntity.sortOrder)]))
        return entities.compactMap { $0.toVerb() }
    }

    public func replaceAllVerbs(with verbs: [Verb]) throws {
        // A failed save must not leave its pending delete and inserts in the shared context, where the
        // next save of any store would commit them.
        do {
            try modelContext.delete(model: VerbEntity.self)
            for (index, verb) in verbs.enumerated() {
                modelContext.insert(VerbEntity(verb, sortOrder: index))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
