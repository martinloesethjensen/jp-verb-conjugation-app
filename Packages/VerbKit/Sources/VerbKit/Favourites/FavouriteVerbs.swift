import Foundation

/// The verbs the user has starred, by `Verb.id`. Stored as one string in the shared defaults
/// (newline-separated, sorted) so the widget can read it too. Ids that no longer exist are harmless.
public struct FavouriteVerbs: Equatable, Sendable {
    public static let defaultsKey = "favouriteVerbs"

    public var ids: Set<String>

    public init(ids: Set<String> = []) {
        self.ids = ids
    }

    /// Parses the stored string; nil and blank lines are ignored.
    public init(rawValue: String?) {
        self.ids = Set((rawValue ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty })
    }

    public var rawValue: String { ids.sorted().joined(separator: "\n") }

    public var isEmpty: Bool { ids.isEmpty }

    public func contains(_ verb: Verb) -> Bool { ids.contains(verb.id) }

    public mutating func toggle(_ verb: Verb) {
        if ids.contains(verb.id) { ids.remove(verb.id) } else { ids.insert(verb.id) }
    }

    /// The starred verbs among `verbs`, in their original order.
    public func filter(_ verbs: [Verb]) -> [Verb] {
        verbs.filter(contains)
    }

    /// How many of `verbs` are starred.
    public func count(in verbs: [Verb]) -> Int {
        verbs.reduce(0) { $0 + (contains($1) ? 1 : 0) }
    }
}
