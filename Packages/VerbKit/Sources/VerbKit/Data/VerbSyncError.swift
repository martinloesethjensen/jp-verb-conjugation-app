public enum VerbSyncError: Error, Equatable, Sendable {
    case offline
    case serverUnreachable
    case malformedData
}
