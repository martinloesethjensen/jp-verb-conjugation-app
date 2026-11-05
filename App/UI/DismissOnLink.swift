import SwiftUI

extension EnvironmentValues {
    /// Goes up by one each time a `verbtable://` link (a widget, Spotlight, Siri or a reminder)
    /// opens a page or a quiz. `RootView` owns it; read it through `dismissOnLink(_:)`.
    @Entry var linkArrivals = 0
}

private struct DismissOnLink: ViewModifier {
    @Environment(\.linkArrivals) private var linkArrivals
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: linkArrivals) { dismiss() }
    }
}

extension View {
    /// Runs `dismiss` when a link opens something, so a sheet or popover presented here does
    /// not hide the page the link opened (#12). Use it for read-only presentations (a guide,
    /// a translation, a lookup), not for editors or quizzes, which would lose work.
    func dismissOnLink(_ dismiss: @escaping () -> Void) -> some View {
        modifier(DismissOnLink(dismiss: dismiss))
    }
}
