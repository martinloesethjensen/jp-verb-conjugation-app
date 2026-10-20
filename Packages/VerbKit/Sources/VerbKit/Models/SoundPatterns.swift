/// One sound class on the Sound patterns screen: its counters and the numbers it changes.
public struct SoundPatternRow: Identifiable, Hashable, Sendable {
    /// The class id (`plain`, `k`, `s`, `h-b`, `h-p`, `irregular`).
    public let sound: String
    public let title: String
    public let summary: String
    /// Members in data order.
    public let counters: [Counter]
    /// Numbers every member changes. A single counter's exception (年 at 4) is not the class's pattern.
    public let marked: [CounterNumber]

    public var id: String { sound }
    public var isIrregular: Bool { sound == "irregular" }
}

private let soundClasses: [(sound: String, title: String, summary: String)] = [
    ("plain", "Plain", "The counter's sound never changes."),
    ("k", "K sounds", "か and こ turn into っか and っこ."),
    ("s", "S sounds", "さ turns into っさ at 1, 8 and 10."),
    ("h-b", "H sounds (b/p)", "は-row sounds turn into ぱ or ば."),
    ("h-p", "H sounds (p)", "は-row sounds turn into ぱ everywhere they can."),
    ("irregular", "Irregular", "Learn each reading."),
]

/// One row per class that has a counter, in a fixed order. Reads only `changed`, never derives a reading.
public func soundPatternRows(from counters: [Counter]) -> [SoundPatternRow] {
    soundClasses.compactMap { cls in
        let members = counters.filter { $0.sound == cls.sound }
        guard !members.isEmpty else { return nil }
        let marked = cls.sound == "irregular"
            ? []
            : CounterNumber.allCases.filter { number in members.allSatisfy { $0.isChanged(number) } }
        return SoundPatternRow(sound: cls.sound, title: cls.title, summary: cls.summary, counters: members, marked: marked)
    }
}

/// The part of the reading that the rows marking `number` share, such as ろっ for 6. Only returned when
/// at least two rows mark it and the shared part ends in a small っ (a shared さん says nothing).
public func soundPatternStem(for number: CounterNumber, in rows: [SoundPatternRow]) -> String? {
    let readings = rows.filter { !$0.isIrregular && $0.marked.contains(number) }
        .compactMap { $0.counters.first?.readings(for: number).first }
    guard readings.count >= 2, var prefix = readings.first.map(Array.init) else { return nil }
    for reading in readings.dropFirst() {
        let other = Array(reading)
        prefix = Array(zip(prefix, other).prefix { $0 == $1 }.map(\.0))
    }
    guard prefix.last == "っ" else { return nil }
    return String(prefix)
}
