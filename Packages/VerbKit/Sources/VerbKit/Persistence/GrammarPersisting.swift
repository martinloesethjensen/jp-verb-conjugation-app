@MainActor
public protocol GrammarPersisting {
    func loadAllGrammarPoints() throws -> [GrammarPoint]
    func loadAllTextbooks() throws -> [Textbook]
    /// Replaces points and textbooks together, in one save.
    func replaceAllGrammar(points: [GrammarPoint], textbooks: [Textbook]) throws
}
