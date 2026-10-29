/// An item that may carry a JLPT level. Items without a level (nil) are always visible.
///
/// An item that spans several levels (a grammar lesson whose usages differ) overrides
/// `isVisible(in:)` and `levelsTaught`; the defaults use `jlpt` alone.
public protocol Leveled {
    var jlpt: JLPTLevel? { get }
    /// Whether `settings` shows the item.
    func isVisible(in settings: LevelSettings) -> Bool
    /// Every level the item covers (empty when it has none).
    var levelsTaught: Set<JLPTLevel> { get }
}

public extension Leveled {
    func isVisible(in settings: LevelSettings) -> Bool {
        settings.isVisible(jlpt)
    }

    var levelsTaught: Set<JLPTLevel> {
        jlpt.map { [$0] } ?? []
    }
}

extension Verb: Leveled {}
extension Counter: Leveled {}

public extension Sequence where Element: Leveled {
    /// The elements visible under `settings`, in their original order. Elements without a level are kept.
    func visible(in settings: LevelSettings) -> [Element] {
        filter { $0.isVisible(in: settings) }
    }

    /// How many elements `settings` hides.
    func hiddenCount(in settings: LevelSettings) -> Int {
        reduce(0) { $0 + ($1.isVisible(in: settings) ? 0 : 1) }
    }

    /// The levels present among the elements (nil skipped).
    func levels() -> Set<JLPTLevel> {
        reduce(into: []) { $0.formUnion($1.levelsTaught) }
    }
}
