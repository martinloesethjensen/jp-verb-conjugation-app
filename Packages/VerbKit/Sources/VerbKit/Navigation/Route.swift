/// A place the app can navigate to. Both the Verbs and Grammar stacks —
/// and, later, widget taps and Shortcuts — resolve through this one type.
public enum Route: Hashable, Sendable {
    /// `Verb.id` (the dictionary form).
    case verb(String)
    /// `GrammarPoint.id`. `pitfall` is an index into the lesson's `pitfalls`: the lesson opens
    /// scrolled to that pitfall (Common mistakes uses it). It is in-app only — `url` leaves it out,
    /// so a `verbtable://grammar/<id>` link always opens the lesson at its top.
    case grammar(String, pitfall: Int? = nil)
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
    /// The pitfall a grammar route lands on, when that lesson has a pitfall at that index;
    /// `nil` for every other route, so the lesson opens at its top.
    func pitfallAnchor(in point: GrammarPoint) -> Int? {
        guard case let .grammar(id, pitfall?) = self, id == point.id, point.pitfalls.indices.contains(pitfall) else {
            return nil
        }
        return pitfall
    }

    /// The same page with any pitfall anchor dropped, for grouping or comparing by page.
    var withoutAnchor: Route {
        if case let .grammar(id, _?) = self { return .grammar(id) }
        return self
    }

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
        case let .grammar(id, _):
            return grammarPoints.first { $0.id == id }.map(RouteTarget.grammar)
        case let .counter(id):
            return counters.first { $0.id == id }.map(RouteTarget.counter)
        case let .counterGroup(id):
            return groups.first { $0.id == id }.map(RouteTarget.counterGroup)
        }
    }
}
