import SwiftUI
import VerbKit

/// Applies the theme's light/dark appearance to the whole app at window level.
/// `preferredColorScheme` cannot do this alone: going back to the system appearance leaves an
/// already-open sheet in the old scheme. A window override reaches every sheet, alert, menu and
/// the keyboard, and changes cross-fade.
@MainActor
enum ThemeApplier {
    static func apply(_ appearance: ThemeAppearance) {
        #if os(iOS)
        let style: UIUserInterfaceStyle = switch appearance {
        case .followSystem: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                UIView.transition(with: window, duration: 0.25, options: .transitionCrossDissolve) {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
        #elseif os(macOS)
        NSApp.appearance = switch appearance {
        case .followSystem: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        #endif
    }
}
