import Foundation

/// What the first-run flow asks: the levels studied, furigana and a theme.
public struct OnboardingChoices: Equatable, Sendable {
    public private(set) var levels: Set<JLPTLevel> = [.n5, .n4]
    public var furigana = true
    public var theme: ThemeID = .light

    public init() {}

    /// Starts with `theme` picked: a flow reopened after the app was killed keeps the theme it had
    /// already written (the theme page writes it live).
    public init(theme: ThemeID) {
        self.theme = theme
    }

    /// Picks or unpicks `level`; the last picked level stays picked.
    public mutating func toggle(_ level: JLPTLevel) {
        if levels.contains(level) {
            guard levels.count > 1 else { return }
            levels.remove(level)
        } else {
            levels.insert(level)
        }
    }

    /// Writes the three settings the flow owns: the hidden levels (keeping every dataset visible,
    /// `LevelSettings.studying`), furigana and the theme. Appearance and seasonal themes keep their
    /// stored values.
    public func apply(to appGroup: UserDefaults, amongEach datasets: [Set<JLPTLevel>]) {
        LevelSettings.studying(levels, amongEach: datasets).save(to: appGroup)
        appGroup.set(furigana, forKey: FuriganaSetting.defaultsKey)
        var choice = ThemeChoice.load(from: appGroup)
        choice.theme = theme
        choice.save(to: appGroup)
    }
}
