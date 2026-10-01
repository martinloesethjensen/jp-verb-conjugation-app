import SwiftUI
import VerbKit
import WidgetKit

struct VerbWidgetView: View {
    let entry: VerbEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let verb = entry.verb {
            content(for: verb)
                .widgetURL(Route.verb(verb.id).url)
                .containerBackground(for: .widget) { background }
        } else {
            empty
                .containerBackground(for: .widget) { background }
        }
    }

    private static let navy = Color(red: 0.043, green: 0.063, blue: 0.149)

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

    @ViewBuilder private func content(for verb: Verb) -> some View {
        if family == .systemMedium {
            HStack(alignment: .top, spacing: 14) {
                small(verb)
                formsGrid(verb)
            }
        } else if isRectangular {
            VStack(alignment: .leading, spacing: 1) {
                Text(verb.kanji ?? verb.dict).font(.headline).bold()
                Text(verb.meaning).font(.caption).lineLimit(1)
                Text(verb.forms.masuPos).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if isInline {
            Text("\(verb.dict) · \(verb.meaning)")
        } else {
            small(verb)
        }
    }

    private func small(_ verb: Verb) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verb.kanji ?? verb.dict)
                .font(.title.weight(.heavy))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(verb.teGroup?.accentColor ?? verb.type.accentColor)
            if verb.kanji != nil {
                Text(verb.dict).font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            Text(verb.meaning).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            Spacer(minLength: 0)
            Text(verb.forms.masuPos).font(.callout).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func formsGrid(_ verb: Verb) -> some View {
        let cells: [(String, String)] = [
            ("て-form", verb.forms.te),
            ("Past", verb.forms.shortPast),
            ("Negative", verb.forms.shortNeg),
            ("Potential", verb.forms.potential ?? ""),
        ].filter { !$0.1.isEmpty }
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 8) {
            ForEach(cells, id: \.0) { cell in
                VStack(alignment: .leading, spacing: 0) {
                    Text(cell.0).font(.caption2).foregroundStyle(.white.opacity(0.6))
                    Text(cell.1).font(.callout).foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#if DEBUG
private let sampleVerb = Verb(
    type: .ru, label: "Ichidan", dict: "たべる", kanji: "食べる", meaning: "to eat", description: "",
    forms: VerbForms(
        masuPos: "たべます", masuNeg: "たべません", masuPast: "たべました", masuPastNeg: "たべませんでした",
        te: "たべて", shortPos: "たべる", shortNeg: "たべない", shortPast: "たべた", shortPastNeg: "たべなかった",
        potential: "たべられる"),
    examples: [])

private let sampleProvider = VerbEntry(date: .now, verb: sampleVerb)

#Preview("Small", as: .systemSmall) {
    VerbTableWidget()
} timeline: {
    sampleProvider
}

#Preview("Medium", as: .systemMedium) {
    VerbTableWidget()
} timeline: {
    sampleProvider
}

#if os(iOS)
#Preview("Lock Screen", as: .accessoryRectangular) {
    VerbTableWidget()
} timeline: {
    sampleProvider
}
#endif
#endif
