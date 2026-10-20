/// A place the app can navigate to. Both the Verbs and Grammar stacks —
/// and, later, widget taps and Shortcuts — resolve through this one type.
public enum Route: Hashable, Sendable {
    /// `Verb.id` (the dictionary form).
    case verb(String)
    /// `GrammarPoint.id`.
    case grammar(String)
    /// `Counter.id`.
    case counter(String)
    /// `CounterGroup.id`.
    case counterGroup(String)
}

public enum RouteTarget: Equatable, Sendable {
    case verb(Verb)
    case grammar(GrammarPoint)
    case counter(Counter)
    case counterGroup(CounterGroup)
}

public extension Route {
    /// `nil` when the target doesn't exist locally (e.g. a grammar point
    /// that hasn't synced yet), so callers can hide the link instead of
    /// navigating nowhere. `counters` and `groups` default to empty so callers that only deal in
    /// verbs and grammar keep compiling.
    func resolve(
        verbs: [Verb], grammarPoints: [GrammarPoint], counters: [Counter] = [], groups: [CounterGroup] = []
    ) -> RouteTarget? {
        switch self {
        case let .verb(id):
            return verbs.first { $0.id == id }.map(RouteTarget.verb)
        case let .grammar(id):
            return grammarPoints.first { $0.id == id }.map(RouteTarget.grammar)
        case let .counter(id):
            return counters.first { $0.id == id }.map(RouteTarget.counter)
        case let .counterGroup(id):
            return groups.first { $0.id == id }.map(RouteTarget.counterGroup)
        }
    }
}
