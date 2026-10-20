import SwiftUI
import VerbKit
import WidgetKit

struct CounterWidgetView: View {
    let entry: CounterEntry
    @Environment(\.widgetFamily) private var family

    private static let navy = Color(red: 0.043, green: 0.063, blue: 0.149)
    private static let accent = Color(red: 0.992, green: 0.62, blue: 0.243)

    var body: some View {
        Group {
            if let counter = entry.counter {
                content(counter).widgetURL(Route.counter(counter.id).url)
            } else {
                Text("Open Verb Table to load counters")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.white)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Self.navy, .black], startPoint: .top, endPoint: .bottom)
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
                Text(changeLine(counter)).font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(_ counter: Counter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(counter.counter).font(.system(size: 44, weight: .bold)).foregroundStyle(.white).minimumScaleFactor(0.6)
            Text(counter.reading).font(.headline).foregroundStyle(Self.accent)
            Text(counter.meaning).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
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
                    Text(counter.written(number)).font(.system(size: 8)).foregroundStyle(.white.opacity(0.55))
                    Text(counter.readings(for: number).first ?? "").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(counter.written(number)), \(counter.readings(for: number).first ?? "")\(changed ? ", sound changes" : "")")
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(changed ? Self.accent.opacity(0.28) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topTrailing) {
                    if changed { Circle().fill(Self.accent).frame(width: 4, height: 4).padding(3) }
                }
            }
        }
    }
}
