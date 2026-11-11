import SwiftUI

/// Hiragino Mincho for widget headwords and sentences, as the app's `Font.headword`/`Font.sentence`
/// (App UI isn't in the widget target). Sized for a widget, scaling with Dynamic Type.
extension Font {
    static func widgetHeadword(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("HiraMinProN-W6", size: size, relativeTo: style)
    }

    static func widgetSentence(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("HiraMinProN-W3", size: size, relativeTo: style)
    }
}

/// A headword with its reading small above it: widgets can't use the app's furigana layout.
struct WidgetRuby: View {
    let text: String
    let reading: String?
    let size: CGFloat
    var color: Color
    var readingColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reading, reading != text {
                Text(reading)
                    .font(.system(size: size * 0.32, weight: .medium))
                    .foregroundStyle(readingColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(text)
                .font(.widgetHeadword(size))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.map { "\(text), \($0)" } ?? text)
    }
}

/// A widget caption: VERB OF THE DAY, COUNTER, GRAMMAR.
struct WidgetCaption: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// The genkō grid of the app's ruled cards, re-drawn for widgets.
struct WidgetRuled: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            var path = Path()
            var x: CGFloat = step
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = step
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 1)
        }
    }
}
