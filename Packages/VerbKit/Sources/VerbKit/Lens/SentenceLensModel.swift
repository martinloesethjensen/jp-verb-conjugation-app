import Foundation
import Observation

/// A piece of the Sentence lens transcript: text between verbs, or a verb to highlight.
public enum LensSegment: Hashable, Sendable {
    case text(String)
    case verb(FormLookup.Item)
}

/// A transformed sentence split around the swapped verb, so the preview can highlight it.
public struct LensPreview: Hashable, Sendable {
    public let before: String
    public let replacement: String
    public let after: String
    public let note: TransformNote?

    public var sentence: String { before + replacement + after }
}

/// Text clean-up for the lens: what the matcher sees, and how a live transcript joins it.
public enum LensText {
    /// The text the lens analyses: trimmed, with line breaks as spaces so the transcript
    /// flows as one sentence. Every range the lens shows points into this string.
    public static func sentence(from text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// A finalised transcript segment, cleaned for Japanese. `SpeechTranscriber` puts a space
    /// before digits (歩いて 10分): spaces go unless both neighbours are ASCII letters or
    /// digits (iPhone 17).
    public static func transcript(_ text: String) -> String {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var result = ""
        for (index, character) in characters.enumerated() {
            if character.isWhitespace {
                let before = index > 0 ? characters[index - 1] : nil
                let after = index + 1 < characters.count ? characters[index + 1] : nil
                if let before, let after, isLatin(before), isLatin(after), !(result.last?.isWhitespace ?? true) {
                    result.append(" ")
                }
                continue
            }
            result.append(character)
        }
        return result
    }

    /// `segment` added to the end of `text`, joined without a space as Japanese is.
    public static func appending(_ segment: String, to text: String) -> String {
        let cleaned = transcript(segment)
        guard !cleaned.isEmpty else { return text }
        let base = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return base + cleaned
    }

    private static func isLatin(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}

/// The Sentence lens's state (#147): the sentence, its verbs, the verb the learner tapped,
/// the reading they chose and the transform they applied. The app's view and its live
/// transcriber stay thin around it; the matching itself is `FormLookupStore`'s, built once
/// for the app.
@MainActor
@Observable
public final class SentenceLensModel {
    /// What the learner typed, pasted, dictated or said. Live speech only adds finalised
    /// text, so highlights never flicker under volatile results.
    public var text: String

    /// The verb whose sheet is open; nil when none is.
    public var selected: FormLookup.Item? {
        didSet {
            guard selected?.id != oldValue?.id else { return }
            chosenReadingID = nil
            applied = nil
        }
    }

    /// The reading the learner chose for an ambiguous verb; nil means the first.
    public var chosenReadingID: String? {
        didSet { if chosenReadingID != oldValue { applied = nil } }
    }

    /// The transform shown in the preview; nil shows the original sentence.
    public private(set) var applied: FormTransform?

    @ObservationIgnored private let store: FormLookupStore

    public init(store: FormLookupStore, text: String = "") {
        self.store = store
        self.text = text
    }

    /// The text the spans index into.
    public var sentence: String { LensText.sentence(from: text) }

    public var isBlank: Bool { sentence.isEmpty }

    /// The verbs in the sentence. Re-run on every read: the matcher is cheap, and this way
    /// the highlights follow both the text and the data.
    public var items: [FormLookup.Item] { store.items(in: sentence) }

    /// The sentence cut into text and verbs, in order.
    public var segments: [LensSegment] {
        Self.segments(of: sentence, items: items)
    }

    public static func segments(of sentence: String, items: [FormLookup.Item]) -> [LensSegment] {
        var segments: [LensSegment] = []
        var cursor = sentence.startIndex
        for item in items {
            let range = item.span.range
            // A span out of step with the text (the data changed under it) is skipped, never
            // drawn over its neighbour.
            guard range.lowerBound >= cursor, range.upperBound <= sentence.endIndex else { continue }
            if cursor < range.lowerBound {
                segments.append(.text(String(sentence[cursor..<range.lowerBound])))
            }
            segments.append(.verb(item))
            cursor = range.upperBound
        }
        if cursor < sentence.endIndex {
            segments.append(.text(String(sentence[cursor...])))
        }
        return segments
    }

    /// Adds a finalised transcript segment.
    public func appendTranscript(_ segment: String) {
        text = LensText.appending(segment, to: text)
    }

    // MARK: The tapped verb

    /// The reading the sheet shows: the chosen one, or the first.
    public var chosenReading: FormLookup.Reading? {
        guard let selected else { return nil }
        return selected.readings.first { $0.id == chosenReadingID } ?? selected.readings.first
    }

    /// The transform chips for the tapped verb, in its chosen reading.
    public var transforms: SpanTransforms {
        guard let selected else { return .unavailable(.chooseReading) }
        return store.transforms(for: selected, reading: chosenReading, in: sentence)
    }

    /// The catalogue label of a chip's target form.
    public func label(for form: FormID) -> String {
        store.label(for: form)
    }

    /// Shows `transform` in the preview; a disabled one does nothing.
    public func apply(_ transform: FormTransform) {
        guard transform.rewrite != nil else { return }
        applied = transform
    }

    /// Back to the original sentence.
    public func resetPreview() {
        applied = nil
    }

    /// The applied transform's sentence, split around the new verb; nil for the original.
    public var preview: LensPreview? {
        guard let rewrite = applied?.rewrite else { return nil }
        let sentence = sentence
        guard rewrite.range.upperBound <= sentence.endIndex else { return nil }
        return LensPreview(
            before: String(sentence[..<rewrite.range.lowerBound]),
            replacement: rewrite.replacement,
            after: String(sentence[rewrite.range.upperBound...]),
            note: rewrite.note
        )
    }

    /// What Play speaks and Copy copies: the preview, or the original sentence.
    public var outputText: String { preview?.sentence ?? sentence }
}
