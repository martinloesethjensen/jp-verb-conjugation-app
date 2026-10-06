@MainActor
public protocol WordsPersisting {
    /// The cached word list, or `nil` if none has been stored yet.
    func loadWords() throws -> [Word]?
    func replaceWords(with words: [Word]) throws
}
