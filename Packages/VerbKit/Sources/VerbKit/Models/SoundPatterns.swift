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
    /// What a counter changes beyond the class pattern (年 at 4, 階 at 3 and 何), in data order.
    public let exceptions: [SoundPatternException]

    public var id: String { sound }
    public var isIrregular: Bool { sound == "irregular" }
}

public struct SoundPatternException: Hashable, Sendable {
    public let counter: Counter
    public let numbers: [CounterNumber]
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
        let exceptions = cls.sound == "irregular" ? [] : members.compactMap { member -> SoundPatternException? in
            let extra = CounterNumber.allCases.filter { member.isChanged($0) && !marked.contains($0) }
            return extra.isEmpty ? nil : SoundPatternException(counter: member, numbers: extra)
        }
        return SoundPatternRow(
            sound: cls.sound, title: cls.title, summary: cls.summary, counters: members, marked: marked, exceptions: exceptions
        )
    }
}

/// The part of the reading that the rows marking `number` share, such as ろっ for 6. Only returned when
/// at least two rows mark it and the shared part ends in a small っ (a shared さん says nothing).
public func soundPatternStem(for number: CounterNumber, in rows: [SoundPatternRow]) -> String? {
    sharedSmallTsuStem(of: rows.filter { !$0.isIrregular && $0.marked.contains(number) }
        .compactMap { $0.counters.first?.readings(for: number).first })
}

/// The longest common prefix of `readings`, only when there are at least two and it ends in っ.
private func sharedSmallTsuStem(of readings: [String]) -> String? {
    guard readings.count >= 2, var prefix = readings.first.map(Array.init) else { return nil }
    for reading in readings.dropFirst() {
        let other = Array(reading)
        prefix = Array(zip(prefix, other).prefix { $0 == $1 }.map(\.0))
    }
    guard prefix.last == "っ" else { return nil }
    return String(prefix)
}

// MARK: - The table: numbers down, the counter's first sound across

/// A column of the Sound patterns table, named for the counter's first sound.
public enum SoundColumnID: String, CaseIterable, Sendable {
    case k, s, h, other

    public var title: String {
        switch self {
        case .k: "か行"
        case .s: "さ行"
        case .h: "は行"
        case .other: "other"
        }
    }

    /// The counter whose readings the column shows when it is visible.
    fileprivate var preferredSample: String {
        switch self {
        case .k: "ko"
        case .s: "satsu"
        case .h: "hon"
        case .other: "mai"
        }
    }

    /// The column for a `sound` class, or nil for `irregular` (and anything unknown).
    fileprivate init?(sound: String) {
        switch sound {
        case "k": self = .k
        case "s": self = .s
        case "h-b", "h-p": self = .h
        case "plain": self = .other
        default: return nil
        }
    }
}

public struct SoundPatternColumn: Identifiable, Sendable {
    public let id: SoundColumnID
    public let counters: [Counter]
    /// The counter whose readings fill the column's cells.
    public let sample: Counter
}

/// The Sound patterns screen's data. Reads only `sound`, `readings` and `changed`.
public struct SoundPatternTable: Sendable {
    public let columns: [SoundPatternColumn]
    /// The numbers that ever change: 1, 3, 6, 8 and 10.
    public let numbers: [CounterNumber]
    /// Counters with no pattern to show (人, つ, 時, 日).
    public let irregular: [Counter]
    /// What a counter changes beyond its column's pattern (分 at 4), in data order.
    public let exceptions: [SoundPatternException]

    public func cell(_ number: CounterNumber, _ column: SoundColumnID) -> (reading: String, changed: Bool)? {
        guard let sample = columns.first(where: { $0.id == column })?.sample,
              let reading = sample.readings(for: number).first else { return nil }
        return (reading, sample.isChanged(number))
    }

    /// One sentence about `number`, built from the data: the columns that change it and, when they share
    /// a stem ending in っ, the stem.
    public func sentence(for number: CounterNumber) -> String {
        let label = number == .what ? "何" : number.key
        let changing = columns.filter { $0.sample.isChanged(number) }
        guard !changing.isEmpty else { return "\(label) never changes sound in these columns." }
        let names = changing.map(\.id.title)
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        if let stem = sharedSmallTsuStem(of: changing.compactMap { $0.sample.readings(for: number).first }) {
            return "\(label) → \(stem) in \(list)"
        }
        return "\(label) changes in \(list)"
    }
}

public func soundPatternTable(from counters: [Counter]) -> SoundPatternTable {
    let numbers: [CounterNumber] = [.n(1), .n(3), .n(6), .n(8), .n(10)]
    var columns: [SoundPatternColumn] = []
    var exceptions: [SoundPatternException] = []
    for id in SoundColumnID.allCases {
        let members = counters.filter { SoundColumnID(sound: $0.sound) == id }
        guard let first = members.first else { continue }
        let sample = members.first { $0.id == id.preferredSample } ?? first
        columns.append(SoundPatternColumn(id: id, counters: members, sample: sample))
        let marked = CounterNumber.allCases.filter { number in members.allSatisfy { $0.isChanged(number) } }
        for member in members {
            let extra = CounterNumber.allCases.filter { member.isChanged($0) && !marked.contains($0) }
            if !extra.isEmpty { exceptions.append(SoundPatternException(counter: member, numbers: extra)) }
        }
    }
    return SoundPatternTable(
        columns: columns, numbers: numbers, irregular: counters.filter { $0.sound == "irregular" }, exceptions: exceptions
    )
}
