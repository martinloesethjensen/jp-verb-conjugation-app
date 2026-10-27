import Foundation

/// The groups on the Common mistakes screen, in display order.
public enum MistakeTheme: String, CaseIterable, Hashable, Sendable {
    case joining
    case lookAlike
    case meaningAndRegister
    case counterReadings

    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public var title: String {
        switch self {
        case .joining: "Joining"
        case .lookAlike: "Look-alike forms"
        case .meaningAndRegister: "Meaning and register"
        case .counterReadings: "Counter readings"
        }
    }

    public var blurb: String {
        switch self {
        case .joining: "Which form attaches, and what goes before it."
        case .lookAlike: "Forms and words that are easy to mix up."
        case .meaningAndRegister: "What it means, and how it sounds."
        case .counterReadings: "Sound changes and special readings."
        }
    }
}

/// One lesson or counter pitfall, with its theme and a route back to where it came from.
public struct CommonMistake: Hashable, Identifiable, Sendable, Leveled {
    /// "<lesson id>#<index>" for a lesson, "counter:<id>#<index>" for a counter.
    public var id: String
    public var theme: MistakeTheme
    public var heading: String
    public var explanation: String
    public var examples: [GrammarExample]
    /// The wrong form learners produce, when the pitfall has one.
    public var wrong: String?
    public var source: Route
    public var sourceTitle: String
    public var jlpt: JLPTLevel?

    public init(
        id: String, theme: MistakeTheme, heading: String, explanation: String, examples: [GrammarExample],
        wrong: String? = nil, source: Route, sourceTitle: String, jlpt: JLPTLevel? = nil
    ) {
        self.id = id
        self.theme = theme
        self.heading = heading
        self.explanation = explanation
        self.examples = examples
        self.wrong = wrong
        self.source = source
        self.sourceTitle = sourceTitle
        self.jlpt = jlpt
    }
}

public enum CommonMistakes {
    /// Hand-assigned themes, keyed "<lesson id>#<pitfall index>". A test checks that every
    /// grammar pitfall has an entry and that no key is stale.
    static let grammarThemes: [String: MistakeTheme] = [
        "n-desu#0": .joining, "n-desu#1": .meaningAndRegister, "n-desu#2": .joining,
        "potential#0": .lookAlike, "potential#1": .meaningAndRegister, "potential#2": .lookAlike,
        "potential#3": .joining,
        "certainty#0": .joining, "certainty#1": .lookAlike, "certainty#2": .meaningAndRegister,
        "obligation#0": .meaningAndRegister, "obligation#1": .joining, "obligation#2": .lookAlike,
        "appearance#0": .lookAlike, "appearance#1": .joining, "appearance#2": .lookAlike,
        "ppoi#0": .meaningAndRegister, "ppoi#1": .joining,
        "teiru#0": .meaningAndRegister, "teiru#1": .meaningAndRegister, "teiru#2": .joining,
        "teiru#3": .lookAlike,
        "teshimau#0": .meaningAndRegister, "teshimau#1": .lookAlike, "teshimau#2": .meaningAndRegister,
        "temiru#0": .meaningAndRegister, "temiru#1": .joining, "temiru#2": .meaningAndRegister,
        "sugiru#0": .joining, "sugiru#1": .meaningAndRegister, "sugiru#2": .lookAlike,
        "node#0": .joining, "node#1": .lookAlike,
        "hou-ga-ii#0": .joining, "hou-ga-ii#1": .meaningAndRegister,
        "tai#0": .lookAlike, "tai#1": .meaningAndRegister,
        "volitional#0": .lookAlike, "volitional#1": .joining,
        "nai-te#0": .joining, "nai-te#1": .joining,
        "te-mo-ii#0": .meaningAndRegister, "te-mo-ii#1": .joining,
        "nakereba#0": .meaningAndRegister, "nakereba#1": .joining,
        // Only one pitfall is about a particle (な), so there is no Particles group; it joins Joining.
        "imperative#0": .meaningAndRegister, "imperative#1": .joining, "imperative#2": .joining,
    ]

    /// Counter pitfalls are Counter readings unless listed here, keyed "<counter id>#<index>".
    static let counterExceptions: [String: MistakeTheme] = [
        "ko#1": .lookAlike, "hiki#1": .lookAlike, "hai#1": .lookAlike, "kai#0": .lookAlike,
        "fun#1": .lookAlike, "ji#1": .meaningAndRegister, "nen#1": .lookAlike, "jikan#0": .lookAlike,
        "kagetsu#0": .meaningAndRegister, "nenkan#0": .lookAlike, "nichikan#0": .lookAlike,
        "soku#1": .meaningAndRegister, "chaku#1": .meaningAndRegister, "ban#0": .meaningAndRegister,
        "ban#1": .lookAlike, "tou#1": .lookAlike, "wa#1": .meaningAndRegister,
        "dai#0": .meaningAndRegister,
    ]

    /// Every pitfall of every lesson and counter, in data order.
    public static func build(grammar: [GrammarPoint], counters: [Counter]) -> [CommonMistake] {
        var result: [CommonMistake] = []
        for point in grammar {
            for (index, pitfall) in point.pitfalls.enumerated() {
                let key = "\(point.id)#\(index)"
                result.append(CommonMistake(
                    id: key, theme: grammarThemes[key] ?? .meaningAndRegister, heading: pitfall.heading,
                    explanation: pitfall.explanation, examples: pitfall.examples,
                    wrong: pitfall.wrong, source: .grammar(point.id), sourceTitle: point.title, jlpt: point.jlpt))
            }
        }
        for counter in counters {
            for (index, pitfall) in counter.pitfalls.enumerated() {
                let key = "\(counter.id)#\(index)"
                result.append(CommonMistake(
                    id: "counter:\(key)", theme: counterExceptions[key] ?? .counterReadings,
                    heading: pitfall.heading, explanation: pitfall.explanation,
                    examples: pitfall.examples.map { GrammarExample(jp: $0.jp, en: $0.en) },
                    wrong: pitfall.wrong, source: .counter(counter.id), sourceTitle: "\(counter.counter) (\(counter.meaning))",
                    jlpt: counter.jlpt))
            }
        }
        return result
    }

    /// The mistakes by theme, in display order; themes with none are left out.
    public static func grouped(_ mistakes: [CommonMistake]) -> [(theme: MistakeTheme, mistakes: [CommonMistake])] {
        MistakeTheme.allCases.compactMap { theme in
            let items = mistakes.filter { $0.theme == theme }
            return items.isEmpty ? nil : (theme, items)
        }
    }
}

/// Matches the heading, the explanation and the Japanese of the examples. Romaji is tried as
/// hiragana; with a furigana dictionary the examples also match by reading.
public func matchesMistakeSearch(_ mistake: CommonMistake, query: String, furigana: FuriganaDictionary? = nil) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    if mistake.heading.localizedCaseInsensitiveContains(trimmed)
        || mistake.explanation.localizedCaseInsensitiveContains(trimmed)
        || (mistake.wrong?.contains(trimmed) ?? false)
        || mistake.sourceTitle.contains(trimmed) { return true }
    let kana = Romaji.toHiragana(trimmed).map { $0.filter { !$0.isWhitespace } }
    for example in mistake.examples {
        if example.jp.contains(trimmed) { return true }
        if let kana, example.jp.contains(kana) { return true }
        if let furigana {
            let reading = furigana.reading(of: example.jp)
            if reading.contains(trimmed) || (kana.map(reading.contains) ?? false) { return true }
        }
    }
    if let kana, mistake.heading.contains(kana) { return true }
    return false
}
