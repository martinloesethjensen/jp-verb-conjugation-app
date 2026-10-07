import Foundation
import Observation

/// What a suggester proposes for the text the user typed. Every field is optional:
/// nothing is applied to an entry until the user taps it.
public struct EntrySuggestion: Equatable, Sendable {
    public var reading: String?
    public var standardForms: [StandardEquivalent]
    public var meanings: [String]
    public var kind: EntryKind?
    /// A `DialectRecord.id` from the bundled catalogue; never a name the model made up.
    public var dialectCatalogueID: String?
    /// The suggester said it wasn't sure: whatever it suggests is a guess, shown as one.
    public var isUnsure: Bool

    public init(
        reading: String? = nil, standardForms: [StandardEquivalent] = [], meanings: [String] = [],
        kind: EntryKind? = nil, dialectCatalogueID: String? = nil, isUnsure: Bool = false
    ) {
        self.reading = reading
        self.standardForms = standardForms
        self.meanings = meanings
        self.kind = kind
        self.dialectCatalogueID = dialectCatalogueID
        self.isUnsure = isUnsure
    }

    public var isEmpty: Bool {
        reading == nil && standardForms.isEmpty && meanings.isEmpty && kind == nil && dialectCatalogueID == nil
    }

    /// The part of the suggestion the entry doesn't already have, so a tapped chip
    /// disappears and a hand-typed value is never suggested again.
    public func removing(whatIsIn entry: WordBankEntryValue, appliedDialectCatalogueIDs: Set<String>) -> EntrySuggestion {
        var rest = self
        // Never suggest over a reading the entry has (typed, or filled in from the dictionary),
        // and a "reading" that is just the text again is no help.
        if entry.reading != nil || reading.map({ JapaneseNormalizer.key($0) == JapaneseNormalizer.key(entry.text) }) == true {
            rest.reading = nil
        }
        let haveForms = Set(entry.equivalents.map { JapaneseNormalizer.key($0.written) })
        rest.standardForms = standardForms.filter { !haveForms.contains(JapaneseNormalizer.key($0.written)) }
        let haveMeanings = Set(entry.senses.map { JapaneseNormalizer.key($0.meaning) })
        rest.meanings = meanings.filter { !haveMeanings.contains(JapaneseNormalizer.key($0)) }
        if kind == entry.kind { rest.kind = nil }
        if let id = dialectCatalogueID, appliedDialectCatalogueIDs.contains(id) { rest.dialectCatalogueID = nil }
        return rest
    }
}

public extension WordBankEntryValue {
    /// Sets the reading unless the entry already has one.
    mutating func apply(reading: String) {
        let trimmed = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.reading == nil, !trimmed.isEmpty else { return }
        self.reading = trimmed
    }

    mutating func apply(standardForm: StandardEquivalent) {
        let key = JapaneseNormalizer.key(standardForm.written)
        guard !key.isEmpty, !equivalents.contains(where: { JapaneseNormalizer.key($0.written) == key }) else { return }
        equivalents.append(standardForm)
    }

    mutating func apply(meaning: String) {
        let trimmed = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = JapaneseNormalizer.key(trimmed)
        guard !key.isEmpty, !senses.contains(where: { JapaneseNormalizer.key($0.meaning) == key }) else { return }
        senses.append(Sense(meaning: trimmed))
    }

    mutating func apply(kind: EntryKind) {
        self.kind = kind
    }
}

/// Produces suggestions for an entry's text, for example with an on-device language model.
public protocol EntrySuggesting: Sendable {
    /// False when the suggester can't run here (no model, not enabled, language unsupported).
    var isAvailable: Bool { get }
    func suggest(for text: String) async throws -> EntrySuggestion
}

/// Runs a suggester as the user types: waits for a pause, drops answers for text that has
/// changed, and keeps the state the editor shows.
@MainActor
@Observable
public final class EntrySuggestionModel {
    public enum State: Equatable, Sendable {
        /// Nothing to suggest for yet (no or too little text).
        case idle
        /// No suggester, or it can't run on this device.
        case unavailable
        case loading
        case ready(EntrySuggestion)
        /// The suggester answered with nothing useful.
        case nothing
        /// The suggester wasn't sure and had nothing to suggest. An unsure answer with
        /// content is `ready`, with `isUnsure` set.
        case unsure
        case failed
    }

    public private(set) var state: State = .idle

    @ObservationIgnored private let suggester: EntrySuggesting?
    @ObservationIgnored private let minimumLength: Int
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let pause: Duration
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastText = ""
    @ObservationIgnored private var lastAsked: String?

    public init(
        suggester: EntrySuggesting?, pause: Duration = .seconds(1), minimumLength: Int = 2,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.suggester = suggester
        self.pause = pause
        self.minimumLength = minimumLength
        self.sleep = sleep
    }

    /// Call on every edit of the text. Starts a request after a pause with no further edits.
    public func textChanged(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastText = trimmed
        guard let suggester, suggester.isAvailable else {
            task?.cancel()
            state = .unavailable
            return
        }
        guard trimmed.count >= minimumLength else {
            task?.cancel()
            lastAsked = nil
            state = .idle
            return
        }
        guard JapaneseNormalizer.key(trimmed) != lastAsked.map(JapaneseNormalizer.key) else { return }
        run(trimmed, suggester: suggester, waiting: true)
    }

    /// Asks again for the current text, without waiting.
    public func retry() {
        guard let suggester, suggester.isAvailable, lastText.count >= minimumLength else { return }
        run(lastText, suggester: suggester, waiting: false)
    }

    private func run(_ text: String, suggester: EntrySuggesting, waiting: Bool) {
        task?.cancel()
        state = .loading
        task = Task { [weak self, sleep, pause] in
            do {
                if waiting { try await sleep(pause) }
                try Task.checkCancellation()
                await MainActor.run { self?.lastAsked = text }
                let suggestion = try await suggester.suggest(for: text)
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self, self.lastText == text else { return }
                    self.state = !suggestion.isEmpty ? .ready(suggestion) : suggestion.isUnsure ? .unsure : .nothing
                }
            } catch is CancellationError {
                // A newer request replaced this one.
            } catch {
                await MainActor.run {
                    guard let self, self.lastText == text else { return }
                    self.state = .failed
                }
            }
        }
    }
}
