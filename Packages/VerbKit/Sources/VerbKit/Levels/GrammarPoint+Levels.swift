/// Per-usage levels. A lesson's `jlpt` is the default; a usage's own `jlpt` overrides it for that
/// usage only. The lesson is visible when any usage is, and spans the range of its usage levels.
extension GrammarPoint: Leveled {
    /// The level `usage` counts at: its own, or else the lesson's.
    public func level(of usage: GrammarUsage) -> JLPTLevel? {
        usage.jlpt ?? jlpt
    }

    /// The usages `settings` shows, in order. A usage without any level is always shown.
    public func visibleUsages(in settings: LevelSettings) -> [GrammarUsage] {
        usages.filter { settings.isVisible(level(of: $0)) }
    }

    /// Visible when any usage is visible (a lesson without usages falls back to its own level).
    public func isVisible(in settings: LevelSettings) -> Bool {
        guard !usages.isEmpty else { return settings.isVisible(jlpt) }
        return usages.contains { settings.isVisible(level(of: $0)) }
    }

    /// The levels of the lesson's usages (the lesson's own level when it has none).
    public var levelsTaught: Set<JLPTLevel> {
        guard !usages.isEmpty else { return jlpt.map { [$0] } ?? [] }
        return Set(usages.compactMap { level(of: $0) })
    }

    /// Easiest to hardest usage level, e.g. N4...N3; nil when no usage has a level.
    public var levelRange: ClosedRange<JLPTLevel>? {
        let levels = levelsTaught
        guard let low = levels.min(), let high = levels.max() else { return nil }
        return low...high
    }

    /// True when the usages do not all share one level, so each usage is worth labelling.
    public var hasMixedLevels: Bool {
        levelsTaught.count > 1
    }
}
