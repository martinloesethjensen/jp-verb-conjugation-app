import Foundation

/// One *Spot the mistake* question: two or three forms, one of which is the wrong form a pitfall
/// warns about. The learner picks the wrong one; afterwards the pitfall's explanation and a link to
/// its lesson or counter page are shown.
public struct SpotMistakeQuestion: Equatable, Sendable, Identifiable {
    public var id: UUID
    /// `CommonMistake.id`: what quiz history records as the attempt's subject.
    public var mistakeID: String
    /// The pitfall's wrong form, and the right answer.
    public var wrong: String
    /// The forms that are fine. Never contains `wrong`.
    public var corrects: [String]
    /// `wrong` and `corrects`, shuffled. No form appears twice.
    public var choices: [String]
    /// True for a counter reading ("四人 よんにん"), false for a phrase or sentence.
    public var isReading: Bool
    public var heading: String
    public var explanation: String
    /// Where the pitfall comes from, for the link shown after answering.
    public var source: Route
    public var sourceTitle: String

    public init(
        id: UUID = UUID(), mistakeID: String, wrong: String, corrects: [String], choices: [String],
        isReading: Bool, heading: String, explanation: String, source: Route, sourceTitle: String
    ) {
        self.id = id
        self.mistakeID = mistakeID
        self.wrong = wrong
        self.corrects = corrects
        self.choices = choices
        self.isReading = isReading
        self.heading = heading
        self.explanation = explanation
        self.source = source
        self.sourceTitle = sourceTitle
    }
}

/// *Spot the mistake* questions, one per pitfall that has a `wrong` form, shuffled and capped at `count`.
///
/// - Only mistakes visible under `levels` are used, as on the Common mistakes screen.
/// - A grammar pitfall is set against up to two correct forms: its own examples first, then the
///   examples of the lesson's other pitfalls. Sentences lose their closing 。！？ so that the wrong
///   form, usually a fragment, is not given away by punctuation. An example that holds the wrong
///   form, or has two sentences, is never used.
/// - A counter pitfall's wrong form is a counted form with its reading ("四人 よんにん"); the correct
///   forms are the counter's other numbers from 1 to 10, written the same way.
/// - A pitfall with no correct form to show makes no question, and with nothing qualifying the result
///   is empty.
public func buildSpotMistakeQuestions(
    mistakes: [CommonMistake], counters: [Counter], levels: LevelSettings = LevelSettings(), count: Int
) -> [SpotMistakeQuestion] {
    guard count > 0 else { return [] }
    let visible = mistakes.visible(in: levels)
    let countersByID = Dictionary(counters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    // Every mistake of a lesson counts as a source of correct sentences, whether or not it has a wrong form.
    let examplesBySource = Dictionary(grouping: mistakes, by: \.source)
        .mapValues { $0.flatMap { $0.examples.map(\.jp) } }

    var questions: [SpotMistakeQuestion] = []
    for mistake in visible {
        guard let wrong = mistake.wrong?.trimmingCharacters(in: .whitespacesAndNewlines), !wrong.isEmpty else { continue }
        let isReading: Bool
        var pool: [String]
        if case .counter(let id) = mistake.source {
            guard let counter = countersByID[id] else { continue }
            isReading = true
            pool = counterForms(counter).filter { !wrong.hasPrefix($0.written + " ") }.map(\.form)
        } else {
            isReading = false
            let own = mistake.examples.map(\.jp)
            pool = sentenceChoices(own, excluding: wrong)
            if pool.isEmpty { pool = sentenceChoices(examplesBySource[mistake.source] ?? [], excluding: wrong) }
        }
        var seen: Set<String> = [wrong]
        let corrects = Array(pool.shuffled().filter { seen.insert($0).inserted }.prefix(2))
        guard !corrects.isEmpty else { continue }
        questions.append(SpotMistakeQuestion(
            mistakeID: mistake.id, wrong: wrong, corrects: corrects, choices: ([wrong] + corrects).shuffled(),
            isReading: isReading, heading: mistake.heading, explanation: mistake.explanation,
            source: mistake.source, sourceTitle: mistake.sourceTitle
        ))
    }
    return Array(questions.shuffled().prefix(count))
}

/// Single sentences without the closing 。！？, never one that contains the wrong form.
private func sentenceChoices(_ sentences: [String], excluding wrong: String) -> [String] {
    let marks = CharacterSet(charactersIn: "。！？!?")
    return sentences.compactMap { sentence in
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = Substring(trimmed)
        while let last = text.unicodeScalars.last, marks.contains(last) { text = text.dropLast() }
        guard !text.isEmpty, text.rangeOfCharacter(from: marks) == nil, !text.contains(wrong) else { return nil }
        return String(text)
    }
}

/// "三人 さんにん": the counter's numbers 1 to 10 with their preferred readings.
private func counterForms(_ counter: Counter) -> [(written: String, form: String)] {
    (1...10).compactMap { value -> (String, String)? in
        let number = CounterNumber.n(value)
        guard let reading = counter.readings(for: number).first else { return nil }
        let written = counter.written(number)
        return (written, "\(written) \(reading)")
    }
}
