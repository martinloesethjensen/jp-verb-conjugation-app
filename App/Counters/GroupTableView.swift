import SwiftUI
import VerbKit

/// A group's lookup table: numbers 1 to 10 and 何 down the rows (a picker above switches to 11 to 20, the
/// round tens and 100 and up when some counter has them), the group's counters across the
/// columns. Up to three counters fill the width; more scroll sideways with the number column
/// pinned, kept aligned by giving every row the same (Dynamic Type scaled) height. At accessibility
/// text sizes even three columns scroll, so text wraps instead of truncating.
struct GroupTableView: View {
    let title: String
    let summary: String?
    private let memberRefs: [CounterGroupMember]
    @Environment(CountersStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var narrowNumberWidth: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var wideNumberWidth: CGFloat = 54
    @State private var range: CounterRange = .core
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 108

    init(group: CounterGroup) {
        title = group.title
        summary = group.summary
        memberRefs = group.members
    }

    /// A home-list section: no summary, and headers say what each counter counts.
    init(section: CounterSection) {
        title = section.title
        summary = nil
        memberRefs = section.counters.map { CounterGroupMember(counter: $0) }
    }

    private var members: [(counter: Counter, note: String?)] {
        let visible = store.counters.visible(in: LevelSettings(rawValue: hiddenLevelsRaw))
        return CounterGroup(id: "", title: title, symbol: "", summary: summary ?? "", members: memberRefs)
            .counters(in: visible)
            .map { ($0.counter, $0.note ?? $0.counter.meaning) }
    }

    /// Between rows. Every row has the same height, so the pinned number column stays aligned.
    private static let rowSpacing: CGFloat = 3

    private static func label(_ number: CounterNumber) -> String {
        number == .what ? "何" : number.key
    }

    /// The range being shown: the picked one, or the core one when the picked one has no rows here.
    private func shown(_ ranges: [CounterRange]) -> CounterRange {
        ranges.contains(range) ? range : .core
    }

    var body: some View {
        let members = members
        let counters = members.map(\.counter)
        let ranges = CounterRange.available(for: counters)
        let shown = shown(ranges)
        let numbers = shown.numbers(for: counters)
        // Readings above 10 are longer, so they wrap to two lines in a three-column table.
        let height = shown.isExtended ? rowHeight * 1.7 : rowHeight
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if ranges.count > 1 { rangePicker(ranges, shown: shown) }
                HStack(alignment: .top, spacing: 8) {
                    numberColumn(numbers, rowHeight: height)
                    if members.count <= 3 && !typeSize.isAccessibilitySize {
                        counterGrid(members, numbers: numbers, rowHeight: height, fill: true)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            counterGrid(members, numbers: numbers, rowHeight: height, fill: false)
                        }
                    }
                }
                changes(members)
            }
            .padding(16)
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Speak readings", systemImage: "speaker.wave.2") {
                    ForEach(members, id: \.counter.id) { member in
                        Button("\(member.counter.counter): \(shown.title)") {
                            speakColumn(member.counter, numbers: numbers)
                        }
                    }
                }
            }
        }
    }

    /// 1–10, 11–20, 30–90, 100+, with the "unreviewed" mark on every range above 10.
    private func rangePicker(_ ranges: [CounterRange], shown: CounterRange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Numbers", selection: Binding(get: { shown }, set: { range = $0 })) {
                ForEach(ranges, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if shown.isExtended { UnreviewedLabel() }
        }
    }

    private func numberColumn(_ numbers: [CounterNumber], rowHeight: CGFloat) -> some View {
        let width = numbers.contains { $0.key.count > 3 } ? wideNumberWidth : narrowNumberWidth
        return VStack(spacing: Self.rowSpacing) {
            Color.clear.frame(width: width, height: headerHeight)
            ForEach(numbers) { number in
                Text(Self.label(number))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: width, height: rowHeight)
            }
        }
    }

    private func counterGrid(_ members: [(counter: Counter, note: String?)], numbers: [CounterNumber], rowHeight: CGFloat, fill: Bool) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: Self.rowSpacing) {
            GridRow {
                ForEach(members, id: \.counter.id) { member in
                    header(member.counter, note: member.note)
                        .frame(width: fill ? nil : columnWidth, height: headerHeight)
                        .frame(maxWidth: fill ? .infinity : nil)
                }
            }
            ForEach(numbers) { number in
                GridRow {
                    ForEach(members, id: \.counter.id) { member in
                        cell(member.counter, number)
                            .frame(width: fill ? nil : columnWidth, height: rowHeight)
                            .frame(maxWidth: fill ? .infinity : nil)
                    }
                }
            }
        }
    }

    /// A reading, or a dash for a counter that has no reading at this number (分 stops at 59).
    @ViewBuilder private func cell(_ counter: Counter, _ number: CounterNumber) -> some View {
        if counter.readings(for: number).isEmpty {
            Text("—")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("\(counter.counter) has no reading for \(number.key)")
        } else {
            ReadingCell(counter: counter, number: number)
        }
    }

    /// The counter, its reading and what it covers in this group. Opens the counter's page.
    private func header(_ counter: Counter, note: String?) -> some View {
        NavigationLink(value: CounterDestination.counter(counter, focus: nil)) {
            VStack(spacing: 2) {
                Text(counter.counter)
                    .font(.title2.weight(.bold))
                HStack(spacing: 4) {
                    Text(counter.reading)
                    if counter.sound == "irregular" {
                        Text("irregular")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .glassEffect(in: Capsule())
                    }
                }
                .font(.caption)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(counter.counter), \(counter.reading)\(counter.sound == "irregular" ? ", irregular" : "")\(note.map { ", \($0)" } ?? "")"
        )
        .accessibilityHint("Opens the counter")
    }

    /// One line per counter, built from its data: which numbers change, or why none are marked.
    private func changes(_ members: [(counter: Counter, note: String?)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(members, id: \.counter.id) { member in
                Text("\(member.counter.counter): \(changeSummary(member.counter))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func changeSummary(_ counter: Counter) -> String {
        if counter.sound == "irregular" { return "irregular, learn each reading" }
        let changed = CounterNumber.allCases.filter(counter.isChanged).map(Self.label)
        return changed.isEmpty ? "no sound changes" : changed.joined(separator: ", ")
    }

    private func speakColumn(_ counter: Counter, numbers: [CounterNumber]) {
        let text = numbers.compactMap { counter.readings(for: $0).first }.joined(separator: "、")
        Speaker.shared.speak(text, restart: true)
    }
}
