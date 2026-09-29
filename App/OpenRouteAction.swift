import SwiftUI
import VerbKit

/// Lets any view navigate to a `Route` (verb or grammar point) without
/// knowing which tab or stack owns it. `MainTabView` provides the real
/// handler; the default is a no-op so previews and isolated views work.
struct OpenRouteAction {
    var handler: (Route) -> Void = { _ in }

    func callAsFunction(_ route: Route) {
        handler(route)
    }
}

private struct OpenRouteKey: EnvironmentKey {
    static let defaultValue = OpenRouteAction()
}

extension EnvironmentValues {
    var openRoute: OpenRouteAction {
        get { self[OpenRouteKey.self] }
        set { self[OpenRouteKey.self] = newValue }
    }
}
