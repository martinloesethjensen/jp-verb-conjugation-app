import SwiftData

@MainActor
public final class SwiftDataKanjiPersisting: KanjiPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadKanji() throws -> SyncedKanjiData? {
        try modelContext.fetch(FetchDescriptor<KanjiDataEntity>()).first?.toSynced()
    }

    public func replaceKanji(with synced: SyncedKanjiData) throws {
        try modelContext.delete(model: KanjiDataEntity.self)
        modelContext.insert(KanjiDataEntity(synced))
        try modelContext.save()
    }
}
