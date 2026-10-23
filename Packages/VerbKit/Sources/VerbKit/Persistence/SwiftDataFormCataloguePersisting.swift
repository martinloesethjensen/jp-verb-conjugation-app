import SwiftData

@MainActor
public final class SwiftDataFormCataloguePersisting: FormCataloguePersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadFormCatalogue() throws -> SyncedFormCatalogue? {
        try modelContext.fetch(FetchDescriptor<FormCatalogueEntity>()).first?.toSynced()
    }

    public func replaceFormCatalogue(with synced: SyncedFormCatalogue) throws {
        try modelContext.delete(model: FormCatalogueEntity.self)
        modelContext.insert(FormCatalogueEntity(synced))
        try modelContext.save()
    }
}
