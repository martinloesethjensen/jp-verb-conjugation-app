import Foundation
import SwiftData

@MainActor
public final class SwiftDataQuizHistoryPersisting: QuizHistoryPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Oldest first; equal dates keep fetch (insertion) order.
    public func loadAll() throws -> [QuizAttempt] {
        let attempts = try modelContext.fetch(FetchDescriptor<QuizAttemptEntity>()).compactMap { $0.toAttempt() }
        return attempts.enumerated()
            .sorted { l, r in l.element.date != r.element.date ? l.element.date < r.element.date : l.offset < r.offset }
            .map(\.element)
    }

    public func append(_ attempt: QuizAttempt) throws {
        modelContext.insert(QuizAttemptEntity(attempt))
        try modelContext.save()
    }

    public func deleteAll() throws {
        try modelContext.delete(model: QuizAttemptEntity.self)
        try modelContext.save()
    }
}
