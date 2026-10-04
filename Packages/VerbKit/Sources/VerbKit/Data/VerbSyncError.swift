public enum VerbSyncError: Error, Equatable, Sendable {
    case offline
    case serverUnreachable
    case malformedData
    /// The manifest's signature is missing or wrong, or it is older than one already accepted.
    case untrusted
}
