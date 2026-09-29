@MainActor
public protocol GrammarPersisting {
    func loadAllGrammarPoints() throws -> [GrammarPoint]
    func replaceAllGrammarPoints(with points: [GrammarPoint]) throws
}
