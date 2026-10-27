import SwiftUI
import VerbKit

/// What the three home screen widgets share: the navy dusk gradient, the text
/// shown before the first sync, and the JLPT accent palette.
enum WidgetTheme {
    static let navy = Color(red: 0.043, green: 0.063, blue: 0.149)

    /// Opaque on the home screen; transparent on the lock screen and inline
    /// families, where the system draws its own surface.
    @ViewBuilder
    static func background(isHome: Bool) -> some View {
        if isHome {
            LinearGradient(colors: [navy, .black], startPoint: .top, endPoint: .bottom)
        } else {
            Color.clear
        }
    }

    /// The pastel that marks a grammar point's level.
    static func accent(for level: JLPTLevel?) -> Color {
        switch level {
        case .n5: Color(red: 0.176, green: 0.831, blue: 0.749)
        case .n4: Color(red: 0.486, green: 0.831, blue: 0.992)
        case .n3: Color(red: 0.655, green: 0.545, blue: 0.980)
        case .n2: Color(red: 0.992, green: 0.792, blue: 0.243)
        case .n1: Color(red: 0.973, green: 0.443, blue: 0.400)
        case nil: .white.opacity(0.8)
        }
    }
}

/// "Open Verb Table to load verbs" and the like, shown until the first sync.
/// Inline (above the clock) can only draw plain text.
struct WidgetEmptyState: View {
    let message: String
    var isHome: Bool
    var isInline: Bool = false

    var body: some View {
        if isInline {
            Text(message)
        } else {
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(isHome ? .white : .primary)
        }
    }
}
