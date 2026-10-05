import Foundation

/// A filter in the Word Bank search field. All tokens in a query must hold.
public enum WordBankToken: Hashable, Codable, Sendable {
    case dialectTag(UUID)
    /// Entries with any dialect tag in the region.
    case region(Region)
    /// Entries with any dialect tag in the prefecture.
    case prefecture(Prefecture)
    case customTag(UUID)
    /// The folder and every folder below it.
    case folder(UUID)
    case kind(EntryKind)
    case wordClass(WordClass)
    case unfiled
    case noDialectTag
}

/// Where in an entry a search matched, strongest first.
public enum WordBankField: String, Sendable {
    case text, reading, kanjiSpelling, equivalent, sense, tag, senseNote, folder, notes

    var weight: Double {
        switch self {
        case .text: return 100
        case .reading, .kanjiSpelling: return 90
        case .equivalent: return 80
        case .sense: return 70
        case .tag: return 50
        case .senseNote: return 30
        case .folder: return 20
        case .notes: return 10
        }
    }
}

public struct WordBankQuery: Hashable, Codable, Sendable {
    public var text: String
    public var tokens: [WordBankToken]
    /// Limits results to this folder and the folders below it.
    public var scopeFolder: UUID?

    public init(text: String = "", tokens: [WordBankToken] = [], scopeFolder: UUID? = nil) {
        self.text = text
        self.tokens = tokens
        self.scopeFolder = scopeFolder
    }
}

public struct WordBankMatch: Identifiable, Sendable {
    /// Why an entry matched, when it wasn't its text: "Standard: ありがとう".
    public struct Explanation: Hashable, Sendable {
        public var field: WordBankField
        /// The field's value, or for long values an excerpt around the match.
        public var snippet: String
        /// The matched part of `snippet`, when it can be found in the original text.
        public var range: Range<String.Index>?
    }

    /// What an explanation is built from. Building one searches the original text,
    /// which is slow, so it happens only when a row reads `explanation`.
    struct ExplanationSource: Sendable {
        var field: WordBankField
        var display: String
        var needles: [String]
    }

    public var entry: WordBankEntryValue
    /// 0 when the query has no text.
    public var score: Double
    var explanationSource: ExplanationSource?
    public var id: UUID { entry.id }

    /// nil when the entry matched on its text, or the query has no text.
    public var explanation: Explanation? {
        explanationSource.map(WordBankSearchIndex.explanation)
    }
}

/// A way out of an empty result: drop one token, or search outside the folder.
public struct WordBankRelaxation: Hashable, Sendable {
    public var dropping: WordBankToken?
    public var widenScope: Bool
    public var count: Int

    public init(dropping: WordBankToken?, widenScope: Bool, count: Int) {
        self.dropping = dropping
        self.widenScope = widenScope
        self.count = count
    }
}

/// Search over the whole bank in memory. Each entry's normalised keys are worked
/// out once here; build a new index when the bank changes.
///
/// Text is split into words on spaces outside double quotes (a quoted part is one
/// phrase). Every word must match somewhere. A word scores the best of
/// field weight × match quality over the entry's fields (exact 1, prefix 0.8, word
/// prefix 0.6, contains 0.4); a Latin word is also tried as kana against Japanese
/// fields, and only when nothing matches strictly are long vowels folded (0.25).
/// An entry's score is the sum over words; ties go to the most recently updated.
public struct WordBankSearchIndex: Sendable {
    private struct FieldValue: Sendable {
        var field: WordBankField
        var display: String
        /// Normalised keys as UTF-8, so matching compares bytes.
        var keys: [[UInt8]]
        /// Empty for fields that aren't matched loosely.
        var looseKeys: [[UInt8]]
        /// Whether a Latin word's kana form is tried here.
        var japanese: Bool
    }

    private struct Item: Sendable {
        var entry: WordBankEntryValue
        var fields: [FieldValue]
        var regions: Set<Region>
        var prefectures: Set<Prefecture>
    }

    private struct Word {
        var original: String
        var key: Needle
        var kana: Needle?
        /// The kana form as text, for finding the match in the original value.
        var kanaText: String?
        var loose: Needle
    }

    /// A normalised word as UTF-8, with its word-start form (" " + word) made once.
    private struct Needle {
        var bytes: [UInt8]
        var spaced: [UInt8]

