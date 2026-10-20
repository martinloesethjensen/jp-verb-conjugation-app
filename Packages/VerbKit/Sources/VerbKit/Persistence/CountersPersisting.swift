@MainActor
public protocol CountersPersisting {
    /// The cached counters and groups, or `nil` if none have been stored yet.
    func loadCounters() throws -> CountersDataFile?
    func replaceCounters(with file: CountersDataFile) throws
}
