import VerbKit
import os
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

    private static let log = Logger(subsystem: "dev.martinloeseth.jpverbconjugation", category: "AppIcon")
    /// True while iOS is changing the icon: a second tap would queue a second alert.
    private static var changing = false

    static func apply(_ change: IconChange?) {
        #if os(iOS)
        guard let change, isSupported, !changing else { return }
        changing = true
        UIApplication.shared.setAlternateIconName(change.name) { error in
            if let error { log.error("Changing the app icon failed: \(error.localizedDescription, privacy: .public)") }
            Task { @MainActor in changing = false }
        }
        #endif
    }
}
