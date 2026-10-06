import SwiftData

@MainActor
public final class SwiftDataWordsPersisting: WordsPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadWords() throws -> [Word]? {
        try modelContext.fetch(FetchDescriptor<WordsEntity>()).first?.toWords()
    }

    public func replaceWords(with words: [Word]) throws {
        try modelContext.delete(model: WordsEntity.self)
        modelContext.insert(WordsEntity(words))
        try modelContext.save()
    }
}
