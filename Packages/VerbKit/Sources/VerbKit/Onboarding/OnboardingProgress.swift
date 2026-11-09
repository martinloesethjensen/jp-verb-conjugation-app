import Foundation

/// Whether to show the first-run flow. New installs see it once; an install that already has verb
/// data or a level or furigana setting is an existing one and never does. A flow left unfinished
/// (the app killed half-way) shows again, even though the first launch has written data by then.
public enum OnboardingProgress {
    /// App Group keys.
    public static let completedKey = "onboardingCompleted"
    public static let pendingKey = "onboardingPending"

    /// Call once at launch, before the stores install any data. `standard` holds the sync state.
    public static func begin(appGroup: UserDefaults, standard: UserDefaults) -> Bool {
        if appGroup.bool(forKey: completedKey) { return false }
        if appGroup.bool(forKey: pendingKey) { return true }
        let existing = UserDefaultsSyncStateStore.hasAcceptedVerbs(in: standard)
            || appGroup.object(forKey: LevelSettings.defaultsKey) != nil
            || appGroup.object(forKey: FuriganaSetting.defaultsKey) != nil
        if existing {
            appGroup.set(true, forKey: completedKey)
            return false
        }
        appGroup.set(true, forKey: pendingKey)
        return true
    }

    /// The flow is done: never show it again.
    public static func finish(appGroup: UserDefaults) {
        appGroup.set(true, forKey: completedKey)
        appGroup.removeObject(forKey: pendingKey)
    }
}
