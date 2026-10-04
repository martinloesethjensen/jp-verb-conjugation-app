import Foundation

public enum TagSuggestion: Hashable, Sendable {
    case existingDialect(DialectTagValue)
    case existingCustom(CustomTagValue)
    /// A catalogue dialect not yet made into a tag.
    case dialect(DialectRecord)
    /// A plain prefecture tag (岐阜県).
    case prefecture(Prefecture)
    case customIdea(name: String, color: CustomTagColor)
    case createCustom(String)
    case createDialect(String, preselected: Prefecture?)
}

/// What the tag field shows for a query, in sections.
public struct TagSuggestions: Equatable, Sendable {
    /// The user's own tags that match; shown first so a tag is reused, not duplicated.
    public var yours: [TagSuggestion]
    public var dialects: [TagSuggestion]
    public var ideas: [TagSuggestion]
    /// Empty when the query names an existing tag exactly.
    public var create: [TagSuggestion]
    public var isDuplicate: Bool

    public init(
        yours: [TagSuggestion], dialects: [TagSuggestion], ideas: [TagSuggestion],
        create: [TagSuggestion], isDuplicate: Bool
    ) {
        self.yours = yours
        self.dialects = dialects
        self.ideas = ideas
        self.create = create
        self.isDuplicate = isDuplicate
    }
}

/// Matches what the user types against their tags, the dialect catalogue and a
/// short list of custom tag ideas. Dialect names compare by
/// `JapaneseNormalizer.tagKey` (kana, romaji, macrons and 弁 endings don't matter);
/// custom tags compare by their plain `key`, so English names aren't read as romaji.
public struct TagSuggester: Sendable {
    public static let defaultIdeas: [(String, CustomTagColor)] = [
        ("greetings", .green), ("food", .orange), ("slang", .purple), ("casual", .teal),
        ("polite", .blue), ("from a friend", .yellow), ("overheard", .gray), ("work", .red),
    ]

    private let catalogue: DialectCatalogue
    private let ideas: [(String, CustomTagColor)]

    public init(catalogue: DialectCatalogue = .bundled, ideas: [(String, CustomTagColor)] = TagSuggester.defaultIdeas) {
        self.catalogue = catalogue
        self.ideas = ideas
    }

    public func suggestions(
        for query: String, dialectTags: [DialectTagValue], customTags: [CustomTagValue], excluding applied: Set<UUID>
    ) -> TagSuggestions {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagQuery = JapaneseNormalizer.tagKey(trimmed)
        let plainQuery = Self.plainKey(trimmed)
        guard !tagQuery.isEmpty || !plainQuery.isEmpty else {
            return TagSuggestions(yours: [], dialects: [], ideas: [], create: [], isDuplicate: false)
        }

        // Already yours.
        var mine: [(rank: Int, name: String, suggestion: TagSuggestion)] = []
        for tag in dialectTags where !applied.contains(tag.id) {
            if let rank = Self.rank(tagQuery, primary: dialectKeys(tag), aliases: recordAliasKeys(tag)) {
                mine.append((rank, tag.name, .existingDialect(tag)))
            }
        }
        for tag in customTags where !applied.contains(tag.id) {
            if let rank = Self.rank(plainQuery, primary: [Self.plainKey(tag.name)], aliases: []) {
                mine.append((rank, tag.name, .existingCustom(tag)))
            }
        }
        mine.sort { ($0.rank, $0.name) < ($1.rank, $1.name) }

        let isDuplicate = dialectTags.contains { dialectKeys($0).contains(tagQuery) }
            || customTags.contains { Self.plainKey($0.name) == plainQuery }

        // Catalogue dialects, then the dialects of any prefecture the query names.
        let created = Set(dialectTags.compactMap(\.catalogueID))
        let takenNames = Set(dialectTags.map { JapaneseNormalizer.tagKey($0.name) })
        func available(_ record: DialectRecord) -> Bool {
            !created.contains(record.id) && !takenNames.contains(JapaneseNormalizer.tagKey(record.name))
        }
        let direct = catalogue.dialects.enumerated()
            .compactMap { index, record -> (rank: Int, index: Int, record: DialectRecord)? in
                guard available(record),
                      let rank = Self.rank(tagQuery, primary: Self.recordKeys(record), aliases: record.aliases.map(JapaneseNormalizer.tagKey))
                else { return nil }
                return (rank, index, record)
            }
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .map(\.record)
        let prefectures = matchedPrefectures(tagQuery)
        var dialects = direct.map(TagSuggestion.dialect)
        var listed = Set(direct.map(\.id))
        for prefecture in prefectures {
            for record in catalogue.dialects(in: prefecture) where available(record) && !listed.contains(record.id) {
                dialects.append(.dialect(record))
                listed.insert(record.id)
            }
            dialects.append(.prefecture(prefecture))
        }

        let existingCustom = Set(customTags.map { Self.plainKey($0.name) })
        let ideaSuggestions = ideas
            .filter { !existingCustom.contains(Self.plainKey($0.0)) }
            .compactMap { idea -> (rank: Int, suggestion: TagSuggestion)? in
                guard let rank = Self.rank(plainQuery, primary: [Self.plainKey(idea.0)], aliases: []) else { return nil }
                return (rank, .customIdea(name: idea.0, color: idea.1))
            }
            .sorted { $0.rank < $1.rank }
            .map(\.suggestion)

        let create: [TagSuggestion] = isDuplicate || trimmed.isEmpty ? [] : [
            .createCustom(trimmed), .createDialect(trimmed, preselected: prefectures.first),
        ]
        return TagSuggestions(
            yours: mine.map(\.suggestion), dialects: dialects, ideas: ideaSuggestions,
            create: create, isDuplicate: isDuplicate
        )
    }

