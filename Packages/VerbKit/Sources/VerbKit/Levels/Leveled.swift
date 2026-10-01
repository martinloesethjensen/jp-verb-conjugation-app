/// An item that may carry a JLPT level. Items without a level (nil) are always visible.
public protocol Leveled {
    var jlpt: JLPTLevel? { get }
}

extension Verb: Leveled {}
extension GrammarPoint: Leveled {}

public extension Sequence where Element: Leveled {
    /// The elements visible under `settings`, in their original order. Elements without a level are kept.
    func visible(in settings: LevelSettings) -> [Element] {
        filter { settings.isVisible($0.jlpt) }
    }

    /// How many elements `settings` hides.
    func hiddenCount(in settings: LevelSettings) -> Int {
        reduce(0) { $0 + (settings.isVisible($1.jlpt) ? 0 : 1) }
    }

    /// The levels present among the elements (nil skipped).
    func levels() -> Set<JLPTLevel> {
        Set(compactMap(\.jlpt))
    }
}
