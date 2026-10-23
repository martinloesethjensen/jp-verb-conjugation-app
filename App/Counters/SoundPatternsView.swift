import SwiftUI
import VerbKit

/// Why counters change sound, read by the counter's first sound: numbers 1, 3, 6, 8 and 10 down the
/// side, か行, さ行, は行 and "other" across, each cell a real reading from one counter. Tapping a number
/// says what happens to it and which counters it affects; tapping a column header lists that column's
/// counters. Tapping a cell speaks it. Irregular counters and one-off exceptions sit below.
struct SoundPatternsView: View {
    @Environment(CountersStore.self) private var store
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var numberWidth: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 92
    @State private var selected: CounterNumber = .n(6)
    @State private var selectedColumn: SoundColumnID?

    private var table: SoundPatternTable {
        soundPatternTable(from: store.counters.visible(in: LevelSettings(rawValue: hiddenLevelsRaw)))
    }

    private func label(_ number: CounterNumber) -> String { number == .what ? "何" : number.key }

    var body: some View {
        let table = table
        Group {
            if table.columns.isEmpty && table.irregular.isEmpty {
                ContentUnavailableView {
                    Label("No Counters", systemImage: "waveform")
                } description: {
                    Text("Counters hidden by your level settings have no patterns to show.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Find the counter's first sound, then read across. Tap a number or a column.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        tableView(table)
                        explanation(table)
                        exceptions(table)
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Why counters change sound")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: table

    @ViewBuilder private func tableView(_ table: SoundPatternTable) -> some View {
        let grid = grid(table)
        if typeSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) { grid }
        } else {
            grid
        }
    }

    private func grid(_ table: SoundPatternTable) -> some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: numberWidth, height: 1)
                ForEach(table.columns) { column in header(column) }
            }
            ForEach(table.numbers) { number in
                GridRow {
                    numberButton(number)
                    ForEach(table.columns) { column in cell(table, number, column.id) }
                }
            }
        }
    }

    private func header(_ column: SoundPatternColumn) -> some View {
        let on = selectedColumn == column.id
        return Button {
            selectedColumn = on ? nil : column.id
        } label: {
            VStack(spacing: 2) {
                Text(column.id.title).font(.subheadline.weight(.semibold))
                Text(column.counters.map(\.counter).uniqued().joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .frame(minWidth: typeSize.isAccessibilitySize ? columnWidth : 0)
            .overlay {
                if on { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(column.id.title), \(column.counters.map(\.counter).uniqued().joined(separator: ", "))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func numberButton(_ number: CounterNumber) -> some View {
        Button {
            selected = number
            selectedColumn = nil
        } label: {
            Text(label(number))
                .font(.headline)
                .foregroundStyle(selected == number && selectedColumn == nil ? Color.accentColor : .secondary)
                .frame(width: numberWidth, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Number \(label(number))")
        .accessibilityAddTraits(selected == number ? .isSelected : [])
    }

    @ViewBuilder private func cell(_ table: SoundPatternTable, _ number: CounterNumber, _ column: SoundColumnID) -> some View {
        if let cell = table.cell(number, column) {
            Text(cell.reading)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .frame(minWidth: typeSize.isAccessibilitySize ? columnWidth : 0)
                .background(cell.changed ? Color.orange.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if cell.changed {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.orange)
                            .padding(3).accessibilityHidden(true)
                    }
                }
                .overlay {
                    if selected == number && selectedColumn == nil {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .speakOnTap(cell.reading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(column.title), \(label(number)), \(cell.reading)\(cell.changed ? ", sound changes" : "")")
                .accessibilityHint("Speaks the reading")
                .accessibilityAddTraits(.isButton)
        } else {
            Color.clear.frame(minHeight: 44)
        }
    }

    // MARK: explanation

    private func explanation(_ table: SoundPatternTable) -> some View {
        let columns = selectedColumn.flatMap { id in table.columns.first { $0.id == id } }
        let affected = table.affected(for: selected)
        let shown = columns?.counters ?? affected
        return VStack(alignment: .leading, spacing: 8) {
            Text(columns.map { "\($0.id.title) counters" } ?? table.sentence(for: selected))
                .font(.headline)
            if !shown.isEmpty {
                ChipFlowLayout {
                    ForEach(shown.uniqued(by: \.id)) { counter in
                        NavigationLink(value: CounterDestination.counter(counter, focus: columns == nil ? selected : nil)) {
                            Text(counter.counter).font(.title3.weight(.semibold))
                                .padding(.horizontal, 12).frame(minHeight: 44)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel("\(counter.counter), \(counter.reading)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private func exceptions(_ table: SoundPatternTable) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !table.exceptions.isEmpty {
                Text("Exceptions: " + table.exceptions.map { "\($0.counter.counter) at \($0.numbers.map(label).joined(separator: ", "))" }.joined(separator: " · "))
            }
            if !table.irregular.isEmpty {
                Text(table.irregular.map(\.counter).uniqued().joined(separator: ", ") + ": learn each reading")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

private extension Sequence where Element: Hashable {
    /// Elements in order, each once (日 is two counters but one kanji).
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

private extension Sequence {
    func uniqued<Key: Hashable>(by key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
