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
        // A failed save must not leave its pending delete and inserts in the shared context, where the
        // next save of any store would commit them.
        do {
            try modelContext.delete(model: WordsEntity.self)
            modelContext.insert(WordsEntity(words))
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
