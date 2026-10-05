import SwiftUI
import VerbKit

extension CustomTagColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .gray: .gray
        }
    }

    var title: String { rawValue.capitalized }
}

/// A small capsule for a tag. Dialect tags use the accent colour and a map-pin glyph,
/// custom tags their own colour and a number sign, so the two kinds read differently
/// without relying on colour alone.
struct TagPill: View {
    let text: String
    let color: Color
    var systemImage: String?

    init(_ text: String, color: Color, systemImage: String? = nil) {
        self.text = text
        self.color = color
        self.systemImage = systemImage
    }

    init(_ tag: DialectTagValue) {
        self.init(tag.name, color: .accentColor, systemImage: "mappin.and.ellipse")
    }

    init(_ tag: CustomTagValue) {
        self.init(tag.name, color: tag.color.color, systemImage: "number")
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2).accessibilityHidden(true)
            }
            Text(text).font(.caption.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color == .yellow ? Color.primary : color)
        .background(color.opacity(0.15), in: Capsule())
    }
}
