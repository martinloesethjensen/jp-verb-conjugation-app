import Foundation

/// How naturally a thing takes a counter: `primary` is the standard one, `acceptable` is
/// heard and correct, `casual` is a fallback (つ or 個 for anything small).
public enum CounterFit: String, Codable, Hashable, Sendable {
    case primary, acceptable, casual

    var rank: Int {
        switch self {
        case .primary: 0
        case .acceptable: 1
        case .casual: 2
        }
    }
}

/// 1…10 or 何. Numbers above 10 exist too (`isExtended`), but only as many as a counter's data holds;
/// `allCases` stays the core eleven.
public enum CounterNumber: Hashable, Sendable, CaseIterable, Identifiable {
    case n(Int)
    case what

    public static let allCases: [CounterNumber] = (1...10).map(CounterNumber.n) + [.what]

    private static let numerals = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

    public var key: String {
        switch self {
        case .n(let value): String(value)
        case .what: "what"
        }
    }

    public var id: String { key }

    /// The number as written before a counter: 三, 十五, 百, 一万, 何. Kanji numerals, as in the examples.
    public var kanji: String {
        switch self {
        case .n(let value): Self.kanji(for: value)
        case .what: "何"
        }
    }

    /// True above 10: the numbers stage 2 added, which are shown as unreviewed.
    public var isExtended: Bool {
        if case .n(let value) = self { value > 10 } else { false }
    }

    /// 1 to 10000 in kanji; digits for anything else. A leading 一 is dropped before 十, 百 and 千
    /// (十五, 百, 千) but kept before 万 (一万).
    private static func kanji(for value: Int) -> String {
        guard (1...10_000).contains(value) else { return String(value) }
        if value == 10_000 { return "一万" }
        var result = ""
        var rest = value
        for (unit, symbol) in [(1000, "千"), (100, "百"), (10, "十")] where rest >= unit {
            let count = rest / unit
            rest %= unit
            result += (count == 1 ? "" : numerals[count - 1]) + symbol
        }
        return rest > 0 ? result + numerals[rest - 1] : result
    }

    /// The number for a counters.json key ("3", "15", "10000", "what"), or nil for anything else.
    public init?(key: String) {
        if key == "what" {
            self = .what
        } else if let value = Int(key), (1...10_000).contains(value), String(value) == key {
            self = .n(value)
        } else {
            return nil
        }
    }
}

/// A plain noun a counter counts. No forms; `fit` says how standard the counter is for it.
public struct CountedThing: Codable, Hashable, Sendable {
    public var word: String
    public var kana: String
    public var meaning: String
    public var fit: CounterFit
    /// An SF Symbol name; the counter's own symbol is used when this is nil.
    public var symbol: String?

    public init(word: String, kana: String, meaning: String, fit: CounterFit, symbol: String? = nil) {
        self.word = word
        self.kana = kana
        self.meaning = meaning
        self.fit = fit
        self.symbol = symbol
    }
}

/// A grammar-style example whose `readings` win over the furigana dictionary (一日 → ついたち),
/// because one dictionary key cannot read 一日 two ways.
public struct CounterExample: Codable, Hashable, Sendable {
    public var jp: String
    public var en: String
    public var readings: [String: String]

    public init(jp: String, en: String, readings: [String: String] = [:]) {
        self.jp = jp
        self.en = en
        self.readings = readings
    }

    enum CodingKeys: String, CodingKey {
        case jp, en, readings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jp = try c.decode(String.self, forKey: .jp)
        en = try c.decode(String.self, forKey: .en)
        readings = try c.decodeIfPresent([String: String].self, forKey: .readings) ?? [:]
    }

    /// The dictionary with this example's readings layered on top, for `JapaneseText`.
    public func furigana(over dictionary: FuriganaDictionary) -> FuriganaDictionary {
        dictionary.merging(readings)
    }
}

/// A trap worth calling out on a counter's page. Like a grammar pitfall, but its examples are
/// `CounterExample`s, so a date example can read 一日 as ついたち.
public struct CounterPitfall: Codable, Hashable, Sendable {
    public var heading: String
    public var explanation: String
    public var examples: [CounterExample]
    /// The form learners actually produce, without a mark ("さんほん"); the views add the ✗.
    public var wrong: String?

    public init(heading: String, explanation: String, examples: [CounterExample] = [], wrong: String? = nil) {
        self.heading = heading
        self.explanation = explanation
        self.examples = examples
        self.wrong = wrong
    }

