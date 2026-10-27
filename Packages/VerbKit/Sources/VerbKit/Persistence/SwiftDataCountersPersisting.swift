import SwiftData

@MainActor
public final class SwiftDataCountersPersisting: CountersPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadCounters() throws -> CountersDataFile? {
        try modelContext.fetch(FetchDescriptor<CountersEntity>()).first?.toFile()
    }

    public func replaceCounters(with file: CountersDataFile) throws {
        // A failed save must not leave its pending delete and inserts in the shared context, where the
        // next save of any store would commit them.
        do {
            try modelContext.delete(model: CountersEntity.self)
            modelContext.insert(CountersEntity(file))
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
