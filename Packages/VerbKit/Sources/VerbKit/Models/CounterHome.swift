/// One counter under one home-list heading. A counter in two sections has two rows, so the row id
/// includes the section.
public struct CounterHomeRow: Identifiable, Hashable, Sendable {
    public let section: String
    public let counter: Counter

    public var id: String { "\(section)/\(counter.id)" }
}

public struct CounterHomeSection: Identifiable, Hashable, Sendable {
    public let section: CounterSection
    public let rows: [CounterHomeRow]

    public var id: String { section.id }
    /// A single counter has nothing to compare.
    public var canCompare: Bool { rows.count > 1 }
}

/// The home list: `sections` in order, each with its visible counters in order. Ids missing from
/// `visible` (hidden by the level settings, or unknown) are skipped, and a section left empty is dropped.
public func homeSections(_ sections: [CounterSection], counters visible: [Counter]) -> [CounterHomeSection] {
    let byID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return sections.compactMap { section in
        let rows = section.counters.compactMap { id in
            byID[id].map { CounterHomeRow(section: section.id, counter: $0) }
        }
        return rows.isEmpty ? nil : CounterHomeSection(section: section, rows: rows)
    }
}
