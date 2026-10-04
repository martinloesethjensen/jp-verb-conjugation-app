# Word Bank Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship milestone 1 of the Word Bank: a third tab where the user collects their own Japanese (dialect words, phrases, sentences) with structured dialect tags and custom tags (with suggestions), nested folders, a detail page and editor, and ranked search with tokens, chips, folder scopes, match explanations and recent searches.

**Architecture:** All logic lives in VerbKit under `WordBank/` and is unit-tested without UI: value types (`WordBankEntryValue`, `Sense`, `StandardEquivalent`, tag and folder values), a shared `JapaneseNormalizer`, the bundled `DialectCatalogue` (`Resources/dialects.json`), `TagSuggester`, the folder tree rules, and `WordBankSearch` (matching, ranking, explanations, tokens). SwiftData entities (`WordBankEntryEntity`, `WordBankFolderEntity`, `DialectTagEntity`, `CustomTagEntity`) live in a **separate `ModelConfiguration` and file (`WordBank.sqlite`)** in the existing App Group container, wrapped by `WordBankPersisting` / `SwiftDataWordBankPersisting` and an `@Observable WordBankStore`, following `QuizHistoryStore`. The App gets a `Word Bank` tab in `MainTabView` with list, folder, detail, editor, tag picker and tag manager views.