    enum CodingKeys: String, CodingKey {
        case heading, explanation, examples, wrong
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heading = try c.decode(String.self, forKey: .heading)
        explanation = try c.decode(String.self, forKey: .explanation)
        examples = try c.decodeIfPresent([CounterExample].self, forKey: .examples) ?? []
        wrong = try c.decodeIfPresent(String.self, forKey: .wrong)
    }
}

/// A 何 question that a counter answers: 教室に何人いますか。 and its English, "How many people are in the
/// classroom?". The Japanese holds 何 plus the counter; the counter quiz's *Ask it* shows the English.
public struct CounterAsking: Codable, Hashable, Sendable {
    public var jp: String
    public var en: String

    public init(jp: String, en: String) {
        self.jp = jp
        self.en = en
    }
}

/// A counter such as 本. Readings, and which of them changed, are generated by
/// `scripts/update_data.py`; the app only reads them and never derives one.
public struct Counter: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var counter: String
    public var reading: String
    public var meaning: String
    public var jlpt: JLPTLevel?
    /// The sound class, kept as a string: the app only shows it.
    public var sound: String
    public var symbol: String
    public var readings: [String: [String]]
    public var changed: [String]
    /// Wrong readings for each key, generated by `scripts/update_data.py`, for quiz choices. May be
    /// empty for a key; never holds an accepted reading.
    public var distractors: [String: [String]]
    /// False for a counter that measures rather than counts objects (年, 回, 円, 時): its things are
    /// examples of what it measures, so the *Which counter?* quiz leaves them out.
    public var countsObjects: Bool
    public var things: [CountedThing]
    public var examples: [CounterExample]
    public var pitfalls: [CounterPitfall]
    public var related: [String]
    /// 何 questions for the counter quiz (`questions` in counters.json); empty for a counter without any.
    public var askings: [CounterAsking]
    /// The largest number with readings from 11 up (10 when the counter has none).
    public var extent: Int
    /// Round numbers beyond `extent` with readings: 100, and 円's 200 to 10000.
    public var extra: [Int]
    /// Set when someone has reviewed this counter; nil means not yet reviewed.
    public var review: ReviewStamp?

    public init(
        id: String, counter: String, reading: String, meaning: String, jlpt: JLPTLevel? = nil,
        sound: String, symbol: String, readings: [String: [String]], changed: [String] = [],
        distractors: [String: [String]] = [:], countsObjects: Bool = true, things: [CountedThing] = [],
        examples: [CounterExample] = [], pitfalls: [CounterPitfall] = [], related: [String] = [],
        askings: [CounterAsking] = [], extent: Int = 10, extra: [Int] = [], review: ReviewStamp? = nil
    ) {
        self.id = id
        self.counter = counter
        self.reading = reading
        self.meaning = meaning
        self.jlpt = jlpt
        self.sound = sound
        self.symbol = symbol
        self.readings = readings
        self.changed = changed
        self.distractors = distractors
        self.countsObjects = countsObjects
        self.things = things
        self.examples = examples
        self.pitfalls = pitfalls
        self.related = related
        self.askings = askings
        self.extent = extent
        self.extra = extra
        self.review = review
    }

    // `overrides` is authoring input and is not decoded.
    enum CodingKeys: String, CodingKey {
        case id, counter, reading, meaning, jlpt, sound, symbol, readings, changed, distractors, countsObjects
        case things, examples, pitfalls, related, extent, extra, review
        case askings = "questions"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        counter = try c.decode(String.self, forKey: .counter)
        reading = try c.decode(String.self, forKey: .reading)
        meaning = try c.decode(String.self, forKey: .meaning)
        jlpt = try c.decodeIfPresent(JLPTLevel.self, forKey: .jlpt)
        sound = try c.decode(String.self, forKey: .sound)
        symbol = try c.decode(String.self, forKey: .symbol)
        readings = try c.decode([String: [String]].self, forKey: .readings)
        changed = try c.decodeIfPresent([String].self, forKey: .changed) ?? []
        distractors = try c.decodeIfPresent([String: [String]].self, forKey: .distractors) ?? [:]
        countsObjects = try c.decodeIfPresent(Bool.self, forKey: .countsObjects) ?? true
        things = try c.decodeIfPresent([CountedThing].self, forKey: .things) ?? []
        examples = try c.decodeIfPresent([CounterExample].self, forKey: .examples) ?? []
        pitfalls = try c.decodeIfPresent([CounterPitfall].self, forKey: .pitfalls) ?? []
        related = try c.decodeIfPresent([String].self, forKey: .related) ?? []
        askings = try c.decodeIfPresent([CounterAsking].self, forKey: .askings) ?? []
        extent = try c.decodeIfPresent(Int.self, forKey: .extent) ?? 10
        extra = try c.decodeIfPresent([Int].self, forKey: .extra) ?? []
        review = try c.decodeIfPresent(ReviewStamp.self, forKey: .review)
    }

    /// Preferred first. Empty only for malformed data.
    public func readings(for number: CounterNumber) -> [String] {
        readings[number.key] ?? []
    }

    public func isChanged(_ number: CounterNumber) -> Bool {
        changed.contains(number.key)
    }

    /// Wrong readings for quiz choices; empty when there are none for `number`.
    public func distractors(for number: CounterNumber) -> [String] {
        distractors[number.key] ?? []
    }

    /// The numbers above 10 this counter has readings for, ascending: 11 to `extent`, then `extra`.
    public var extendedNumbers: [CounterNumber] {
        (Array(11...max(11, extent)) + extra)
            .filter { value in !readings(for: .n(value)).isEmpty }
            .map(CounterNumber.n)
    }

    /// The extended number `delta` away from `number`, for the counter page's stepper: the first
    /// available number at or above the target going up, the last at or below it going down, clamped to
    /// the ends. A core number counts as 10. Nil when there is nowhere to go.
    public func step(_ number: CounterNumber, by delta: Int) -> CounterNumber? {
        let current: Int
        if case .n(let value) = number { current = max(value, 10) } else { current = 10 }
        let values = extendedNumbers.compactMap { number -> Int? in
            if case .n(let value) = number { value } else { nil }
        }
        let target = current + delta
        let found: Int?
        if delta > 0 {
            found = values.first { $0 >= target } ?? values.last.flatMap { $0 > current ? $0 : nil }
        } else {
            found = values.last { $0 <= target } ?? values.first.flatMap { $0 < current ? $0 : nil }
        }
        guard let found, found != current else { return nil }
        return .n(found)
    }

    /// 三本, 何本.
    public func written(_ number: CounterNumber) -> String {
        number.kanji + counter
    }

    /// Things in display order: primary, then acceptable, then casual, file order within each.
    public var thingsByFit: [CountedThing] {
        things.enumerated()
            .sorted { ($0.element.fit.rank, $0.offset) < ($1.element.fit.rank, $1.offset) }
            .map(\.element)
    }
}

