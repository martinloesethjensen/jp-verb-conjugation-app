import Foundation

extension UserDefaults {
    /// The App Group's defaults, which the app and the widgets share. VerbKit owns the
    /// suite and the fallback; this is the name App code uses.
    static let appGroup = UserDefaults.verbKitAppGroup
}
