@MainActor
public protocol VerbPersisting {
    func loadAllVerbs() throws -> [Verb]
    func replaceAllVerbs(with verbs: [Verb]) throws
}
