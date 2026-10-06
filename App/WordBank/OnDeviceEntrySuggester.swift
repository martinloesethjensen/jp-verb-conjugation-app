import Foundation
import FoundationModels
import os
import VerbKit

/// How sure the model says it is. Only medium and high are shown.
@Generable
private enum SuggestionConfidence: String {
    case low, medium, high
}

@Generable
private enum SuggestedKind: String {
    case word, phrase, sentence
}

/// The structure the on-device model fills in. Guided generation keeps it to these fields;
/// empty strings and arrays mean "don't know".
@Generable
private struct GeneratedEntryHints {
    @Guide(description: "The text written in hiragana only. Empty if you are not sure.")
    var reading: String

    @Guide(description: "At most two ways to say the same thing in standard Japanese (Tokyo speech), written as in a dictionary. Empty if unsure.")
    var standardForms: [String]

    @Guide(description: "At most three short English meanings. Empty if unsure.")
    var meanings: [String]

    var kind: SuggestedKind

    @Guide(description: "The id of the dialect from the list this text belongs to, exactly as listed, or an empty string if it is not clearly from one of them.")
    var dialectID: String

    @Guide(description: "How sure you are that the meanings and standard forms are right.")
    var confidence: SuggestionConfidence
}

/// Suggests a reading, standard Japanese, meanings, kind and dialect for what the user typed,
/// with Apple's on-device model. Nothing leaves the device. The model is small: expect good
/// answers for common words and guesses for rare dialects, which is why the editor only ever
/// offers these as tap-to-apply chips and hides low-confidence answers.
struct OnDeviceEntrySuggester: EntrySuggesting {
    private let catalogue: DialectCatalogue

    init(catalogue: DialectCatalogue = .bundled) {
        self.catalogue = catalogue
    }

    var isAvailable: Bool {
        let model = SystemLanguageModel.default
        return model.availability == .available && model.supportsLocale(Locale(identifier: "ja_JP"))
    }

    /// Why it isn't available, in words for Settings; nil when it is.
    static var unavailableReason: String? {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return model.supportsLocale(Locale(identifier: "ja_JP")) ? nil : "The on-device model doesn't support Japanese on this device."
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to get suggestions."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading."
        case .unavailable:
            return "The on-device model isn't available."
        }
    }

    func suggest(for text: String) async throws -> EntrySuggestion {
        let dialects = catalogue.dialects.map { "\($0.id): \($0.name)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            You help a Japanese learner file words, phrases and sentences they heard, many of them \
            in regional dialects (方言). For the text you are given, fill in the structure. \
            Say you are unsure rather than guessing. Never invent a dialect: choose from this list or leave it empty.

            Dialects:
            \(dialects)
            """)
        do {
            let response = try await session.respond(
                to: "Text: \(text)",
                generating: GeneratedEntryHints.self,
                options: GenerationOptions(temperature: 0.2)
            )
            return suggestion(from: response.content, for: text)
        } catch {
            Logger(subsystem: "dev.martinloeseth.jpverbconjugation", category: "suggestions")
                .error("On-device suggestion failed: \(String(describing: error), privacy: .private)")
            throw error
        }
    }

    private func suggestion(from hints: GeneratedEntryHints, for text: String) -> EntrySuggestion {
        guard hints.confidence != .low else { return EntrySuggestion(isUnsure: true) }
        func clean(_ values: [String], limit: Int) -> [String] {
            var seen = Set<String>()
            return values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert(JapaneseNormalizer.key($0)).inserted }
                .prefix(limit)
                .map { $0 }
        }
        let own = JapaneseNormalizer.key(text)
        let forms = clean(hints.standardForms, limit: 2).filter { JapaneseNormalizer.key($0) != own }
        let reading = hints.reading.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = catalogue.dialects.contains { $0.id == hints.dialectID } ? hints.dialectID : nil
        return EntrySuggestion(
            reading: reading.isEmpty || JapaneseNormalizer.key(reading) == own ? nil : reading,
            standardForms: forms.map { StandardEquivalent(written: $0) },
            meanings: clean(hints.meanings, limit: 3),
            kind: EntryKind(rawValue: hints.kind.rawValue),
            dialectCatalogueID: id
        )
    }
}
