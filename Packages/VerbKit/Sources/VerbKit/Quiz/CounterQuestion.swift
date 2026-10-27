import Foundation

/// One counter quiz question. *Which counter?* shows a thing (傘) and asks for its counter (本);
/// *Read it* shows a counted form (三本) and asks for its reading (さんぼん); *Ask it* shows an English
/// question (How many people are there?) and asks for the 何 phrase (何人).
public struct CounterQuestion: Equatable, Sendable, Identifiable {
    public var id: UUID
    /// `.counterChoice`, `.counterReading` or `.counterAsk`.
    public var kind: QuizQuestionKind
    /// What quiz history records as the attempt's subject: the right counter shown.
    public var counterID: String
    /// What quiz history records as the form: the thing's word, or the number key ("3", "what").
    public var formID: String
    /// "傘" or "三本".
    public var prompt: String
    /// "umbrella", or the counter's meaning ("day of the month") so a form two counters share
    /// (一日) says which counter it is asked about.
    public var detail: String
    /// The thing's SF Symbol, for *Which counter?*.
    public var symbol: String?
    /// The right choice shown: the counter ("本") or the preferred reading ("さんぼん").
    public var correct: String
    /// Every choice that is right. Always contains `correct`; the other right choices are never on screen.
    public var accepted: Set<String>
    /// Shuffled: `correct` and up to three wrong choices.
    public var choices: [String]
    /// Shown after a wrong answer.
    public var explanation: String

    public init(
        id: UUID = UUID(), kind: QuizQuestionKind, counterID: String, formID: String, prompt: String,
        detail: String, symbol: String? = nil, correct: String, accepted: Set<String>,
        choices: [String], explanation: String
    ) {
        self.id = id
        self.kind = kind
        self.counterID = counterID
        self.formID = formID
        self.prompt = prompt
        self.detail = detail
        self.symbol = symbol
        self.correct = correct
        self.accepted = accepted
        self.choices = choices
        self.explanation = explanation
    }
}

/// Counter questions of one kind, shuffled and capped at `count`.
///
/// - `.counterChoice`: one question per distinct thing word, from counters that count objects
///   (`countsObjects`). The right counters are the ones that
///   list the word with the best fit; a word whose best fit is `casual` (the つ and 個 fallbacks)
///   makes no question. The wrong choices are counters that do not list the word at all, those
///   sharing a group with a right counter first, then the rest in order. A question that cannot
///   get two choices is skipped.
/// - `.counterReading`: one question per counter and number. The wrong choices are the counter's
///   generated `distractors`, then the preferred readings of the nearest other numbers; a question
///   with no wrong choice is skipped.
/// - `.counterAsk`: one question per counter `askings` entry. The right choice is the counter's 何
///   phrase (何人); the wrong ones are other counters' phrases, those sharing a group with the right
///   counter first, never the same text twice (two counters written 日 show one 何日). A question with
///   no wrong choice is skipped, and a counter without askings makes none.
/// - Any other kind builds nothing.
public func buildCounterQuestions(
    counters: [Counter], groups: [CounterGroup], kind: QuizQuestionKind, count: Int
) -> [CounterQuestion] {
    guard count > 0 else { return [] }
    let questions: [CounterQuestion]
    switch kind {
    case .counterChoice: questions = whichCounterQuestions(counters: counters, groups: groups)
    case .counterReading: questions = counters.flatMap(readItQuestions)
    case .counterAsk: questions = askItQuestions(counters: counters, groups: groups)
    default: return []
    }
    return Array(questions.shuffled().prefix(count))
}

/// Read it questions about one counter (Practise this counter), shuffled and capped at `count`.
public func buildCounterQuestions(for counter: Counter, count: Int) -> [CounterQuestion] {
    guard count > 0 else { return [] }
    return Array(readItQuestions(for: counter).shuffled().prefix(count))
}

/// Read it questions for exactly the given (counter, number) pairs, in order and unshuffled, so a
/// caller can ask about specific weak spots. A pair with no wrong choice to offer is skipped and the
/// result is never padded.
public func buildCounterQuestions(
    pairs: [(counter: Counter, number: CounterNumber)], count: Int
) -> [CounterQuestion] {
    guard count > 0 else { return [] }
    return Array(pairs.compactMap { readItQuestion(for: $0.counter, number: $0.number) }.prefix(count))
}

