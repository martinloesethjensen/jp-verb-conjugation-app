@MainActor
public protocol QuizHistoryPersisting {
    func loadAll() throws -> [QuizAttempt]
    func append(_ attempt: QuizAttempt) throws
    func deleteAll() throws
}
