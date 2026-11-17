import SwiftUI
import VerbKit
import WidgetKit

struct CounterWidgetView: View {
    @Environment(\.palette) private var palette
    let entry: CounterEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// The board's counter widget is ink with paper text; Clear and Tinted keep only the type.
    private var inverted: Bool { renderingMode == .fullColor }
    private var face: Color { inverted ? palette.paper : palette.ink }
    private var faint: Color { inverted ? palette.paper.opacity(0.7) : palette.muted }

    var body: some View {
        Group {
            if let counter = entry.counter {
                content(counter).widgetURL(Route.counter(counter.id).url)
            } else {
                WidgetEmptyState(message: "Open Verb Table to load counters", isHome: true)
            }
        }
        .containerBackground(for: .widget) {
            if inverted { palette.ink } else { WidgetTheme.background(isHome: true, palette: palette) }
        }
    }

    @ViewBuilder private func content(_ counter: Counter) -> some View {
        if family == .systemMedium {
            HStack(alignment: .top, spacing: 12) {
                header(counter).frame(width: 96, alignment: .leading)
                grid(counter)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                header(counter)
                Spacer(minLength: 0)
                Text(changeLine(counter)).font(.caption2).foregroundStyle(faint).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ counter: Counter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetCaption(text: "Counter", color: faint)
            WidgetRuby(text: counter.counter, reading: counter.reading, size: 38, color: face, readingColor: faint)
            Text(counter.meaning).font(.subheadline.weight(.semibold)).foregroundStyle(face).lineLimit(2)
        }
    }

    /// "Changes at 1 · 3 · 6 · 8 · 10 · 何", straight from the counter's `changed` list.
    private func changeLine(_ counter: Counter) -> String {
        let changed = CounterNumber.allCases.filter(counter.isChanged).map { $0 == .what ? "何" : $0.key }
        if !changed.isEmpty { return "Changes at " + changed.joined(separator: " · ") }
        return counter.sound == "irregular" ? "Irregular: learn each reading" : "No sound changes"
    }

    private func grid(_ counter: Counter) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
            ForEach(CounterNumber.allCases) { number in
                let changed = counter.isChanged(number)
                VStack(spacing: 0) {
                    Text(counter.written(number)).font(.system(size: 8)).foregroundStyle(faint)
                    Text(counter.readings(for: number).first ?? "")
                        .font(.system(size: 11, weight: changed ? .bold : .regular))
                        .foregroundStyle(face).minimumScaleFactor(0.6).lineLimit(1)
                        // A changed reading is underlined, as in the app (never colour alone).
                        .underline(changed, color: face)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(counter.written(number)), \(counter.readings(for: number).first ?? "")\(changed ? ", sound changes" : "")")
                .frame(maxWidth: .infinity, minHeight: 30)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(faint.opacity(0.4), lineWidth: 1))
            }
        }
    }
}
