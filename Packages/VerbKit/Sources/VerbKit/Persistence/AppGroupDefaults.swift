import Foundation

public extension UserDefaults {
    /// The App Group's defaults, shared by the app, its widgets and the intents, or the
    /// standard domain when the group is unavailable (an unsigned build or a misconfigured team).
    static var verbKitAppGroup: UserDefaults {
        UserDefaults(suiteName: VerbModelContainer.appGroupIdentifier) ?? .standard
    }
}
