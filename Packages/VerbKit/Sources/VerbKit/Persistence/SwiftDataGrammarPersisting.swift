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

    public func replaceAllGrammarPoints(with points: [GrammarPoint]) throws {
        try modelContext.delete(model: GrammarEntity.self)
        for (index, point) in points.enumerated() {
            modelContext.insert(GrammarEntity(point, sortOrder: index))
        }
        try modelContext.save()
    }
}
