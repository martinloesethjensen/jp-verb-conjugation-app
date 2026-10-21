import Foundation
import Observation
import os

/// One of the published data files the app syncs.
public enum DataFile: String, CaseIterable, Identifiable, Sendable {
    case verbs, grammar, furigana, words, counters

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .verbs: return "Verbs"
        case .grammar: return "Grammar"
        case .furigana: return "Furigana"
        case .words: return "Words"
        case .counters: return "Counters"
        }
    }
}

/// Why the last check of a file did not bring in new data, in terms a user can act on.
/// The underlying error is only logged, never shown.
public enum DataSyncProblem: Equatable, Sendable {
    case offline
    case serverUnreachable
    /// Hash mismatch, undecodable, or over the size cap.
    case damaged
    /// Bad or missing signature, or an older version than one already accepted.
    case untrusted
    /// The download was fine but saving it on the device failed.
    case couldNotSave

    public init(syncError error: Error) {
        switch error as? VerbSyncError {
        case .offline: self = .offline
        case .serverUnreachable: self = .serverUnreachable
        case .malformedData: self = .damaged
        case .untrusted: self = .untrusted
        case nil: self = .serverUnreachable
        }
    }

    var reason: String {
        switch self {
        case .offline: return "You're offline."
        case .serverUnreachable: return "The data server couldn't be reached."
        case .damaged: return "The download was incomplete, so it wasn't used."
        case .untrusted: return "The download couldn't be verified, so it wasn't used."
        case .couldNotSave: return "The download couldn't be saved on this device."
        }
    }
}

/// What Settings shows for one file.
public struct DataFileStatus: Equatable, Sendable {
    public let file: DataFile
    /// The version of the data on this device; `nil` until one has been saved.
    public var version: String?
    /// When the version on this device was first saved. A same-version re-download
    /// (e.g. after an app update) does not move it.
    public var lastUpdated: Date?
    /// When the server last answered for this file, with or without new data.
    public var lastChecked: Date?
    /// Set when the latest check failed; cleared by the next one that succeeds.
    public var problem: DataSyncProblem?

    public var hasData: Bool { version != nil }

    /// A plain-language line for the latest problem, or `nil` when there is none.
    public var problemMessage: String? {
        guard let problem else { return nil }
        let fallback = hasData ? "The data on this device is still in use." : "Try again later."
        return "\(problem.reason) \(fallback)"
    }
}

/// Collects how each data file's sync went, for the Data section in Settings, and runs
/// the manual refresh. The stores report into it; it never affects what they load.
///
/// Version and last-updated survive relaunches; problems are kept in memory only,
/// since the launch sync checks again anyway.
@MainActor
@Observable
public final class DataSyncStatus {
    public private(set) var files: [DataFile: DataFileStatus] = [:]
    public private(set) var isRefreshing = false

    /// Runs every store's sync. Set once by the app after the stores exist.
    @ObservationIgnored public var refreshHandler: (@MainActor () async -> Void)?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let logger = Logger(subsystem: "dev.martinloeseth.jpverbconjugation", category: "sync")

    public init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        for file in DataFile.allCases {
            files[file] = DataFileStatus(
                file: file,
                version: defaults.string(forKey: key(file, "version")),
                lastUpdated: defaults.object(forKey: key(file, "lastUpdated")) as? Date,
                lastChecked: defaults.object(forKey: key(file, "lastChecked")) as? Date
            )
        }
    }

    public func status(for file: DataFile) -> DataFileStatus {
        files[file] ?? DataFileStatus(file: file)
    }

    /// The server answered and nothing changed (or the file isn't published yet).
    public func recordUpToDate(_ file: DataFile) {
        var status = status(for: file)
        status.lastChecked = now()
        status.problem = nil
        save(status)
    }

    /// `version` was saved on the device and confirmed.
    public func recordUpdated(_ file: DataFile, version: String) {
        var status = status(for: file)
        let date = now()
        if status.version != version || status.lastUpdated == nil {
            status.lastUpdated = date
        }
        status.version = version
        status.lastChecked = date
        status.problem = nil
        save(status)
    }

    /// The sync, or saving its result (`whileSaving`), failed. The data on the device is untouched.
    public func recordFailure(_ file: DataFile, _ error: Error, whileSaving: Bool = false) {
        let problem = whileSaving ? DataSyncProblem.couldNotSave : DataSyncProblem(syncError: error)
        logger.error("Sync of \(file.rawValue, privacy: .public) failed (\(String(describing: problem), privacy: .public)): \(String(describing: error), privacy: .private)")
        var status = status(for: file)
        status.problem = problem
        files[file] = status
    }

    /// Runs `refreshHandler` unless a refresh is already running.
    public func refresh() async {
        guard !isRefreshing, let refreshHandler else { return }
        isRefreshing = true
        await refreshHandler()
        isRefreshing = false
    }

    private func save(_ status: DataFileStatus) {
        files[status.file] = status
        defaults.set(status.version, forKey: key(status.file, "version"))
        defaults.set(status.lastUpdated, forKey: key(status.file, "lastUpdated"))
        defaults.set(status.lastChecked, forKey: key(status.file, "lastChecked"))
    }

    private func key(_ file: DataFile, _ field: String) -> String {
        "VerbKit.dataSync.\(file.rawValue).\(field)"
    }
}
