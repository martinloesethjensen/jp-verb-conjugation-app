import Observation

@MainActor
@Observable
public final class QuizHistoryStore {
    public private(set) var attempts: [QuizAttempt]

    private let persisting: QuizHistoryPersisting

    public init(persisting: QuizHistoryPersisting) {
        self.persisting = persisting
        self.attempts = (try? persisting.loadAll()) ?? []
    }

    /// Appends in memory and persists; a persistence failure is swallowed so a
    /// quiz is never interrupted by history storage.
    public func record(_ attempt: QuizAttempt) {
        attempts.append(attempt)
        try? persisting.append(attempt)
    }

    public func reset() {
        try? persisting.deleteAll()
        attempts = []
    }
}