        init(_ text: String) {
            bytes = Array(text.utf8)
            spaced = [UInt8(ascii: " ")] + bytes
        }
    }

    private let items: [Item]
    private let tree: FolderTree
    private let folders: [WordBankFolderValue]
    private let dialectTags: [DialectTagValue]
    private let customTags: [CustomTagValue]

    /// `derivedReading` gives a reading for entries that have none, such as
    /// `FuriganaDictionary.reading(of:)`, so "atama" finds 頭.
    public init(
        entries: [WordBankEntryValue], folders: [WordBankFolderValue],
        dialectTags: [DialectTagValue], customTags: [CustomTagValue],
        derivedReading: (String) -> String? = { _ in nil }
    ) {
        self.folders = folders
        self.dialectTags = dialectTags
        self.customTags = customTags
        tree = FolderTree(folders)
        let dialectByID = Dictionary(dialectTags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let customByID = Dictionary(customTags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let folderByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        items = entries.map { entry in
            var fields: [FieldValue] = []
            func add(_ field: WordBankField, _ display: String?, also extra: [String?] = [], japanese: Bool) {
                guard let display, !display.isEmpty else { return }
                let values = [display] + extra.compactMap { $0 }
                let keys = values.map(JapaneseNormalizer.key).filter { !$0.isEmpty }.map { Array($0.utf8) }
                fields.append(FieldValue(
                    field: field, display: display, keys: keys,
                    looseKeys: japanese ? values.map { Array(JapaneseNormalizer.looseKey($0).utf8) } : [],
                    japanese: japanese
                ))
            }
            add(.text, entry.text, japanese: true)
            let reading = entry.reading ?? derivedReading(entry.text).flatMap { $0 == entry.text ? nil : $0 }
            add(.reading, reading, japanese: true)
            add(.kanjiSpelling, entry.kanjiSpelling, japanese: true)
            for equivalent in entry.equivalents {
                add(.equivalent, equivalent.written, also: [equivalent.reading], japanese: true)
            }
            for sense in entry.senses { add(.sense, sense.meaning, japanese: false) }
            let tags = entry.dialectTagIDs.compactMap { dialectByID[$0] }
            for tag in tags { add(.tag, tag.name, also: [tag.romaji], japanese: true) }
            for tag in entry.customTagIDs.compactMap({ customByID[$0] }) { add(.tag, tag.name, japanese: true) }
            for sense in entry.senses { add(.senseNote, sense.note, japanese: false) }
            add(.folder, entry.folderID.flatMap { folderByID[$0]?.name }, japanese: false)
            add(.notes, entry.notes, japanese: false)
            return Item(
                entry: entry, fields: fields,
                regions: Set(tags.map(\.region)), prefectures: Set(tags.flatMap(\.prefectures))
            )
        }
    }

    // MARK: - Search

    /// Ranked when the query has text; otherwise the filtered entries in their
    /// original order, with score 0 and no explanation.
    public func search(_ query: WordBankQuery) -> [WordBankMatch] {
        let words = Self.words(in: query.text)
        guard !words.isEmpty else {
            return items.filter { passes($0, query) }
                .map { WordBankMatch(entry: $0.entry, score: 0, explanationSource: nil) }
        }
        // Score into small records and sort those; the full matches are built last.
        var ranked: [(index: Int, score: Double, best: (field: Int, word: Int))] = []
        for index in items.indices where passes(items[index], query) {
            if let result = score(items[index], words: words) {
                ranked.append((index, result.score, result.best))
            }
        }
        ranked.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let dateA = items[a.index].entry.updatedAt, dateB = items[b.index].entry.updatedAt
            if dateA != dateB { return dateA > dateB }
            return items[a.index].entry.id.uuidString < items[b.index].entry.id.uuidString
        }
        return ranked.map { record in
            let item = items[record.index]
            let field = item.fields[record.best.field]
            let word = words[record.best.word]
            let source = field.field == .text ? nil : WordBankMatch.ExplanationSource(
                field: field.field, display: field.display,
                needles: [word.original, word.kanaText, word.kanaText.map(Self.katakana)].compactMap { $0 }
            )
            return WordBankMatch(entry: item.entry, score: record.score, explanationSource: source)
        }
    }

    public func count(_ query: WordBankQuery) -> Int {
        search(query).count
    }

    /// Tokens whose name starts with (or, from two characters, contains) the
    /// fragment, and that would still return something alongside `excluding`.
    public func suggestedTokens(for fragment: String, excluding: [WordBankToken]) -> [WordBankToken] {
        guard !JapaneseNormalizer.key(fragment).isEmpty else { return [] }
        var candidates: [(WordBankToken, [String])] = []
        candidates += dialectTags.map { (.dialectTag($0.id), [$0.name, $0.romaji].compactMap { $0 }) }
        candidates += Region.allCases.map { (.region($0), [$0.name, $0.romaji]) }
        candidates += Prefecture.allCases.map { (.prefecture($0), [$0.name, $0.kana, $0.romaji]) }
        candidates += customTags.map { (.customTag($0.id), [$0.name]) }
        candidates += folders.map { (.folder($0.id), [$0.name]) }
        candidates += EntryKind.allCases.map { (.kind($0), [$0.rawValue]) }
        candidates += WordClass.allCases.map { (.wordClass($0), [$0.rawValue]) }
        return candidates
            .filter { token, names in
                !excluding.contains(token) && Self.names(names, match: fragment)
                    && count(WordBankQuery(tokens: excluding + [token])) > 0
            }
            .map(\.0)
    }

    /// For a query with no results: each token whose removal finds something, and
    /// searching all entries when the query is scoped to a folder. Counts > 0 only.
    public func relaxations(of query: WordBankQuery) -> [WordBankRelaxation] {
        var result: [WordBankRelaxation] = []
        for token in query.tokens {
            var relaxed = query
            relaxed.tokens.removeAll { $0 == token }
            let found = count(relaxed)
            if found > 0 { result.append(WordBankRelaxation(dropping: token, widenScope: false, count: found)) }
        }
        if query.scopeFolder != nil {
            var widened = query
            widened.scopeFolder = nil
            let found = count(widened)
            if found > 0 { result.append(WordBankRelaxation(dropping: nil, widenScope: true, count: found)) }
        }
        return result
    }

    // MARK: - Filtering

    private func passes(_ item: Item, _ query: WordBankQuery) -> Bool {
        let entry = item.entry
        if let scope = query.scopeFolder, !inSubtree(entry.folderID, of: scope) { return false }
        return query.tokens.allSatisfy { token in
            switch token {
            case .dialectTag(let id): return entry.dialectTagIDs.contains(id)
            case .region(let region): return item.regions.contains(region)
            case .prefecture(let prefecture): return item.prefectures.contains(prefecture)
            case .customTag(let id): return entry.customTagIDs.contains(id)
            case .folder(let id): return inSubtree(entry.folderID, of: id)
            case .kind(let kind): return entry.kind == kind
            case .wordClass(let wordClass): return entry.wordClass == wordClass
            case .unfiled: return entry.folderID == nil
            case .noDialectTag: return entry.dialectTagIDs.isEmpty
            }
        }
    }

    private func inSubtree(_ folder: UUID?, of root: UUID) -> Bool {
        guard let folder else { return false }
        return folder == root || tree.descendants(of: root).contains(folder)
    }

    // MARK: - Scoring

    /// The entry's total score and which field and word scored highest; nil
    /// unless every word matches.
    private func score(_ item: Item, words: [Word]) -> (score: Double, best: (field: Int, word: Int))? {
        var total = 0.0
        var bestScore = 0.0
        var best = (field: 0, word: 0)
        for (wordIndex, word) in words.enumerated() {
            guard let match = bestMatch(item, word) else { return nil }
            total += match.score
            if match.score > bestScore {
                bestScore = match.score
                best = (match.field, wordIndex)
            }
        }
        return (total, best)
    }

    /// Best score for one word and the index of the field it came from.
    private func bestMatch(_ item: Item, _ word: Word) -> (score: Double, field: Int)? {
        var bestScore = 0.0
        var bestField = -1
        for (index, field) in item.fields.enumerated() {
            let weight = field.field.weight
            guard weight > bestScore else { continue }   // even an exact match couldn't win
            for key in field.keys {
                var quality = Self.quality(word.key, in: key)
                if quality < 1, field.japanese, let kana = word.kana { quality = max(quality, Self.quality(kana, in: key)) }
                let score = quality * weight
                if score > bestScore { bestScore = score; bestField = index }
            }
        }
        if bestField >= 0 { return (bestScore, bestField) }
        // Nothing strict: try again with long vowels folded.
        for (index, field) in item.fields.enumerated() where field.japanese {
            let score = 0.25 * field.field.weight
            guard score > bestScore else { continue }
            if field.looseKeys.contains(where: { Self.quality(word.loose, in: $0) > 0 }) {
                bestScore = score
                bestField = index
            }
        }
        return bestField >= 0 ? (bestScore, bestField) : nil
    }

    /// Byte comparison is safe here: keys and needles went through the same
    /// normalisation (NFKC, hiragana, lowercase), so equal text has equal bytes.
    private static func quality(_ needle: Needle, in key: [UInt8]) -> Double {
        let bytes = needle.bytes
        guard !bytes.isEmpty, bytes.count <= key.count else { return 0 }
        let prefix = key.withUnsafeBytes { k in bytes.withUnsafeBytes { b in memcmp(k.baseAddress!, b.baseAddress!, b.count) == 0 } }
        if prefix { return key.count == bytes.count ? 1 : 0.8 }
        if key.count == bytes.count { return 0 }
        if contains(needle.spaced, in: key) { return 0.6 }
        if contains(bytes, in: key) { return 0.4 }
        return 0
    }

    private static func contains(_ needle: [UInt8], in haystack: [UInt8]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        return haystack.withUnsafeBytes { hay in
            needle.withUnsafeBytes { pin in
                memmem(hay.baseAddress, hay.count, pin.baseAddress, pin.count) != nil
            }
        }
    }

    private static func words(in text: String) -> [Word] {
        var parts: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if character == "\"" || character == "“" || character == "”" {
                quoted.toggle()
                if !current.isEmpty { parts.append(current); current = "" }
            } else if character.isWhitespace && !quoted {
                if !current.isEmpty { parts.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts.compactMap { part in
            let key = JapaneseNormalizer.key(part)
            guard !key.isEmpty else { return nil }
            let kana = JapaneseNormalizer.kanaForm(part).map(JapaneseNormalizer.key)
            return Word(
                original: part, key: Needle(key), kana: kana.map(Needle.init), kanaText: kana,
                loose: Needle(JapaneseNormalizer.looseKey(kana ?? part))
            )
        }
    }

    // MARK: - Explanations

    static func explanation(_ source: WordBankMatch.ExplanationSource) -> WordBankMatch.Explanation {
        let display = source.display
        let needles = source.needles
        let found = needles.lazy.compactMap { display.range(of: $0, options: searchOptions) }.first
        let excerpted = source.field == .notes || source.field == .senseNote || display.count > 60
        guard excerpted, let found else {
            return .init(field: source.field, snippet: display, range: found)
        }
        let lower = display.index(found.lowerBound, offsetBy: -20, limitedBy: display.startIndex) ?? display.startIndex
        let upper = display.index(found.upperBound, offsetBy: 20, limitedBy: display.endIndex) ?? display.endIndex
        let snippet = (lower > display.startIndex ? "…" : "") + display[lower..<upper] + (upper < display.endIndex ? "…" : "")
        let range = needles.lazy.compactMap { snippet.range(of: $0, options: searchOptions) }.first
        return .init(field: source.field, snippet: snippet, range: range)
    }

    private static let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    private static func katakana(_ hiragana: String) -> String {
        hiragana.applyingTransform(.hiraganaToKatakana, reverse: false) ?? hiragana
    }

    // MARK: - Token names

    private static func names(_ names: [String], match fragment: String) -> Bool {
        let tagQuery = JapaneseNormalizer.tagKey(fragment)
        let plainQuery = JapaneseNormalizer.key(fragment).filter { $0 != " " && $0 != "-" }
        return names.contains { name in
            let tagKey = JapaneseNormalizer.tagKey(name)
            let plainKey = JapaneseNormalizer.key(name).filter { $0 != " " && $0 != "-" }
            if !tagQuery.isEmpty, tagKey.hasPrefix(tagQuery) { return true }
            if !plainQuery.isEmpty, plainKey.hasPrefix(plainQuery) { return true }
            return plainQuery.count >= 2 && plainKey.contains(plainQuery)
        }
    }
}
