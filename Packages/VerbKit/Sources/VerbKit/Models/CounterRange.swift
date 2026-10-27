import Foundation

/// A band of numbers on a Compare table: the core 1 to 10 and 何, 11 to 20, the round tens 30 to 90, and 100
/// and above. 21 to 29 and the other in-between numbers are on the counter's own page.
public enum CounterRange: CaseIterable, Hashable, Sendable {
    case core, elevenToTwenty, tens, hundredsUp

    public var title: String {
        switch self {
        case .core: "1–10"
        case .elevenToTwenty: "11–20"
        case .tens: "30–90"
        case .hundredsUp: "100+"
        }
    }

    /// True for every range but the core one: the numbers the data generates, shown as unreviewed.
    public var isExtended: Bool { self != .core }

    /// The rows, in order. The core range is always all eleven, as tables show today; the others only the
    /// numbers at least one of `counters` has readings for.
    public func numbers(for counters: [Counter]) -> [CounterNumber] {
        if self == .core { return CounterNumber.allCases }
        let candidates: [CounterNumber] = switch self {
        case .core: []
        case .elevenToTwenty: (11...20).map(CounterNumber.n)
        case .tens: stride(from: 30, through: 90, by: 10).map(CounterNumber.n)
        case .hundredsUp: Set(counters.flatMap(\.extendedNumbers))
            .filter { if case .n(let value) = $0 { value >= 100 } else { false } }
            .sorted { $0.sortValue < $1.sortValue }
        }
        return candidates.filter { number in counters.contains { !$0.readings(for: number).isEmpty } }
    }

    /// The ranges with at least one row, in order.
    public static func available(for counters: [Counter]) -> [CounterRange] {
        allCases.filter { !$0.numbers(for: counters).isEmpty }
    }
}

extension CounterNumber {
    /// 1 to 10000 for a number, `Int.max` for 何: a stable order for sorting.
    var sortValue: Int {
        if case .n(let value) = self { value } else { Int.max }
    }
}
