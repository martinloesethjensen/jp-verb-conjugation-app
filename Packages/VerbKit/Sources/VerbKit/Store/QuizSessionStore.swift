import Foundation
import Observation

/// Keeps the one running verb quiz (a `QuizSession`) as JSON in the App Group defaults, so it
/// can be resumed after the app is killed or left for another page.
@MainActor
@Observable
public final class QuizSessionStore {
    public static let defaultsKey = "runningQuizSession"

    public private(set) var session: QuizSession?

    @ObservationIgnored private let defaults: UserDefaults

    /// An unreadable saved session (a damaged value, or one from a newer app) is dropped.
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: VerbModelContainer.appGroupIdentifier) ?? .standard
        if let data = self.defaults.data(forKey: Self.defaultsKey) {
            session = try? JSONDecoder().decode(QuizSession.self, from: data)
            if session == nil { self.defaults.removeObject(forKey: Self.defaultsKey) }
        }
    }

    public func save(_ session: QuizSession) {
        self.session = session
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    /// When the quiz is finished or quit.
    public func clear() {
        session = nil
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    /// The saved quiz ready to pick up again among `verbs` (every verb, not only the visible
    /// ones), or nil when there is none or it no longer fits the data.
    public func resumable(verbs: [Verb]) -> (questions: [QuizQuestion], progress: QuizProgressState)? {
        session?.restore(verbs: verbs)
    }

    /// Drops a saved quiz that no longer fits `verbs`, after the data or form set changes.
    /// Does nothing while there are no verbs yet, so a launch before the data loads keeps it.
    public func discardIfStale(verbs: [Verb]) {
        guard !verbs.isEmpty, session != nil, resumable(verbs: verbs) == nil else { return }
        clear()
    }
}