**Tech Stack:** Swift 5 mode, SwiftUI (iOS 26 / macOS 26), SwiftData, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-03-word-bank-design.md` (milestone 1 "Core"; read "Dependencies on open PRs").

**Base:** `main`. PR #16's foundations are merged there (2026-10-04): use its `WordClass` (`Models/WordClass.swift`), `Word`, `FormID`, `FormCatalogue`. PRs #18 (`FuriganaDictionary.reading(of:)`) and #24 (`SpotlightIndexer`, `App/Intents/`) are merged too.

## Global Constraints

- Package tests: `swift test --package-path Packages/VerbKit`; every existing test stays green (count them before Task 1 and record the number in the Task 1 commit message body). Data check `python3 scripts/update_data.py --check` must stay "data is up to date" (no data changes in this plan).
- After adding files run `xcodegen generate`. iOS build: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build-dd build` (add `,OS=<version>` or use `id=<simulator UDID>` when several runtimes have a device of that name); macOS: `-scheme JPVerbConjugation_macOS -destination 'platform=macOS' -derivedDataPath .build-dd-mac CODE_SIGNING_ALLOWED=NO`. iOS-only SwiftUI APIs behind `#if os(iOS)`. Never commit `.build-dd*/` or PNGs; `git add` explicit paths.
- **Naming:** every new type is `WordBank…`, `DialectTag…`, `CustomTag…`, `Sense`, `StandardEquivalent`, `EntryKind`, `TagSuggester`, `JapaneseNormalizer`, `DialectCatalogue`. Never a bare `Word…` (that is #16's curated model). SwiftData classes end in `Entity`; the plain value types the UI and tests use do not. App Intents entities (milestone 7) end in `AppEntity`, so they never share a name with a VerbKit SwiftData class.
- **CloudKit-ready models:** no `@Attribute(.unique)`; every stored property optional or defaulted; every relationship optional with an explicit inverse; identity is a `UUID` `id` property. `Codable` value arrays (`[Sense]`, `[StandardEquivalent]`) are stored as JSON `Data` with a computed accessor, like `VerbEntity.formsData`.
- **Separate store:** Word Bank entities are only in the `WordBank.sqlite` configuration; the existing schema list and `VerbKit.sqlite` file are unchanged. Nothing in verb/grammar/furigana sync may touch the Word Bank store (test in Task 2).
- **Entry fields (Core):** `id`, `text` (required, non-blank after trimming), `reading?`, `kanjiSpelling?`, `kind: EntryKind` (`word`, `phrase`, `sentence`; default `word`), `wordClass: WordClass?` (only meaningful for `word`), `senses: [Sense]` (`meaning`, `note?`), `equivalents: [StandardEquivalent]` (`written`, `reading?`, `note?`), `linkedWordID: String?` and `linkedFormID: String?` (stored now, no UI until milestone 4), `notes?` (source/notes), `folder`, `dialectTags`, `customTags`, `createdAt`, `updatedAt`.
- **Tags:** `DialectTag` = `id`, `name` (kanji, e.g. 熊本弁), `romaji?`, `prefectures: [Prefecture]`, `region: Region`, `catalogueID: String?`. `CustomTag` = `id`, `name`, `colorName` (one of a fixed palette of 8 names). The tag list starts empty; nothing is seeded.
- **Folders:** nested via `parent`; each entry in at most one folder; sibling names unique under `JapaneseNormalizer.key` comparison; moving a folder into itself or a descendant is rejected; delete with `.keepContents` (entries and subfolders move to the parent, or to root/Unfiled) or `.deleteContents` (recursive). Model relationships use `.nullify`, never `.cascade`; the store does deletion explicitly.
- **Normalisation (`JapaneseNormalizer.key`)**: NFKC; katakana → hiragana (ァ–ヶ → ぁ–ゖ); Latin lowercased with diacritics folded (ō → o); whitespace trimmed and inner runs collapsed to one space. `looseKey` additionally removes ー and folds long vowels (おお/おう → お, うう → う, いい → い, ええ/えい → え, ああ → あ). Tag-name normalisation (`tagKey`) is `key` without spaces, hyphens and the suffixes 弁 / べん / ben / 方言 / ことば / 言葉, and with romaji converted through `Romaji.toHiragana` when the text is Latin.
- **Search fields and weights:** text 100; reading 90; kanji spelling 90; equivalent written/reading 80; sense meaning 70; tag names 50; sense note 30; folder name 20; notes 10. Match quality multipliers: exact 1.0, prefix 0.8, word-prefix 0.6, contains 0.4, loose fallback 0.25. Entry score = sum over query words of that word's best (weight × quality); every word must match (AND). Ties: `updatedAt` descending, then `id`.
- **Tokens:** `.dialectTag(UUID)`, `.region(Region)`, `.prefecture(Prefecture)`, `.customTag(UUID)`, `.folder(UUID)` (includes descendants), `.kind(EntryKind)`, `.wordClass(WordClass)`, `.unfiled`, `.noDialectTag`. All tokens AND together.
- **Recent searches:** last 10, newest first, deduplicated (same text after `key` and same token set), stored in standard `UserDefaults` (not the App Group) under `wordBank.recentSearches` as JSON.
- Commit messages end with the session's `Co-Authored-By` / `Claude-Session` lines; no model names in code or commits.
- The app has no UI test target; UI tasks are verified by builds and simulator checks (report what you saw and what you could not check).

---

### Task 1: Value types, regions and the normaliser

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankValues.swift` (`EntryKind`, `Sense`, `StandardEquivalent`, `WordBankEntryValue`, `DialectTagValue`, `CustomTagValue`, `WordBankFolderValue`, `CustomTagColor`)
- Create: `.../WordBank/Region.swift` (`Region`, `Prefecture` with all 47, each prefecture's region, kanji/kana/romaji names)
- Create: `.../WordBank/JapaneseNormalizer.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/JapaneseNormalizerTests.swift`, `.../RegionTests.swift`

**Interfaces:**

```swift
public enum EntryKind: String, Codable, CaseIterable, Sendable { case word, phrase, sentence }
public struct Sense: Codable, Hashable, Sendable { public var meaning: String; public var note: String? }
public struct StandardEquivalent: Codable, Hashable, Sendable { public var written: String; public var reading: String?; public var note: String? }
public enum Region: String, Codable, CaseIterable, Sendable { case hokkaido, tohoku, kanto, chubu, kansai, chugoku, shikoku, kyushuOkinawa
    public var name: String /* 北海道 … 九州・沖縄 */; public var romaji: String; public var prefectures: [Prefecture] }
public enum Prefecture: String, Codable, CaseIterable, Sendable { case hokkaido, aomori, … , okinawa   // 47, JIS order
    public var name: String /* 熊本県 */; public var kana: String; public var romaji: String; public var region: Region }
public struct WordBankEntryValue: Identifiable, Hashable, Sendable { public var id: UUID; public var text: String; public var reading: String?
    public var kanjiSpelling: String?; public var kind: EntryKind; public var wordClass: WordClass?; public var senses: [Sense]
    public var equivalents: [StandardEquivalent]; public var linkedWordID: String?; public var linkedFormID: String?; public var notes: String?
    public var folderID: UUID?; public var dialectTagIDs: [UUID]; public var customTagIDs: [UUID]; public var createdAt: Date; public var updatedAt: Date }
public struct DialectTagValue: Identifiable, Hashable, Sendable { public var id: UUID; public var name: String; public var romaji: String?
    public var prefectures: [Prefecture]; public var region: Region; public var catalogueID: String? }
public enum CustomTagColor: String, Codable, CaseIterable, Sendable { case red, orange, yellow, green, teal, blue, purple, gray }
public struct CustomTagValue: Identifiable, Hashable, Sendable { public var id: UUID; public var name: String; public var color: CustomTagColor }
public struct WordBankFolderValue: Identifiable, Hashable, Sendable { public var id: UUID; public var name: String; public var parentID: UUID?; public var sortOrder: Int }
public enum JapaneseNormalizer {
    public static func key(_ text: String) -> String
    public static func looseKey(_ text: String) -> String
    public static func tagKey(_ text: String) -> String
    /// Kana for a Latin query via `Romaji.toHiragana`, else nil.
    public static func kanaForm(_ text: String) -> String?
}
```

- [ ] **Step 1: Failing tests.** Normaliser: full-width "ＡＢＣ" and half-width "ｶﾀｶﾅ" fold; カタカナ → かたかな; "Ōsaka" → "osaka"; whitespace collapse; `looseKey("おおきに") == looseKey("おきに")`, `looseKey("コーヒー") == looseKey("こひ")`; dakuten are NOT folded (`key("が") != key("か")`); `tagKey`: "Osaka-ben", "osaka ben", "OSAKA" and "おおさかべん" share one key (romaji goes through `Romaji`, the suffix is dropped), and "大阪弁" and "大阪" share another (kanji is not converted to kana; the dialect catalogue's kana and aliases bridge the two in Task 3); `kanaForm("ookini") == "おおきに"`, `kanaForm("おおきに") == nil`. Regions: 47 prefectures, each in exactly one region, every region non-empty, `Prefecture.gifu.region == .chubu`, `.kumamoto.region == .kyushuOkinawa`, names unique.
- [ ] **Step 2: Run** `swift test --package-path Packages/VerbKit --filter "JapaneseNormalizerTests|RegionTests"` (FAIL), **Step 3: implement**, **Step 4: run** filtered then the whole suite (green).
- [ ] **Step 5: Commit** `git add Packages/VerbKit && git commit -m "Word Bank value types, regions and the Japanese normaliser"`.

---

### Task 2: SwiftData entities, the separate store and persistence

**Files:**
- Create: `.../Persistence/WordBankEntities.swift` (`WordBankEntryEntity`, `WordBankFolderEntity`, `DialectTagEntity`, `CustomTagEntity`)
- Create: `.../Persistence/WordBankPersisting.swift`, `.../Persistence/SwiftDataWordBankPersisting.swift`
- Modify: `.../Persistence/VerbModelContainer.swift` (second configuration)
- Test: `.../SwiftDataWordBankPersistingTests.swift`, `.../VerbModelContainerTests.swift` (new)

**Interfaces:**

```swift
public enum VerbModelContainer {
    public static let wordBankSchema: Schema           // the four Word Bank entities
    public static func make() throws -> ModelContainer // now two configurations: VerbKit.sqlite (unchanged list) + WordBank.sqlite
    public static func makeInMemory() throws -> ModelContainer  // both configurations in memory
}
public struct WordBankSnapshot: Equatable, Sendable { public var entries: [WordBankEntryValue]; public var folders: [WordBankFolderValue]
    public var dialectTags: [DialectTagValue]; public var customTags: [CustomTagValue] }
@MainActor public protocol WordBankPersisting {
    func load() throws -> WordBankSnapshot
    func upsert(entry: WordBankEntryValue) throws
    func delete(entryIDs: [UUID]) throws
    func upsert(folder: WordBankFolderValue) throws
    func delete(folderIDs: [UUID]) throws          // folders only; contents already moved/deleted by the caller
    func upsert(dialectTag: DialectTagValue) throws
    func upsert(customTag: CustomTagValue) throws
    func delete(dialectTagIDs: [UUID], customTagIDs: [UUID]) throws
}
@MainActor public final class SwiftDataWordBankPersisting: WordBankPersisting { public init(modelContext: ModelContext) }
```

Configuration: `ModelConfiguration("WordBank", schema: wordBankSchema, url: groupURL/WordBank.sqlite)` next to the existing one (give the existing one an explicit name and its existing schema list, unchanged). Both go into one `ModelContainer(for: Schema(existing + wordBank), configurations: [verbs, wordBank])`. The widget's `VerbModelContainer.make()` calls keep working.

- [ ] **Step 1: Failing tests.** Round trip every field of an entry (including senses/equivalents arrays, word class, linked ids, nil optionals) through `upsert` + `load`; tags and folder relationships restore as ids; updating an entry replaces its tag sets; deleting a tag removes it from entries (nullify) without deleting entries; deleting a folder row leaves its entries with `folderID == nil`; a corrupted senses `Data` loads as `[]` instead of throwing. Container test: `makeInMemory()` can save a `VerbEntity` and a `WordBankEntryEntity` in one context, and `SwiftDataVerbPersisting.replaceAllVerbs(with:)` (what the verb sync uses to rewrite rows) leaves Word Bank rows intact. On-disk check (in the same test file, using a temp directory variant `make(directory:)` added as `internal` for tests): the two configurations write two different files and the Word Bank file name is `WordBank.sqlite`.
- [ ] **Step 2: Run** filtered (FAIL). **Step 3: Implement.** Entities store enums as raw strings (`kindRaw`, `wordClassRaw`, `regionRaw`, `prefecturesRaw` comma-joined, `colorRaw`) with defaults; unknown raw values map to defaults on load. **Step 4: Run** filtered, whole suite; build iOS and macOS (app and widget open the container).
- [ ] **Step 5: Commit** `"Word Bank SwiftData entities in their own store file"`.

---

### Task 3: Dialect catalogue and tag suggestions

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Resources/dialects.json`, `.../WordBank/DialectCatalogue.swift`, `.../WordBank/TagSuggester.swift`
- Modify: `Packages/VerbKit/Package.swift` (`resources: [.copy("Resources/forms.json"), .copy("Resources/dialects.json")]`)
- Test: `.../DialectCatalogueTests.swift`, `.../TagSuggesterTests.swift`

**Interfaces:**

```swift
public struct DialectRecord: Codable, Hashable, Identifiable, Sendable { public var id: String; public var name: String; public var kana: String
    public var romaji: String; public var aliases: [String]; public var prefectures: [Prefecture]; public var region: Region }
public struct DialectCatalogue: Sendable { public let dialects: [DialectRecord]
    public init(data: Data) throws; public static let bundled: DialectCatalogue   // like FormCatalogue.bundled
    public func dialects(in prefecture: Prefecture) -> [DialectRecord]; public func dialects(in region: Region) -> [DialectRecord] }
public enum TagSuggestion: Hashable, Sendable {
    case existingDialect(DialectTagValue), existingCustom(CustomTagValue)
    case dialect(DialectRecord), prefecture(Prefecture), customIdea(name: String, color: CustomTagColor)
    case createCustom(String), createDialect(String, preselected: Prefecture?)
}
public struct TagSuggestions: Equatable, Sendable { public var yours: [TagSuggestion]; public var dialects: [TagSuggestion]
    public var ideas: [TagSuggestion]; public var create: [TagSuggestion]; public var isDuplicate: Bool }
public struct TagSuggester: Sendable {
    public init(catalogue: DialectCatalogue = .bundled, ideas: [(String, CustomTagColor)] = TagSuggester.defaultIdeas)
    public func suggestions(for query: String, dialectTags: [DialectTagValue], customTags: [CustomTagValue], excluding applied: Set<UUID>) -> TagSuggestions
    public func related(to dialectTags: [DialectTagValue], recent: [UUID], allDialectTags: [DialectTagValue], allCustomTags: [CustomTagValue]) -> [TagSuggestion]  // empty-field state
}
```

`dialects.json`: `{"schema": 1, "dialects": [...]}`; at least one record per prefecture (the prefecture's main dialect, e.g. `kumamoto-ben`), plus the well-known ones named in the spec (大阪弁, 京都弁, 神戸弁, 河内弁, 博多弁, 名古屋弁, 津軽弁, 沖縄方言, 飛騨弁 with alias 高山弁, 美濃弁, 関西弁 (all Kansai prefectures, region kansai), 東北弁 (all Tohoku prefectures)). Romaji in the `-ben` form ("Kumamoto-ben"). Ids are stable kebab-case.

Ranking inside each section: `tagKey` exact > prefix > alias prefix > contains; then catalogue order. "Dialects" for a prefecture-name query lists that prefecture's dialects then `.prefecture(p)`. `isDuplicate` when the query's `tagKey` equals an existing tag's `tagKey` (then `create` is empty). Already-applied tags and already-created catalogue ids are excluded from `dialects`.

- [ ] **Step 1: Failing tests.** Catalogue decodes; ids unique; every prefecture has ≥ 1 record; every record's region matches its prefectures' region (multi-prefecture records may span exactly one region); 飛騨弁 has alias 高山弁 and prefecture gifu. Suggester: "takayama" → 飛騨弁 first in dialects; "kuma" → 熊本弁; "gifu" → 飛騨弁, 美濃弁, then `.prefecture(.gifu)`; "osaka", "おおさか", "Osaka-ben", "大阪弁" each find 大阪弁; existing 関西弁 tag + "kansai" → in `yours`, not in `dialects`; exact duplicate sets `isDuplicate` and no create option; "food" → idea with its color, plus create; empty query + existing 大阪弁 → related gives 京都弁/神戸弁/河内弁 before other Kansai and before other regions, recent tags first; applied tags excluded.
- [ ] **Steps 2–4:** run (FAIL), implement, run filtered + whole suite. **Step 5: Commit** `"Bundled dialect catalogue and tag suggestions"`.

---

### Task 4: Folder rules and the Word Bank store

**Files:**
- Create: `.../WordBank/FolderTree.swift`, `.../Store/WordBankStore.swift`
- Test: `.../FolderTreeTests.swift`, `.../WordBankStoreTests.swift` (with an in-memory `WordBankPersisting` double, like `QuizHistoryStoreTests`)

**Interfaces:**

```swift
public struct FolderTree: Sendable {
    public init(_ folders: [WordBankFolderValue])
    public func children(of id: UUID?) -> [WordBankFolderValue]        // sorted by sortOrder, then name key
    public func descendants(of id: UUID) -> Set<UUID>                    // not including id
    public func path(of id: UUID) -> [WordBankFolderValue]                // root first
    public func canMove(_ id: UUID, to parent: UUID?) -> Bool
    public func nameIsFree(_ name: String, in parent: UUID?, ignoring: UUID? = nil) -> Bool
}
public enum FolderDeletion: Sendable { case keepContents, deleteContents }
public enum WordBankError: Error, Equatable { case blankText, duplicateFolderName, invalidMove, duplicateTagName }
@MainActor @Observable public final class WordBankStore {
    public private(set) var entries: [WordBankEntryValue]; public private(set) var folders: [WordBankFolderValue]
    public private(set) var dialectTags: [DialectTagValue]; public private(set) var customTags: [CustomTagValue]
    public private(set) var lastError: WordBankError?
    public init(persisting: WordBankPersisting, now: @escaping () -> Date = Date.init)
    public var tree: FolderTree { get }
    @discardableResult public func save(_ entry: WordBankEntryValue) throws -> WordBankEntryValue   // trims, validates, sets createdAt/updatedAt
    public func delete(entryIDs: [UUID])
    public func move(entryIDs: [UUID], to folder: UUID?)
    @discardableResult public func createFolder(named: String, in parent: UUID?) throws -> WordBankFolderValue
    public func rename(folder: UUID, to name: String) throws
    public func move(folder: UUID, to parent: UUID?) throws
    public func delete(folder: UUID, _ mode: FolderDeletion)
    @discardableResult public func createDialectTag(_ tag: DialectTagValue) throws -> DialectTagValue
    @discardableResult public func createDialectTag(from record: DialectRecord) throws -> DialectTagValue
    @discardableResult public func createCustomTag(named: String, color: CustomTagColor) throws -> CustomTagValue
    public func update(dialectTag: DialectTagValue) throws; public func update(customTag: CustomTagValue) throws
    public func delete(dialectTag: UUID); public func delete(customTag: UUID)
    public func entries(sharingEquivalentWith entry: WordBankEntryValue) -> [WordBankEntryValue]   // groundwork for milestone 4; tested now
    public func entryWithSameText(as text: String, excluding: UUID?) -> WordBankEntryValue?
}
```

- [ ] **Step 1: Failing tests.** FolderTree: children order; path; descendants; cannot move into self/descendant; can move to root; sibling-name check is normalised ("Kansai" vs "ｋａｎｓａｉ") and ignores the folder itself on rename. Store: save rejects blank text; save sets `createdAt` on first save and only bumps `updatedAt` when something changed; senses/equivalents with blank text are dropped on save; delete; move entries; folder create/rename duplicate errors; keep-contents deletion moves entries and subfolders to the parent (root when top-level); delete-contents removes every descendant folder and entry; deleting a tag removes it from entries in memory too; `createDialectTag(from:)` copies name/romaji/prefectures/region/catalogueID and refuses a second tag with the same catalogue id or `tagKey`; `entries(sharingEquivalentWith:)` matches by `key` of written or reading and excludes the entry itself; `entryWithSameText` uses `key`; a throwing persister leaves memory updated and sets `lastError`.
- [ ] **Steps 2–4**, **Step 5: Commit** `"Folder rules and the WordBankStore"`.

---

### Task 5: Search engine, tokens and recent searches

**Files:**
- Create: `.../Search/WordBankSearch.swift`, `.../WordBank/RecentSearches.swift`, `.../WordBank/KanjiExtraction.swift`
- Modify: `.../Lookup/TextLookupURL.swift` (`jishoKanji`)
- Test: `.../WordBankSearchTests.swift`, `.../RecentSearchesTests.swift`, `.../KanjiExtractionTests.swift`, `.../TextLookupURLTests.swift` (append)

**Interfaces:**

```swift
public enum WordBankToken: Hashable, Codable, Sendable { case dialectTag(UUID), region(Region), prefecture(Prefecture), customTag(UUID),
    folder(UUID), kind(EntryKind), wordClass(WordClass), unfiled, noDialectTag }
public enum WordBankField: String, Sendable { case text, reading, kanjiSpelling, equivalent, sense, tag, senseNote, folder, notes }
public struct WordBankMatch: Identifiable, Sendable { public var entry: WordBankEntryValue; public var score: Double
    public var explanation: (field: WordBankField, snippet: String, range: Range<String.Index>)?   // nil when the match is in `text`
    public var id: UUID { entry.id } }
public struct WordBankSearchIndex: Sendable {       // cached per entry by the store; rebuilt when an entry changes
    public init(entries: [WordBankEntryValue], folders: [WordBankFolderValue], dialectTags: [DialectTagValue], customTags: [CustomTagValue],
                derivedReading: (String) -> String? = { _ in nil })   // the app passes FuriganaDictionary.reading(of:) (PR #18, merged)
}
public struct WordBankQuery: Hashable, Codable, Sendable { public var text: String; public var tokens: [WordBankToken]; public var scopeFolder: UUID? }
public extension WordBankSearchIndex {
    func search(_ query: WordBankQuery) -> [WordBankMatch]             // ranked when text non-empty; else filter only, score 0, original order
    func count(_ query: WordBankQuery) -> Int
    func suggestedTokens(for fragment: String, excluding: [WordBankToken]) -> [WordBankToken]   // only tokens with ≥ 1 result
    func relaxations(of query: WordBankQuery) -> [(dropping: WordBankToken?, widenScope: Bool, count: Int)]   // no-results helpers, counts > 0 only
}
public struct RecentSearches: Sendable { public static let defaultsKey = "wordBank.recentSearches"
    public init(rawValue: Data?); public var rawValue: Data; public private(set) var items: [WordBankQuery]
    public mutating func record(_ query: WordBankQuery); public mutating func remove(_ query: WordBankQuery); public mutating func clear() }
public enum KanjiExtraction { public static func kanji(in texts: [String]) -> [Character] }   // distinct, first-seen order, uses FuriganaDictionary.isKanji
public extension TextLookupURL { static func jishoKanji(_ character: Character) -> URL? }      // https://jisho.org/search/<k>%20%23kanji
```

Matching per Global Constraints: split text on spaces outside double quotes; a quoted part is one word matched as a whole phrase; for each word try `key` on each field, plus `kanaForm` against Japanese fields (text, reading, kanji spelling, equivalents) when Latin, plus `looseKey` fallback when the strict pass found nothing for that word in that entry. The snippet is the field value (for notes, ±20 characters around the match with "…").

- [ ] **Step 1: Failing tests** (build a fixture bank of ~12 entries: おおきに/関西弁/"thank you"/eq ありがとう; なおす with sense note "≠ standard 直す"; だんだん/出雲弁/eq ありがとう; めんこい/eq 可愛い(かわいい); a phrase in a folder Trip › Takayama; one with notes "from Yuki at the izakaya"; etc.): "ookini", "おおきに", "オオキニ", "thank you" find おおきに first; "okini" finds おおきに via loose fallback, ranked below an exact match for another entry if one exists; "ありがとう" finds both おおきに and だんだん with explanation field `.equivalent`; "yuki izakaya" (two words AND) finds the notes entry with a notes snippet containing "…"; quoted "thank you" doesn't match "thank … you" split across fields; "kansai" text matches entries tagged 関西弁 with `.tag` explanation; tokens: dialect, region (九州 matches 熊本弁 and 博多弁 entries), prefecture, custom tag, folder includes subfolders, kind, word class, unfiled, noDialectTag, combined AND; `scopeFolder` limits to that subtree; ranking order checks for exact > prefix > contains and field weights; ties by `updatedAt`; empty text keeps original order; `suggestedTokens("kuma")` returns the 熊本弁 token only if an entry has it, `("taka")` returns the Takayama folder; `relaxations` reports "drop 熊本弁 → 3" and "widen scope → n"; `derivedReading` lets "atama" find 頭; performance: 5,000 generated entries, `measure(metrics: [XCTClockMetric()]) { _ = index.search(...) }` with a 10-character query, plus a plain assertion that one search takes under 0.1 s in the (debug) test build; the spec's 16 ms target is for release builds, so record the measured debug number in the commit message and check release timing on the simulator in Task 10. RecentSearches: cap 10, newest first, dedupe moves to top, remove, clear, corrupt data → empty. KanjiExtraction: distinct, ordered, kana ignored. `jishoKanji("大")` percent-encodes and contains `%23kanji`.
- [ ] **Steps 2–4**, **Step 5: Commit** `"Word Bank search: ranking, tokens, explanations and recent searches"`.

---

### Task 6: App wiring and the tab shell

**Files:**
- Modify: `App/JPVerbConjugationApp.swift` (create and inject `WordBankStore` from the same `ModelContext`; macOS Settings scene too), `App/MainTabView.swift` (`AppTab.wordBank`, third `Tab("Word Bank", systemImage: "books.vertical", …)`)
- Create: `App/WordBank/WordBankTab.swift` (its `NavigationSplitView`, selection state, preferred column like `GrammarTab`)

- [ ] **Step 1:** Wire the store; the tab shows an empty list with `ContentUnavailableView("Your Word Bank is empty", systemImage: "books.vertical", description: Text("Save dialect words, phrases and sentences you learn outside the app."))` and an "Add your first entry" button (no-op until Task 8). Detail column placeholder `ContentUnavailableView("Select an Entry", systemImage: "books.vertical")`.
- [ ] **Step 2:** `xcodegen generate`; build iOS and macOS; on the simulator check the three tabs, switching keeps each tab's state, and the sidebar on iPad/macOS shows Word Bank (macOS: build only if no Mac session).
- [ ] **Step 3: Commit** `"Word Bank tab shell"`.

---

### Task 7: List, folders and moving

**Files:**
- Create: `App/WordBank/WordBankListView.swift` (root and folder screens share it via a `folderID: UUID?` parameter), `App/WordBank/WordBankRow.swift`, `App/WordBank/FolderPicker.swift`, `App/WordBank/FolderActions.swift` (new/rename sheets, delete dialog)

- [ ] **Step 1: Root and folder screens.** Root: smart rows **All entries**, **Unfiled**, **Recently added** (last 30 days, newest first), then top-level folders, then unfiled entries. Folder: subfolders, then entries; navigation subtitle = folder path joined with " › ". Grouping/sort menu chip (by region › dialect with "Untagged" last, by date added, A–Z by reading-or-text `key`). Row: `JapaneseText(text)` (furigana from the global dictionary), first equivalent, first sense, up to three tag pills (dialect tags first). Toolbar: **＋** menu (New entry, New folder) and **⋯** (Manage tags, Settings, Report a problem; Review/Import/Export arrive in later milestones and are not shown).
- [ ] **Step 2: Folder actions.** New folder (sheet with name field; inline error for a duplicate name); context menu Rename, Move to…, Delete (confirmation dialog: "Keep entries" default, "Delete folder and N entries" destructive). Entries: swipe Delete, context menu Move to…, edit mode multi-select with a Move toolbar button. `FolderPicker` is a tree list that disables the folder itself and its descendants when moving a folder. iPad/macOS: `.draggable` entry/folder ids and `.dropDestination` on folder rows, using `canMove`.
- [ ] **Step 3: Build** both platforms; simulator: create nested folders, rename to a duplicate (error shown), move entries and folders (invalid targets disabled), delete with both modes, check counts and Unfiled. **Step 4: Commit** `"Word Bank list, folders and moving"`.

---

### Task 8: Editor, tag picker and tag manager

**Files:**
- Create: `App/WordBank/WordBankEditor.swift`, `App/WordBank/TagPicker.swift`, `App/WordBank/NewDialectTagSheet.swift`, `App/WordBank/TagManagerView.swift`, `App/WordBank/TagPill.swift`

- [ ] **Step 1: Editor** (sheet with its own `NavigationStack`, Cancel/Save): Text (required; Save disabled while blank), Reading, Standard equivalents (repeating rows: written, reading, note; ＋/delete), Meanings (repeating: meaning, note), Kind (segmented), Word class (menu, shown only for Kind = word, "None" allowed), Folder (`FolderPicker`, pre-selected to the folder the editor was opened from), Tags (`TagPicker`), Kanji spelling, Notes/source (multi-line). When Text matches another entry (`entryWithSameText`), show an inline banner "You already have おおきに" with an **Open** button that cancels and selects that entry. Reading pre-fill from `FuriganaDictionary.reading(of:)` (PR #18, merged): when Text has kanji and Reading is empty, fill Reading for the user to confirm.
- [ ] **Step 2: TagPicker:** applied tags as removable pills; a "New tag…" field. Empty field: **Recently used** then **Related dialects** (`TagSuggester.related`). Typing: sections **Already yours**, **Dialects**, **Ideas**, **Create "…"** from `TagSuggester.suggestions`; picking a catalogue dialect calls `createDialectTag(from:)` and applies it; "Dialect…" opens `NewDialectTagSheet` (name, romaji, prefecture picker grouped by region with the region auto-set, pre-selected from the query); duplicate shows "Already exists" and no create row. Recently used tag ids are kept in `UserDefaults` (`wordBank.recentTags`, last 8).
- [ ] **Step 3: TagManagerView** (from ⋯ › Manage tags): Dialect tags grouped by region with entry counts; Custom tags with color dot and counts; add (same suggestion field), rename (duplicate check), edit prefecture/region or color, delete with "Removes the tag from N entries" confirmation.
- [ ] **Step 4: Build** both platforms; simulator: add おおきに with equivalent ありがとう, sense "thank you", tag via "osaka" suggestion; add a custom tag from an idea; try a duplicate tag; create 高山弁 via "takayama"; create a manual dialect tag for a prefecture; check related suggestions after having 大阪弁. **Step 5: Commit** `"Word Bank editor, tag picker with suggestions and tag manager"`.

---

### Task 9: Detail page

**Files:**
- Create: `App/WordBank/WordBankDetailView.swift`, `App/WordBank/KanjiChips.swift`

- [ ] **Step 1:** Header: `JapaneseText(text)` large, reading underneath when the furigana dictionary can't show it (kana-only text with a user reading is shown plain), `SpeakButton(text:)` with caption "Standard pronunciation" (`.caption`, secondary), `.textActions` / translatable text actions for `kind == .sentence`. **Comparison card** "方言 → 標準語" with one row per equivalent (`JapaneseText`, reading, note, text actions); hidden when there are none. **Meanings**: numbered senses with notes. **Kanji**: `KanjiChips` from `KanjiExtraction.kanji(in: [text, kanjiSpelling] + equivalents.written)`, each a button opening `TextLookupURL.jishoKanji` via `openURL`; hidden when empty. **Tags** (pills), **Folder** (path; tapping navigates to the folder), **Notes**, dates ("Added 3 Oct 2026 · Edited …"). Toolbar: Edit (opens the editor), ⋯ Move to…, Delete (confirm). Milestone-4 sections (word links, other dialects) are not shown yet.
- [ ] **Step 2: Build** both; simulator: open entries with and without each section, speak, open a kanji chip (Safari opens jisho kanji page), edit and see the page update, delete returns to the list. **Step 3: Commit** `"Word Bank detail page"`.

---

### Task 10: Search UI

**Files:**
- Modify: `App/WordBank/WordBankListView.swift`
- Create: `App/WordBank/WordBankSearchChips.swift`, `App/WordBank/MatchExplanationLabel.swift`, `App/WordBank/RecentSearchesList.swift`

- [ ] **Step 1: Field and tokens.** `inlineSearch` style with `searchable(text:tokens:suggestedTokens:placement:prompt:)` ("Search word bank…"); token views show the tag/folder/kind name with its icon; `suggestedTokens` from `index.suggestedTokens(for: text)`. Picking a suggestion removes the fragment from the text. Folder screens add `searchScopes` (This folder / All entries; default This folder, resets when the field is cleared). The store owns one `WordBankSearchIndex`, rebuilt when its data changes (keep it `@ObservationIgnored` and invalidated by a revision counter so typing doesn't rebuild it).
- [ ] **Step 2: Chips.** `WordBankSearchChips` (Dialect ▾ region › dialect menu, Kind ▾, Tag ▾) under the field like `TeFormFilter`; they add/remove tokens in the same `[WordBankToken]` state, highlighted when active; the navigation subtitle summarises active tokens like `filterSummary`.
- [ ] **Step 3: Results.** Text non-empty → flat ranked list of `WordBankMatch` rows with `MatchExplanationLabel` ("Standard: ありがとう" with the range bold/tinted; VoiceOver label reads the same) and folder path when outside the current folder. Tokens only → normal grouping filtered. No results → `ContentUnavailableView.search(text:)` plus buttons from `relaxations` ("Without 熊本弁 (3)", "Search all entries (5)") and **Add "X" as a new entry** (opens the editor with Text prefilled).
- [ ] **Step 4: Recent searches.** Focused and empty field → `RecentSearchesList` (restore on tap, swipe to remove, Clear). Record on opening a result or on submit.
- [ ] **Step 5: Build** both; simulator: run the search checks from Task 5's fixture by hand (ookini, okini, ありがとう, thank you, kuma token, region token, folder scope, quoted phrase), the no-results actions, recents (record, restore, remove, clear), Dynamic Type at XXL for rows and chips. **Step 6: Commit** `"Word Bank search UI"`.

---

### Task 11: Final checks

- [ ] Whole package suite green; `python3 scripts/update_data.py --check` clean; iOS and macOS builds clean with no new warnings.
- [ ] Simulator pass on a fresh install: empty state → add → tag suggestions → folders → search → detail → delete; then reinstall over an existing install with Word Bank data and confirm entries survive an app update and a verb data re-sync (delete the sync state in Settings or trigger Try Again).
- [ ] Re-read the spec's milestone 1 list and tick each item; anything deferred is listed in the PR description.
- [ ] Commit any fixes; push `claude/word-bank-dialect-tags-xjodqi`.
