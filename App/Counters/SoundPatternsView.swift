import SwiftUI
import VerbKit

/// Which numbers change sound in each class. Tapping a number rings its column in every card and
/// says which classes change it and, where they share one, the stem (6 → ろっ).
struct SoundPatternsView: View {
    @Environment(CountersStore.self) private var store
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: CounterNumber?

    private var rows: [SoundPatternRow] {
        soundPatternRows(from: store.counters.visible(in: LevelSettings(rawValue: hiddenLevelsRaw)))
    }

    private func label(_ number: CounterNumber) -> String { number == .what ? "何" : number.key }

    private func caption(_ number: CounterNumber, in rows: [SoundPatternRow]) -> String {
        let changing = rows.filter { $0.marked.contains(number) }.map(\.title)
        guard !changing.isEmpty else { return "\(label(number)) never changes sound in these classes." }
        let list = changing.count == 1 ? changing[0] : changing.dropLast().joined(separator: ", ") + " and " + changing[changing.count - 1]
        if let stem = soundPatternStem(for: number, in: rows) {
            return "\(label(number)) → \(stem) in \(list)"
        }
        return "\(label(number)) changes in \(list)"
    }

    var body: some View {
        let rows = rows
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No Counters", systemImage: "waveform")
                } description: {
                    Text("Counters hidden by your level settings have no patterns to show.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(selected.map { caption($0, in: rows) } ?? "Tap a number to compare it across classes.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(selected.map { caption($0, in: rows) } ?? "Tap a number to compare it across classes.")
                        ForEach(rows) { row in card(row) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Sound patterns")
    }

    private func card(_ row: SoundPatternRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title).font(.headline)
            Text(row.summary).font(.footnote).foregroundStyle(.secondary)
            Text(row.counters.map(\.counter).joined(separator: " · ")).font(.title3).foregroundStyle(.secondary)
            if row.isIrregular {
                Text("Irregular: learn each reading").font(.footnote).foregroundStyle(.secondary)
            } else {
                strip(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func strip(_ row: SoundPatternRow) -> some View {
        let cells = HStack(spacing: 4) {
            ForEach(CounterNumber.allCases) { number in cell(number, row: row) }
        }
        if typeSize.isAccessibilitySize {
            ScrollView(.horizontal, showsIndicators: false) { cells }
        } else {
            cells
        }
    }

    private func cell(_ number: CounterNumber, row: SoundPatternRow) -> some View {
        let marked = row.marked.contains(number)
        return Button {
            selected = selected == number ? nil : number
        } label: {
            Text(label(number))
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .frame(minWidth: typeSize.isAccessibilitySize ? 56 : 0)
                .background(marked ? Color.orange.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if marked {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.orange)
                            .padding(3).accessibilityHidden(true)
                    }
                }
                .overlay {
                    if selected == number {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label(number)), \(marked ? "sound changes" : "no change")")
    }
}
