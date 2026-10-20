import SwiftUI
import VerbKit

/// A group's lookup table: numbers 1 to 10 and 何 down the rows, the group's counters across the
/// columns. Up to three counters fill the width; more scroll sideways with the number column
/// pinned, kept aligned by giving every row the same (Dynamic Type scaled) height. At accessibility
/// text sizes even three columns scroll, so text wraps instead of truncating.
struct GroupTableView: View {
    let group: CounterGroup
    @Environment(CountersStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 92
    @ScaledMetric(relativeTo: .body) private var numberWidth: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 108

    private var members: [(counter: Counter, note: String?)] {
        group.counters(in: store.counters.visible(in: LevelSettings(rawValue: hiddenLevelsRaw)))
    }

    private static func label(_ number: CounterNumber) -> String {
        number == .what ? "何" : number.key
    }

    var body: some View {
        let members = members
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(group.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 8) {
                    numberColumn
                    if members.count <= 3 && !typeSize.isAccessibilitySize {
                        counterGrid(members, fill: true)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            counterGrid(members, fill: false)
                        }
                    }
                }
                changes(members)
            }
            .padding(16)
        }
        .navigationTitle(group.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Speak readings", systemImage: "speaker.wave.2") {
                    ForEach(members, id: \.counter.id) { member in
                        Button("\(member.counter.counter): 1 to 10") {
                            speakColumn(member.counter)
                        }
                    }
                }
            }
        }
    }

    private var numberColumn: some View {
        VStack(spacing: 8) {
            Color.clear.frame(width: numberWidth, height: headerHeight)
            ForEach(CounterNumber.allCases) { number in
                Text(Self.label(number))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: numberWidth, height: rowHeight)
            }
        }
    }

    private func counterGrid(_ members: [(counter: Counter, note: String?)], fill: Bool) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                ForEach(members, id: \.counter.id) { member in
                    header(member.counter, note: member.note)
                        .frame(width: fill ? nil : columnWidth, height: headerHeight)
                        .frame(maxWidth: fill ? .infinity : nil)
                }
            }
            ForEach(CounterNumber.allCases) { number in
                GridRow {
                    ForEach(members, id: \.counter.id) { member in
                        ReadingCell(counter: member.counter, number: number)
                            .frame(width: fill ? nil : columnWidth, height: rowHeight)
                            .frame(maxWidth: fill ? .infinity : nil)
                    }
                }
            }
        }
    }

    /// The counter, its reading and what it covers in this group. Opens the counter's page.
    private func header(_ counter: Counter, note: String?) -> some View {
        NavigationLink(value: CounterDestination.counter(counter, focus: nil)) {
            VStack(spacing: 2) {
                Text(counter.counter)
                    .font(.title2.weight(.bold))
                Text(counter.reading)
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
        .accessibilityLabel("\(counter.counter), \(counter.reading)\(note.map { ", \($0)" } ?? "")")
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

    private func speakColumn(_ counter: Counter) {
        let text = CounterNumber.allCases.compactMap { counter.readings(for: $0).first }.joined(separator: "、")
        Speaker.shared.speak(text, restart: true)
    }
}