/// Bigger numbers: Read it questions for the numbers above 10 that the counters have readings for, drawn
/// without replacement and weighted: a number whose sound changed, or any number of an irregular counter,
/// is four times as likely as a plain one. Same question kind as Read it, so history, weak spots and
/// "Practise missed" need nothing new. Pairs with no wrong choice to offer are skipped.
public func buildBiggerNumberQuestions(
    counters: [Counter], count: Int, using generator: inout some RandomNumberGenerator
) -> [CounterQuestion] {
    guard count > 0 else { return [] }
    // Efraimidis-Spirakis: sort by random^(1/weight), take the largest keys.
    var keyed: [(key: Double, question: CounterQuestion)] = []
    for counter in counters {
        for number in counter.extendedNumbers {
            guard let question = readItQuestion(for: counter, number: number) else { continue }
            let weight = counter.isChanged(number) || counter.sound == "irregular" ? 4.0 : 1.0
            keyed.append((pow(Double.random(in: Double.leastNonzeroMagnitude..<1, using: &generator), 1 / weight), question))
        }
    }
    return keyed.sorted { $0.key > $1.key }.prefix(count).map(\.question)
}

public func buildBiggerNumberQuestions(counters: [Counter], count: Int) -> [CounterQuestion] {
    var generator = SystemRandomNumberGenerator()
    return buildBiggerNumberQuestions(counters: counters, count: count, using: &generator)
}

// MARK: Which counter?

private func whichCounterQuestions(counters all: [Counter], groups: [CounterGroup]) -> [CounterQuestion] {
    // Counters that measure (年, 回) are neither answers nor wrong choices here.
    let counters = all.filter(\.countsObjects)
    var words: [String] = []
    var listings: [String: [(counter: Counter, thing: CountedThing)]] = [:]
    for counter in counters {
        for thing in counter.things {
            if listings[thing.word] == nil { words.append(thing.word) }
            listings[thing.word, default: []].append((counter, thing))
        }
    }

    var questions: [CounterQuestion] = []
    for word in words {
        guard let listed = listings[word], let bestFit = listed.map(\.thing.fit).min(by: { $0.rank < $1.rank }),
              bestFit != .casual else { continue }
        let right = listed.filter { $0.thing.fit == bestFit }
        let rightChars = Set(right.map(\.counter.counter))
        let listingIDs = Set(listed.map(\.counter.id))
        let rightIDs = Set(right.map(\.counter.id))
        let sharingGroup = Set(groups.filter { group in group.members.contains { rightIDs.contains($0.counter) } }
            .flatMap { $0.members.map(\.counter) })

        let candidates = counters.filter { !listingIDs.contains($0.id) }
        let ordered = candidates.filter { sharingGroup.contains($0.id) } + candidates.filter { !sharingGroup.contains($0.id) }
        var wrong: [String] = []
        for counter in ordered where wrong.count < 3 {
            // Two counters can be written alike (日); never show a button twice.
            if !rightChars.contains(counter.counter) && !wrong.contains(counter.counter) { wrong.append(counter.counter) }
        }

        guard let shown = right.first, !wrong.isEmpty else { continue }
        let counted = right.map { "\($0.counter.counter) (\($0.counter.meaning))" }.joined(separator: " or ")
        questions.append(CounterQuestion(
            kind: .counterChoice, counterID: shown.counter.id, formID: word, prompt: word,
            detail: shown.thing.meaning, symbol: shown.thing.symbol ?? shown.counter.symbol,
            correct: shown.counter.counter, accepted: rightChars,
            choices: ([shown.counter.counter] + wrong).shuffled(),
            explanation: "\(word) is counted with \(counted)"
        ))
    }
    return questions
}

// MARK: Ask it

