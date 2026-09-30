@MainActor
public protocol FuriganaPersisting {
    /// The cached dictionary, or `nil` if none has been stored yet.
    func loadFuriganaDictionary() throws -> FuriganaDictionary?
    func replaceFuriganaDictionary(with dictionary: FuriganaDictionary) throws
}
