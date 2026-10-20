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
        try modelContext.delete(model: CountersEntity.self)
        modelContext.insert(CountersEntity(file))
        try modelContext.save()
    }
}
