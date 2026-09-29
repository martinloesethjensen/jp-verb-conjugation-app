/// A place the app can navigate to. Both the Verbs and Grammar stacks —
/// and, later, widget taps and Shortcuts — resolve through this one type.
public enum Route: Hashable, Sendable {
    /// `Verb.id` (the dictionary form).
    case verb(String)
    /// `GrammarPoint.id`.
    case grammar(String)
}

public enum RouteTarget: Equatable, Sendable {
    case verb(Verb)
    case grammar(GrammarPoint)
}

public extension Route {
    /// `nil` when the target doesn't exist locally (e.g. a grammar point
    /// that hasn't synced yet), so callers can hide the link instead of
    /// navigating nowhere.
    func resolve(verbs: [Verb], grammarPoints: [GrammarPoint]) -> RouteTarget? {
        switch self {
        case let .verb(id):
            return verbs.first { $0.id == id }.map(RouteTarget.verb)
        case let .grammar(id):
            return grammarPoints.first { $0.id == id }.map(RouteTarget.grammar)
        }
    }
}
