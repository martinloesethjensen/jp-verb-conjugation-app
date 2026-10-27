import Foundation
import SwiftData

@MainActor
public final class SwiftDataGrammarPersisting: GrammarPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadAllGrammarPoints() throws -> [GrammarPoint] {
        let descriptor = FetchDescriptor<GrammarEntity>(sortBy: [SortDescriptor(\.sortOrder)])
        return try modelContext.fetch(descriptor).compactMap { $0.toGrammarPoint() }
    }

    public func loadAllTextbooks() throws -> [Textbook] {
        let descriptor = FetchDescriptor<TextbookEntity>(sortBy: [SortDescriptor(\.sortOrder)])
        return try modelContext.fetch(descriptor).compactMap { $0.toTextbook() }
    }

    public func replaceAllGrammar(points: [GrammarPoint], textbooks: [Textbook]) throws {
        // A failed save must not leave its pending delete and inserts in the shared context, where the
        // next save of any store would commit them.
        do {
            try modelContext.delete(model: GrammarEntity.self)
            try modelContext.delete(model: TextbookEntity.self)
            for (index, book) in textbooks.enumerated() {
                modelContext.insert(TextbookEntity(book, sortOrder: index))
            }
            for (index, point) in points.enumerated() {
                modelContext.insert(GrammarEntity(point, sortOrder: index))
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
