public enum FirstLaunchState: Equatable, Sendable {
    case checking
    case fetching
    case failed(VerbSyncError)
    case success
}
