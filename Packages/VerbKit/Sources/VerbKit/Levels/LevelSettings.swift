import Foundation

/// Which JLPT levels the user has hidden. Stored as the HIDDEN set so a level added to the data later
/// appears automatically. Items without a level (nil) are always visible.
public struct LevelSettings: Equatable, Sendable {
    public static let defaultsKey = "hiddenJLPTLevels"

    public var hidden: Set<JLPTLevel>

    public init(hidden: Set<JLPTLevel> = []) {
        self.hidden = hidden
    }

    /// Parses "N4,N3"; nil, empty and unknown tokens are ignored.
    public init(rawValue: String?) {
        let tokens = (rawValue ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        self.hidden = Set(tokens.compactMap(JLPTLevel.init(rawValue:)))
    }

    /// Hidden levels sorted N5 first, comma-separated.
    public var rawValue: String {
        hidden.sorted().map(\.rawValue).joined(separator: ",")
    }

    public func isVisible(_ level: JLPTLevel?) -> Bool {
        guard let level else { return true }
        return !hidden.contains(level)
    }

    public func anyHidden(among available: Set<JLPTLevel>) -> Bool {
        !hidden.isDisjoint(with: available)
    }

    /// False when hiding `level` would leave no available level visible.
    public func canHide(_ level: JLPTLevel, among available: Set<JLPTLevel>) -> Bool {
        let remaining = available.subtracting(hidden).subtracting([level])
        return !remaining.isEmpty || !available.contains(level)
    }

    /// Describes the visible levels among `available`, best first (N5 first); nil when nothing among
    /// `available` is hidden. Visible levels that are consecutive among ALL FIVE JLPT levels
    /// (N5, N4, N3, N2, N1) form a range with an en dash ("N5–N4"); a level that exists in the JLPT but
    /// not in the data still breaks a run, so N5 and N3 with N4 absent give "N5, N3". Otherwise a comma
    /// list. A single visible level is just that level. If nothing is visible, returns "".
    public func summary(among available: Set<JLPTLevel>) -> String? {
        guard anyHidden(among: available) else { return nil }
        let visible = available.subtracting(hidden).sorted()
        guard let first = visible.first, let last = visible.last else { return "" }
        if visible.count == 1 { return first.rawValue }
        let all = JLPTLevel.allCases
        let contiguous = zip(visible, visible.dropFirst()).allSatisfy {
            all.firstIndex(of: $1)! == all.firstIndex(of: $0)! + 1
        }
        if contiguous { return "\(first.rawValue)–\(last.rawValue)" }
        return visible.map(\.rawValue).joined(separator: ", ")
    }

    private static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: VerbModelContainer.appGroupIdentifier) ?? .standard
    }

    public static func load(from defaults: UserDefaults? = nil) -> LevelSettings {
        LevelSettings(rawValue: (defaults ?? appGroupDefaults).string(forKey: defaultsKey))
    }

    public func save(to defaults: UserDefaults? = nil) {
        (defaults ?? Self.appGroupDefaults).set(rawValue, forKey: Self.defaultsKey)
    }
}
