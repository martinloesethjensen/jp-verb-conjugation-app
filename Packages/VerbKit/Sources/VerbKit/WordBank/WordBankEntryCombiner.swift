import Foundation

extension WordBankEntryValue {
    public func trimmed() -> WordBankEntryValue {
        func clean(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        var entry = self
        entry.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.reading = clean(reading)
        entry.kanjiSpelling = clean(kanjiSpelling)
        entry.notes = clean(notes)
        entry.senses = senses.compactMap { sense in
            clean(sense.meaning).map { Sense(meaning: $0, note: clean(sense.note)) }
        }
        entry.equivalents = equivalents.compactMap { equivalent in
            clean(equivalent.written).map {
                StandardEquivalent(written: $0, reading: clean(equivalent.reading), note: clean(equivalent.note))
            }
        }
        if entry.kind != .word { entry.wordClass = nil }
        return entry
    }
}

/// What importing does to an entry that already exists: nothing is deleted or overwritten.
public enum WordBankEntryCombiner {
    public struct Result: Equatable, Sendable {
        public var entry: WordBankEntryValue
        public var changed: Bool
    }

    public static func combine(
        local: WordBankEntryValue, incoming: WordBankEntryValue, importedFolderID: UUID?,
        importedOn: Date, now: Date
    ) -> Result {
        var merged = local
        merged.reading = local.reading ?? incoming.reading
        merged.kanjiSpelling = local.kanjiSpelling ?? incoming.kanjiSpelling
        merged.linkedWordID = local.linkedWordID ?? incoming.linkedWordID
        merged.linkedFormID = local.linkedFormID ?? incoming.linkedFormID
        if local.kind == .word { merged.wordClass = local.wordClass ?? incoming.wordClass }

        var senseKeys = Set(merged.senses.map { JapaneseNormalizer.key($0.meaning) })
        for sense in incoming.senses where senseKeys.insert(JapaneseNormalizer.key(sense.meaning)).inserted {
            merged.senses.append(sense)
        }
        func equivalentKey(_ value: StandardEquivalent) -> String {
            JapaneseNormalizer.key(value.written) + "|" + JapaneseNormalizer.key(value.reading ?? "")
        }
        var equivalentKeys = Set(merged.equivalents.map(equivalentKey))
        for equivalent in incoming.equivalents where equivalentKeys.insert(equivalentKey(equivalent)).inserted {
            merged.equivalents.append(equivalent)
        }
        merged.dialectTagIDs += incoming.dialectTagIDs.filter { !merged.dialectTagIDs.contains($0) }
        merged.customTagIDs += incoming.customTagIDs.filter { !merged.customTagIDs.contains($0) }

        if let note = incoming.notes {
            let have = local.notes ?? ""
            if !JapaneseNormalizer.key(have).contains(JapaneseNormalizer.key(note)) {
                merged.notes = have.isEmpty ? note : have + "\n\nImported \(day(importedOn)): \(note)"
            }
        }
        if merged.folderID == nil { merged.folderID = importedFolderID }

        let changed = merged != local
        if changed { merged.updatedAt = now }
        merged.createdAt = min(local.createdAt, incoming.createdAt)
        return Result(entry: merged, changed: changed)
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
