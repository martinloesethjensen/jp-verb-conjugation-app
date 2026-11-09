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

/// A small paper capsule for a tag: ink text on `card`, a map-pin glyph and an ink outline for a
/// dialect tag, a number sign, a `rule` outline and a dot in the tag's colour for a custom one. The
/// glyph tells the two kinds apart without colour; the colour never carries the text.
struct TagPill: View {
    let text: String
    let color: Color
    var systemImage: String?
    var isDialect = false

    @Environment(\.palette) private var palette

    init(_ text: String, color: Color, systemImage: String? = nil) {
        self.text = text
        self.color = color
        self.systemImage = systemImage
    }

    init(_ tag: DialectTagValue) {
        self.init(tag.name, color: .accentColor, systemImage: "mappin.and.ellipse")
        isDialect = true
    }

    init(_ tag: CustomTagValue) {
        self.init(tag.name, color: tag.color.color, systemImage: "number")
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true)
            }
            if !isDialect {
                Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
            }
            Text(text).font(.caption.weight(.medium)).foregroundStyle(palette.ink).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(palette.card, in: Capsule())
        .overlay(Capsule().strokeBorder(isDialect ? palette.ink : palette.rule, lineWidth: 1))
    }
}
