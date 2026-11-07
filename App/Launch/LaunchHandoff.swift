#if os(iOS)
import SwiftUI
import UIKit
import VerbKit

/// The app's first frame on a cold launch. It starts as an exact copy of the iOS launch screen
/// (the phone's own appearance, the default seal), fades the chosen theme's paper and stamp in
/// over 250 ms with 活 staying put, then fades away over 200 ms to the content. It never waits
/// for data; with Reduce Motion on it ends at once. Hidden from VoiceOver and never takes taps.
struct LaunchHandoff: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var themeShown = false
    @State private var overlayShown = true

    /// The launch screen follows the phone, not the app's Appearance setting, and the window
    /// override doesn't change the screen's traits.
    private var phoneIsDark: Bool {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.screen.traitCollection.userInterfaceStyle == .dark
    }

    var body: some View {
        let choice = ThemeChoice.load(from: .appGroup)
        let launchDark = phoneIsDark
        let launch = ThemePalette.resolve(.light, isDark: launchDark, contrast: .standard)
        let themeDark = choice.isDark(systemIsDark: launchDark)
        let theme = choice.effectiveTheme(on: .now)
        let themed = ThemePalette.resolve(theme, isDark: themeDark, contrast: contrast)
        ZStack {
            layer(paper: launch.paper, stamp: .stamp(for: .light, isDark: launchDark), ink: launch.ink)
            layer(paper: themed.paper, stamp: .stamp(for: theme, isDark: themeDark), ink: themed.ink)
                .opacity(themeShown ? 1 : 0)
        }
        .opacity(overlayShown ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            if reduceMotion { onFinished(); return }
            // Let the first screen draw underneath before anything moves.
            await Task.yield()
            withAnimation(.easeOut(duration: 0.25)) { themeShown = true }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeOut(duration: 0.2)) { overlayShown = false }
            try? await Task.sleep(for: .milliseconds(200))
            onFinished()
        }
    }

    private func layer(paper: Color, stamp: ThemeStamp, ink: Color) -> some View {
        ZStack {
            paper
            SealView(stamp: stamp, ink: ink)
        }
        .ignoresSafeArea()
    }
}
#endif
