import VerbKit
#if os(iOS)
import UIKit
#endif

/// Applies an `AppIconMatching` decision. iOS shows its own alert for every change and only while
/// the app is open; the Mac has no alternate icons, so there it does nothing.
@MainActor
enum AppIconSwitcher {
    /// The alternate icon showing now, nil for the primary one (and always nil on the Mac).
    static var current: String? {
        #if os(iOS)
        UIApplication.shared.alternateIconName
        #else
        nil
        #endif
    }

    static var isSupported: Bool {
        #if os(iOS)
        UIApplication.shared.supportsAlternateIcons
        #else
        false
        #endif
    }

    static func apply(_ change: IconChange?) {
        #if os(iOS)
        guard let change, isSupported else { return }
        UIApplication.shared.setAlternateIconName(change.name) { _ in }
        #endif
    }
}
