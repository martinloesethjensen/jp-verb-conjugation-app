import SwiftUI

/// Applies the Appearance setting to the whole app at window level. `preferredColorScheme`
/// cannot do this alone: going back to System leaves an already-open sheet in the old
/// scheme. A window override reaches every sheet and cover, and changes cross-fade.
@MainActor
enum AppearanceApplier {
    static func apply(_ mode: AppearanceMode) {
        #if os(iOS)
        let style: UIUserInterfaceStyle = switch mode {
        case .system: .unspecified
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
        NSApp.appearance = switch mode {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        #endif
    }
}
