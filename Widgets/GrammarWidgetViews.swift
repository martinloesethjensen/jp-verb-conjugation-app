import SwiftUI
import VerbKit
import WidgetKit

struct GrammarWidgetView: View {
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

    private static let navy = Color(red: 0.043, green: 0.063, blue: 0.149)
    private static let beginner = Color(red: 0.176, green: 0.831, blue: 0.749)
    private static let intermediate = Color(red: 0.655, green: 0.545, blue: 0.980)

    @ViewBuilder private var background: some View {
        if isHome {
            LinearGradient(colors: [Self.navy, .black], startPoint: .top, endPoint: .bottom)
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var empty: some View {
        let text = Text("Open Verb Table to load verbs")
        if isInline {
            text
        } else {
            text.font(.caption).multilineTextAlignment(.center)
                .foregroundStyle(isHome ? .white : .primary)
        }
    }

    private var isHome: Bool { family == .systemSmall || family == .systemMedium }

    #if os(iOS)
    private var isInline: Bool { family == .accessoryInline }
    private var isRectangular: Bool { family == .accessoryRectangular }
    #else
    private var isInline: Bool { false }
    private var isRectangular: Bool { false }
    #endif

    private func accent(_ level: JLPTLevel?) -> Color {
        guard let level else { return Self.beginner }
        return level <= .n4 ? Self.beginner : Self.intermediate
    }

    private func levelName(_ level: JLPTLevel?) -> String {
        level?.rawValue ?? ""
    }

    @ViewBuilder private func content(for point: GrammarPoint) -> some View {
        if family == .systemMedium {
            VStack(alignment: .leading, spacing: 6) {
                small(point)
                if let example = point.usages.first?.examples.first {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(example.jp).font(.callout).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                        Text(example.en).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
            }
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
        VStack(alignment: .leading, spacing: 2) {
            Text(point.title)
                .font(.title3.weight(.heavy))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(accent(point.jlpt))
            Text(levelName(point.jlpt)).font(.caption2).foregroundStyle(.white.opacity(0.6))
            Text(point.summary).font(.caption).foregroundStyle(.white.opacity(0.85)).lineLimit(3)
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
