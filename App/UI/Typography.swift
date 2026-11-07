import SwiftUI

extension Font {
    /// Hiragino Mincho (ships with iOS and macOS) for Japanese headwords, at the default size of
    /// `style` times `scale`, and scaling with Dynamic Type like it.
    static func headword(_ style: Font.TextStyle, scale: CGFloat = 1) -> Font {
        .custom("HiraMinProN-W6", size: defaultSize(of: style) * scale, relativeTo: style)
    }

    /// The lighter Hiragino Mincho for Japanese sentences and phrases (examples, common phrases),
    /// at the default size of `style` and scaling with Dynamic Type like it.
    static func sentence(_ style: Font.TextStyle) -> Font {
        .custom("HiraMinProN-W3", size: defaultSize(of: style), relativeTo: style)
    }

    private static func defaultSize(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}