    /// What the field shows while empty: recently used tags, then catalogue dialects
    /// near the user's dialect tags (the entry's own, or all of them when it has none):
    /// same prefecture first, then the rest of the region.
    public func related(
        to dialectTags: [DialectTagValue], recent: [UUID],
        allDialectTags: [DialectTagValue], allCustomTags: [CustomTagValue]
    ) -> [TagSuggestion] {
        let applied = Set(dialectTags.map(\.id))
        var result: [TagSuggestion] = []
        for id in recent where !applied.contains(id) {
            if let tag = allDialectTags.first(where: { $0.id == id }) {
                result.append(.existingDialect(tag))
            } else if let tag = allCustomTags.first(where: { $0.id == id }) {
                result.append(.existingCustom(tag))
            }
        }

        let basis = dialectTags.isEmpty ? allDialectTags : dialectTags
        let prefectures = Set(basis.flatMap(\.prefectures))
        let regions = Set(basis.map(\.region))
        let created = Set(allDialectTags.compactMap(\.catalogueID))
        let takenNames = Set(allDialectTags.map { JapaneseNormalizer.tagKey($0.name) })
        let candidates = catalogue.dialects.filter {
            !created.contains($0.id) && !takenNames.contains(JapaneseNormalizer.tagKey($0.name))
        }
        let samePrefecture = candidates.filter { !prefectures.isDisjoint(with: $0.prefectures) }
        let sameRegion = candidates.filter { regions.contains($0.region) && prefectures.isDisjoint(with: $0.prefectures) }
        result += (samePrefecture + sameRegion).map(TagSuggestion.dialect)
        return result
    }

    // MARK: - Matching

    /// 0 exact, 1 prefix, 2 alias prefix, 3 contains (only for two or more
    /// characters, so a single kana doesn't match half the catalogue); nil for no match.
    private static func rank(_ query: String, primary: [String], aliases: [String]) -> Int? {
        guard !query.isEmpty else { return nil }
        let primary = primary.filter { !$0.isEmpty }
        let aliases = aliases.filter { !$0.isEmpty }
        if primary.contains(query) || aliases.contains(query) { return 0 }
        if primary.contains(where: { $0.hasPrefix(query) }) { return 1 }
        if aliases.contains(where: { $0.hasPrefix(query) }) { return 2 }
        if query.count >= 2, (primary + aliases).contains(where: { $0.contains(query) }) { return 3 }
        return nil
    }

    private static func recordKeys(_ record: DialectRecord) -> [String] {
        [record.name, record.kana, record.romaji].map(JapaneseNormalizer.tagKey)
    }

    private func dialectKeys(_ tag: DialectTagValue) -> [String] {
        [tag.name, tag.romaji].compactMap { $0 }.map(JapaneseNormalizer.tagKey)
    }

    /// A tag made from the catalogue also answers to its record's kana and aliases.
    private func recordAliasKeys(_ tag: DialectTagValue) -> [String] {
        guard let id = tag.catalogueID, let record = catalogue.dialects.first(where: { $0.id == id }) else { return [] }
        return ([record.kana, record.romaji] + record.aliases).map(JapaneseNormalizer.tagKey)
    }

    /// Prefectures whose name, kana or romaji the query is, or starts.
    private func matchedPrefectures(_ query: String) -> [Prefecture] {
        guard !query.isEmpty else { return [] }
        return Prefecture.allCases.filter { prefecture in
            [prefecture.name, prefecture.kana, prefecture.romaji]
                .map(JapaneseNormalizer.tagKey)
                .contains { $0.hasPrefix(query) }
        }
    }

    /// `key` without spaces and hyphens: how custom tag names compare.
    private static func plainKey(_ text: String) -> String {
        JapaneseNormalizer.key(text).filter { $0 != " " && $0 != "-" }
    }
}