public struct CounterGroupMember: Codable, Hashable, Sendable {
    /// A `Counter.id`.
    public var counter: String
    /// What the counter covers within this group.
    public var note: String?

    public init(counter: String, note: String? = nil) {
        self.counter = counter
        self.note = note
    }
}

/// A set of counters compared side by side ("Drinks": 杯, 本, つ). A counter can be in several.
public struct CounterGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var symbol: String
    public var summary: String
    public var members: [CounterGroupMember]

    public init(id: String, title: String, symbol: String, summary: String, members: [CounterGroupMember]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.summary = summary
        self.members = members
    }

    /// The members' counters, in member order. Ids missing from `all` are skipped, so pass the
    /// counters the level settings leave visible to hide the rest.
    public func counters(in all: [Counter]) -> [(counter: Counter, note: String?)] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return members.compactMap { member in
            byID[member.counter].map { ($0, member.note) }
        }
    }
}

/// A heading on the Counters home list ("Drinks": 杯, 本, つ), with the counters under it in order.
/// A counter may be in several sections.
public struct CounterSection: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    /// `Counter.id`s.
    public var counters: [String]

    public init(id: String, title: String, counters: [String]) {
        self.id = id
        self.title = title
        self.counters = counters
    }
}

/// The published `counters.json`.
public struct CountersDataFile: Codable, Equatable, Sendable {
    public var version: String
    public var description: String
    public var counters: [Counter]
    public var groups: [CounterGroup]
    /// The home list's headings. Optional in the data; empty in an older file.
    public var sections: [CounterSection]

    public init(
        version: String, description: String, counters: [Counter], groups: [CounterGroup] = [],
        sections: [CounterSection] = []
    ) {
        self.version = version
        self.description = description
        self.counters = counters
        self.groups = groups
        self.sections = sections
    }

    enum CodingKeys: String, CodingKey {
        case version, description, counters, groups, sections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        description = try c.decode(String.self, forKey: .description)
        counters = try c.decode([Counter].self, forKey: .counters)
        groups = try c.decodeIfPresent([CounterGroup].self, forKey: .groups) ?? []
        sections = try c.decodeIfPresent([CounterSection].self, forKey: .sections) ?? []
    }
}