private func askItQuestions(counters: [Counter], groups: [CounterGroup]) -> [CounterQuestion] {
    let askers = counters.filter { !$0.askings.isEmpty }
    return askers.flatMap { counter -> [CounterQuestion] in
        let correct = counter.written(.what)
        let sharing = Set(groups.filter { $0.members.contains { $0.counter == counter.id } }
            .flatMap { $0.members.map(\.counter) })
        let others = askers.filter { $0.id != counter.id }
        var wrong: [String] = []
        for other in others.filter({ sharing.contains($0.id) }) + others.filter({ !sharing.contains($0.id) }) where wrong.count < 3 {
            let phrase = other.written(.what)
            if phrase != correct, !wrong.contains(phrase) { wrong.append(phrase) }
        }
        guard !wrong.isEmpty else { return [] }
        let reading = counter.readings(for: .what).first ?? ""
        return counter.askings.map { asking in
            CounterQuestion(
                kind: .counterAsk, counterID: counter.id, formID: asking.jp, prompt: asking.en,
                detail: "Pick the 何 phrase", correct: correct, accepted: [correct],
                choices: ([correct] + wrong).shuffled(), explanation: "\(asking.jp)  (\(correct): \(reading))"
            )
        }
    }
}

// MARK: Read it

private func readItQuestions(for counter: Counter) -> [CounterQuestion] {
    CounterNumber.allCases.compactMap { readItQuestion(for: counter, number: $0) }
}

private func readItQuestion(for counter: Counter, number: CounterNumber) -> CounterQuestion? {
    let accepted = counter.readings(for: number)
    guard let preferred = accepted.first else { return nil }
    let wrong = wrongReadings(for: counter, number: number, accepted: Set(accepted))
    guard !wrong.isEmpty else { return nil }
    return CounterQuestion(
        kind: .counterReading, counterID: counter.id, formID: number.key,
        prompt: counter.written(number), detail: counter.meaning, correct: preferred,
        accepted: Set(accepted), choices: ([preferred] + wrong).shuffled(),
        explanation: readingExplanation(for: counter, number: number, preferred: preferred)
    )
}

/// Up to three wrong readings: the generated ones, then the preferred readings of the nearest
/// other numbers (a real reading, for the wrong number), never an accepted reading.
private func wrongReadings(for counter: Counter, number: CounterNumber, accepted: Set<String>) -> [String] {
    var wrong: [String] = []
    func offer(_ reading: String) {
        if wrong.count < 3, !accepted.contains(reading), !wrong.contains(reading) { wrong.append(reading) }
    }
    counter.distractors(for: number).forEach(offer)
    // Nearest numbers in the same pool: 1 to 10 and 何, or the counter's numbers above 10.
    let all = number.isExtended ? counter.extendedNumbers : CounterNumber.allCases
    guard let here = all.firstIndex(of: number) else { return wrong }
    let others = all.indices.filter { $0 != here }.sorted {
        abs($0 - here) != abs($1 - here) ? abs($0 - here) < abs($1 - here) : $0 < $1
    }
    for index in others {
        if let reading = counter.readings(for: all[index]).first { offer(reading) }
    }
    return wrong
}

/// Names the pattern after a wrong answer, from the counter's own data: which numbers change, or
/// that it is irregular, or that nothing changes.
private func readingExplanation(for counter: Counter, number: CounterNumber, preferred: String) -> String {
    if number.isExtended {
        if counter.sound == "irregular" {
            return "\(counter.counter) is irregular: learn each reading. \(counter.written(number)) is \(preferred)"
        }
        guard counter.isChanged(number) else {
            return "\(counter.counter) keeps its plain reading at \(number.key): \(counter.written(number)) is \(preferred)."
        }
        let core = CounterNumber.allCases.filter(counter.isChanged).map { $0 == .what ? "何" : $0.key }
        let tail = core.isEmpty ? "" : ", as it does at \(core.joined(separator: ", "))"
        return "\(counter.written(number)) is \(preferred): the sound changes here\(tail)."
    }
    if counter.sound == "irregular" {
        return "\(counter.counter) is irregular: learn each reading. \(counter.written(number)) is \(preferred)"
    }
    let changed = CounterNumber.allCases.filter(counter.isChanged).map { $0 == .what ? "何" : $0.key }
    guard let last = changed.last else { return "\(counter.counter) has no sound changes: \(preferred)" }
    let list = changed.count == 1 ? last : changed.dropLast().joined(separator: ", ") + " and " + last
    if counter.isChanged(number) { return "\(counter.counter) changes at \(list): \(preferred)" }
    // A number that keeps its plain reading: say so, or "changes at …: にほん" reads as if it changed.
    return "\(counter.counter) keeps its plain reading at \(number == .what ? "何" : number.key): \(preferred). It changes at \(list)."
}
