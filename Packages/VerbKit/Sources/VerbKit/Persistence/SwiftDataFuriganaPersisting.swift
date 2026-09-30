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
        try modelContext.delete(model: FuriganaEntity.self)
        modelContext.insert(FuriganaEntity(dictionary))
        try modelContext.save()
    }
}
