import SwiftUI
import VerbKit

private struct FuriganaEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct FuriganaDictionaryKey: EnvironmentKey {
    static let defaultValue: FuriganaDictionary? = nil
}

extension EnvironmentValues {
    /// The user's "Show furigana" setting. `RootView` sets it once, so one
    /// toggle flips every screen live.
    var furiganaEnabled: Bool {
        get { self[FuriganaEnabledKey.self] }
        set { self[FuriganaEnabledKey.self] = newValue }
    }

    /// The reading dictionary, or `nil` until one has loaded (which means
    /// no furigana is shown).
    var furiganaDictionary: FuriganaDictionary? {
        get { self[FuriganaDictionaryKey.self] }
        set { self[FuriganaDictionaryKey.self] = newValue }
    }
}
