import SwiftUI
import VerbKit
import WidgetKit

struct GrammarWidgetView: View {
    @Environment(\.palette) private var palette
    let entry: GrammarEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let point = entry.point {
            content(for: point)
                .widgetURL(Route.grammar(point.id).url)
                .containerBackground(for: .widget) { background }
        } else {
            empty
                .containerBackground(for: .widget) { background }
        }
    }

    /// Paper, ruled like the app's example cards, on the home screen (the board's grammar widget).
    @ViewBuilder private var background: some View {
        ZStack {
            WidgetTheme.background(isHome: isHome, palette: palette)
            if isHome { WidgetRuled(color: palette.rule) }
        }
    }

    /// The example with the lesson's pattern underlined.
    private func example(_ text: String, point: GrammarPoint) -> Text {
        var attributed = AttributedString(text)
        if let range = GrammarHighlight.range(in: text, patterns: GrammarHighlight.patterns(of: point)) {
            let chars = Array(text)
            let start = attributed.index(attributed.startIndex, offsetByCharacters: range.lowerBound)
            let end = attributed.index(start, offsetByCharacters: min(range.count, chars.count - range.lowerBound))
            attributed[start..<end].underlineStyle = .single
            attributed[start..<end].inlinePresentationIntent = .stronglyEmphasized
        }
        return Text(attributed)
    }

    @ViewBuilder private var empty: some View {
        WidgetEmptyState(message: "Open Verb Table to load verbs", isHome: isHome, isInline: isInline)
    }

    private var isHome: Bool { family == .systemSmall || family == .systemMedium }

    #if os(iOS)
    private var isInline: Bool { family == .accessoryInline }
    private var isRectangular: Bool { family == .accessoryRectangular }
    #else
    private var isInline: Bool { false }
    private var isRectangular: Bool { false }
    #endif

    /// GRAMMAR, with the level as an outlined pill.
    private func header(_ point: GrammarPoint) -> some View {
        HStack {
            WidgetCaption(text: "Grammar", color: palette.muted)
            Spacer(minLength: 4)
            if let level = point.jlpt?.rawValue {
                Text(level)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 6)
                    .background(palette.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(palette.rule, lineWidth: 1))
            }
        }
    }

    @ViewBuilder private func content(for point: GrammarPoint) -> some View {
        if family == .systemMedium {
            VStack(alignment: .leading, spacing: 6) {
                header(point)
                Text(point.title).font(.widgetHeadword(24)).foregroundStyle(palette.ink).lineLimit(1).minimumScaleFactor(0.6)
                if let first = point.usages.first?.examples.first {
                    example(first.jp, point: point)
                        .font(.widgetSentence(17)).foregroundStyle(palette.ink).lineLimit(1).minimumScaleFactor(0.7)
                    Text(first.en).font(.caption).foregroundStyle(palette.muted).lineLimit(1)
                } else {
                    Text(point.summary).font(.caption).foregroundStyle(palette.ink).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if isRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text(point.title).font(.headline).bold().lineLimit(1)
                Text(point.summary).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isInline {
            Text(point.title)
        } else {
            small(point)
        }
    }

    private func small(_ point: GrammarPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(point)
            Text(point.title)
                .font(.widgetHeadword(22))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(palette.ink)
            Text(point.summary).font(.caption).foregroundStyle(palette.ink).lineLimit(3)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension GrammarPoint {
    /// Shown in the widget gallery and as the placeholder before real data loads.
    static let sample = GrammarPoint(
        id: "n-desu", title: "〜んです", summary: "Explains or asks for the reason behind something.",
        jlpt: .n4,
        usages: [GrammarUsage(heading: "Explaining", explanation: "", examples: [GrammarExample(jp: "どうしたんですか。", en: "What happened?")])],
        attachment: [], conjugations: [], pitfalls: [], related: [])
}

#if DEBUG
private let sampleEntry = GrammarEntry(date: .now, point: .sample)

#Preview("Small", as: .systemSmall) {
    GrammarRuleWidget()
} timeline: {
    sampleEntry
}

#Preview("Medium", as: .systemMedium) {
    GrammarRuleWidget()
} timeline: {
    sampleEntry
}

#if os(iOS)
#Preview("Lock Screen", as: .accessoryRectangular) {
    GrammarRuleWidget()
} timeline: {
    sampleEntry
}
#endif
#endif
