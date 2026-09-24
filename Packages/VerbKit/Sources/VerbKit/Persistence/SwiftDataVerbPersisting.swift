import SwiftData

@MainActor
public final class SwiftDataVerbPersisting: VerbPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadAllVerbs() throws -> [Verb] {
        let entities = try modelContext.fetch(FetchDescriptor<VerbEntity>())
        return entities.compactMap { $0.toVerb() }
    }

    public func replaceAllVerbs(with verbs: [Verb]) throws {
        try modelContext.delete(model: VerbEntity.self)
        for verb in verbs {
            modelContext.insert(VerbEntity(verb))
        }
        try modelContext.save()
    }
}
