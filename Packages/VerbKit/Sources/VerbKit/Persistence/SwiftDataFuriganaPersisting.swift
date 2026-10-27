import SwiftData

@MainActor
public final class SwiftDataFuriganaPersisting: FuriganaPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadFuriganaDictionary() throws -> FuriganaDictionary? {
        try modelContext.fetch(FetchDescriptor<FuriganaEntity>()).first?.toDictionary()
    }

    public func replaceFuriganaDictionary(with dictionary: FuriganaDictionary) throws {
        // A failed save must not leave its pending delete and inserts in the shared context, where the
        // next save of any store would commit them.
        do {
            try modelContext.delete(model: FuriganaEntity.self)
            modelContext.insert(FuriganaEntity(dictionary))
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
