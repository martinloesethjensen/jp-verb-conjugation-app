# Word Bank Import / Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship milestone 2 of the Word Bank: a `.wordbank` file format, export (everything, one folder, a selection, search results), an import flow with destination choice and a preview, matching and combining that never overwrites or deletes, automatic backups before every import and restore from Settings.

**Architecture:** All logic is in VerbKit and unit-tested without UI: `WordBankArchive` (the file format, lenient decoding), an export initialiser on it, `WordBankEntryCombiner` (the merge rules), `WordBankChanges` (a set of writes) with an all-or-nothing `WordBankPersisting.apply`, `WordBankImportPlanner` (a pure function from archive + current bank + destination to a preview and the changes), `WordBankBackupStore` (files, last three kept) and `WordBankTransfer` (backs up, then applies). The app adds a `.wordbank` document type, an export sheet (share sheet and Save to Files), an import sheet with preview, opening files from outside the app, and Settings › Word Bank › Restore backup.

**Tech Stack:** Swift 5 mode, SwiftUI (iOS 26 / macOS 26), SwiftData, `UniformTypeIdentifiers`, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-03-word-bank-design.md`, sections "Import and export" and "Starter packs" (packs reuse this plan's archive and planner and come in a later plan, milestone 2b).

**Base:** `main` (milestone 1 merged). Start a branch `claude/word-bank-import-export`. The starter-packs spec lives on `claude/word-bank-starter-packs-spec`; merge it first or the spec edits in Task 8 will conflict.

## Global Constraints

- Package tests: `swift test --package-path Packages/VerbKit`; every existing test stays green (note the count before Task 1). Commit only when the command's **exit code is 0** (not just when a summary line prints). `python3 scripts/update_data.py --check` stays "data is up to date" (no data changes in this plan).
- After adding files run `./scripts/generate-project.sh` (XcodeGen; the xcodeproj is not tracked). iOS build: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=<simulator UDID>' -derivedDataPath <scratch>/dd build`. **iPad and macOS checks are parked:** do not build the macOS scheme or check iPad. iOS-only SwiftUI APIs behind `#if os(iOS)` anyway.
- Naming: new types are `WordBank…`, `ImportDestination`, `WordBankExportScope`. Never a bare `Word…`.
- **Nothing is ever deleted or overwritten by an import.** Only Restore replaces the bank, and it takes a backup first.
- The file format is **lenient on read, strict on write**: only `text` is required per entry, unknown fields are ignored, unknown enum values fall back to defaults, a file with a newer major `version` is refused, files over 20 MB (`20 * 1024 * 1024` bytes) are refused. The writer always writes every field it has.
- Sibling folder names are unique under `JapaneseNormalizer.key`; paths from files are matched segment by segment with that key.
- Tag matching: dialect tags by id, then `catalogueID`, then `JapaneseNormalizer.tagKey(name)`; custom tags by id, then `tagKey(name)`. Unmatched tags are created.
- Entry matching: by id; otherwise by `JapaneseNormalizer.key(text)` plus `key(reading ?? "")`. When the file has no reading, text alone matches only if exactly one local entry has that text; if several do, the imported entry is added as new.
- New folders, tags and entries keep the file's ids when those are unused locally (so a restore reproduces the bank exactly); otherwise they get fresh ids.
- The recent-searches, smart-folder, backup-directory and installed-pack bookkeeping are out of scope here except where a task says so.
- The app has no UI test target; UI tasks are verified by builds and simulator checks. Report what you saw and what you could not check.
- Commit messages end with the trailer the session's attribution reminder gives; PR descriptions end with the reminder's footer.

## File Structure

| File | Responsibility |
|---|---|
| `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankArchive.swift` | The `.wordbank` model, `encoded()`, `decode(_:)`, errors, skipped records |
| `.../WordBank/WordBankExport.swift` | `WordBankExportScope`, `WordBankArchive.init(snapshot:scope:exportedAt:)`, file name suggestion |
| `.../WordBank/WordBankEntryCombiner.swift` | `WordBankEntryValue.trimmed()` and the merge rules |
| `.../WordBank/WordBankChanges.swift` | `WordBankChanges` (upserts, deletes, `applied(to:)`, `replacing`) |
| `.../WordBank/WordBankImportPlanner.swift` | `ImportDestination`, summary, plan, the planner |
| `.../WordBank/WordBankBackupStore.swift` | Backup files, pruning, listing |
| `.../WordBank/WordBankTransfer.swift` | Import with backup, restore |
| `.../Persistence/WordBankPersisting.swift`, `SwiftDataWordBankPersisting.swift` | `apply(_:)` all or nothing |
| `.../Store/WordBankStore.swift` | `snapshot`, `apply(_:)`, uses `trimmed()` |
| `App/WordBank/WordBankFileType.swift` | `UTType.wordBank`, `WordBankFile` document |
| `App/WordBank/WordBankExportSheet.swift` | Scope choice, Share, Save to Files |
| `App/WordBank/WordBankImportSheet.swift` | Destination, preview, Import, errors |
| `App/WordBank/WordBankBackupsView.swift` | Restore list in Settings |
| `project.yml` | Exported type and document type |

---

### Task 1: The archive format

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankArchive.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/WordBankArchiveTests.swift`

**Interfaces:**
- Produces:

```swift
public struct WordBankArchive: Equatable, Sendable {
    public static let formatName = "word-bank"
    public static let currentVersion = 1
    public static let maxBytes = 20 * 1024 * 1024

    public struct Folder: Codable, Equatable, Sendable { public var id: UUID?; public var name: String; public var parentID: UUID? }
    public struct DialectTag: Codable, Equatable, Sendable { public var id: UUID?; public var name: String; public var romaji: String?; public var prefectures: [Prefecture]?; public var region: Region?; public var catalogueID: String? }
    public struct CustomTag: Codable, Equatable, Sendable { public var id: UUID?; public var name: String; public var color: CustomTagColor? }
    public struct SmartFolder: Codable, Equatable, Sendable { public var name: String; public var dialectTagNames: [String]; public var customTagNames: [String]; public var match: SmartFolderMatch }
    public struct Entry: Codable, Equatable, Sendable { /* see step 3 */ }
    public struct Skipped: Equatable, Sendable { public var section: String; public var position: Int; public var reason: String }
    public enum ArchiveError: Error, Equatable, Sendable { case notAWordBank, newerVersion(Int), tooLarge }

    public var exportedAt: Date
    public var folders: [Folder]; public var dialectTags: [DialectTag]; public var customTags: [CustomTag]
    public var smartFolders: [SmartFolder]; public var entries: [Entry]
    public var skipped: [Skipped]          // filled by decode, never written
    public func encoded() throws -> Data
    public static func decode(_ data: Data) throws -> WordBankArchive
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import VerbKit

final class WordBankArchiveTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    func testRoundTripKeepsEverything() throws {
        let folderID = UUID(), tagID = UUID(), entryID = UUID()
        let archive = WordBankArchive(
            exportedAt: date,
            folders: [.init(id: folderID, name: "Trip 2026", parentID: nil)],
            dialectTags: [.init(id: tagID, name: "大阪弁", romaji: "Osaka-ben", prefectures: [.osaka], region: .kansai, catalogueID: "osaka")],
            customTags: [.init(id: UUID(), name: "food", color: .orange)],
            smartFolders: [.init(name: "Kansai", dialectTagNames: ["大阪弁"], customTagNames: [], match: .any)],
            entries: [
                .init(
                    id: entryID, text: "おおきに", reading: "おおきに", kind: .phrase,
                    senses: [Sense(meaning: "thank you", note: "informal")],
                    equivalents: [StandardEquivalent(written: "ありがとう")],
                    notes: "Heard in Osaka", folderID: folderID, folderPath: ["Trip 2026"],
                    dialectTagIDs: [tagID], dialectTagNames: ["大阪弁"], createdAt: date, updatedAt: date
                )
            ]
        )
        let decoded = try WordBankArchive.decode(try archive.encoded())
        XCTAssertEqual(decoded, archive)
    }

    func testHandWrittenFileWithOnlyTextAndPathsDecodes() throws {
        let json = #"{"entries":[{"text":"おおきに","folderPath":["Trip","Osaka"],"dialectTagNames":["大阪弁"]}]}"#
        let archive = try WordBankArchive.decode(Data(json.utf8))
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual(archive.entries[0].folderPath, ["Trip", "Osaka"])
        XCTAssertEqual(archive.entries[0].kind, .word)
        XCTAssertNil(archive.entries[0].id)
        XCTAssertTrue(archive.folders.isEmpty)
        XCTAssertTrue(archive.skipped.isEmpty)
    }

    func testUnknownFieldsAndEnumValuesAreTolerated() throws {
        let json = #"{"format":"word-bank","version":1,"future":true,"entries":[{"text":"x","kind":"haiku","wordClass":"adverb","surprise":1}]}"#
        let archive = try WordBankArchive.decode(Data(json.utf8))
        XCTAssertEqual(archive.entries[0].kind, .word)
        XCTAssertNil(archive.entries[0].wordClass)
    }

    func testBadRecordsAreSkippedWithReasons() throws {
        let json = #"{"entries":[{"text":"ok"},{"reading":"no text"},{"text":"   "}]}"#
        let archive = try WordBankArchive.decode(Data(json.utf8))
        XCTAssertEqual(archive.entries.map(\.text), ["ok"])
        XCTAssertEqual(archive.skipped.map(\.position), [2, 3])
        XCTAssertEqual(archive.skipped.map(\.section), ["entries", "entries"])
        XCTAssertFalse(archive.skipped[0].reason.isEmpty)
    }

    func testNewerVersionIsRefused() {
        let json = #"{"format":"word-bank","version":2,"entries":[]}"#
        XCTAssertThrowsError(try WordBankArchive.decode(Data(json.utf8))) {
            XCTAssertEqual($0 as? WordBankArchive.ArchiveError, .newerVersion(2))
        }
    }

    func testOtherFormatsAndGarbageAreRefused() {
        for json in [#"{"format":"something-else","entries":[]}"#, "not json", "[]", #"{"hello":1}"#] {
            XCTAssertThrowsError(try WordBankArchive.decode(Data(json.utf8)), json) {
                XCTAssertEqual($0 as? WordBankArchive.ArchiveError, .notAWordBank)
            }
        }
    }

    func testOversizedFileIsRefused() {
        XCTAssertThrowsError(try WordBankArchive.decode(Data(count: WordBankArchive.maxBytes + 1))) {
            XCTAssertEqual($0 as? WordBankArchive.ArchiveError, .tooLarge)
        }
    }

    func testEncodedFileStartsWithHeader() throws {
        let text = String(decoding: try WordBankArchive(exportedAt: date).encoded(), as: UTF8.self)
        XCTAssertTrue(text.contains(#""format" : "word-bank""#))
        XCTAssertTrue(text.contains(#""version" : 1"#))
    }
}
```

Note: the memberwise `init`s are written in step 3 with default values for every field except `text`, so the calls above compile.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/VerbKit --filter WordBankArchiveTests`
Expected: FAIL to compile ("cannot find 'WordBankArchive' in scope").

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The `.wordbank` file: JSON with a header, then folders, tags, smart folders and entries.
/// Reading is lenient (only `text` is required, so a hand-written or generated file with no
/// ids still imports); writing always writes everything.
public struct WordBankArchive: Equatable, Sendable {
    public static let formatName = "word-bank"
    public static let currentVersion = 1
    public static let maxBytes = 20 * 1024 * 1024

    public struct Folder: Codable, Equatable, Sendable {
        public var id: UUID?
        public var name: String
        public var parentID: UUID?
        public init(id: UUID? = nil, name: String, parentID: UUID? = nil) {
            self.id = id; self.name = name; self.parentID = parentID
        }
    }

    public struct DialectTag: Codable, Equatable, Sendable {
        public var id: UUID?
        public var name: String
        public var romaji: String?
        public var prefectures: [Prefecture]?
        public var region: Region?
        public var catalogueID: String?
        public init(
            id: UUID? = nil, name: String, romaji: String? = nil, prefectures: [Prefecture]? = nil,
            region: Region? = nil, catalogueID: String? = nil
        ) {
            self.id = id; self.name = name; self.romaji = romaji; self.prefectures = prefectures
            self.region = region; self.catalogueID = catalogueID
        }

        enum CodingKeys: String, CodingKey { case id, name, romaji, prefectures, region, catalogueID }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.lenient(UUID.self, .id)
            name = try c.decode(String.self, forKey: .name)
            romaji = c.lenient(String.self, .romaji)
            prefectures = c.lenient([Prefecture].self, .prefectures)
            region = c.lenient(Region.self, .region)
            catalogueID = c.lenient(String.self, .catalogueID)
        }
    }

    public struct CustomTag: Codable, Equatable, Sendable {
        public var id: UUID?
        public var name: String
        public var color: CustomTagColor?
        public init(id: UUID? = nil, name: String, color: CustomTagColor? = nil) {
            self.id = id; self.name = name; self.color = color
        }

        enum CodingKeys: String, CodingKey { case id, name, color }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.lenient(UUID.self, .id)
            name = try c.decode(String.self, forKey: .name)
            color = c.lenient(CustomTagColor.self, .color)
        }
    }

    public struct SmartFolder: Codable, Equatable, Sendable {
        public var name: String
        public var dialectTagNames: [String]
        public var customTagNames: [String]
        public var match: SmartFolderMatch
        public init(name: String, dialectTagNames: [String] = [], customTagNames: [String] = [], match: SmartFolderMatch = .any) {
            self.name = name; self.dialectTagNames = dialectTagNames
            self.customTagNames = customTagNames; self.match = match
        }

        enum CodingKeys: String, CodingKey { case name, dialectTagNames, customTagNames, match }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            dialectTagNames = c.lenient([String].self, .dialectTagNames) ?? []
            customTagNames = c.lenient([String].self, .customTagNames) ?? []
            match = c.lenient(SmartFolderMatch.self, .match) ?? .any
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var id: UUID?
        public var text: String
        public var reading: String?
        public var kanjiSpelling: String?
        public var kind: EntryKind
        public var wordClass: WordClass?
        public var senses: [Sense]
        public var equivalents: [StandardEquivalent]
        public var linkedWordID: String?
        public var linkedFormID: String?
        public var notes: String?
        public var folderID: UUID?
        /// `["Trip 2026", "Takayama"]`: lets a file with no `folders` list still file entries.
        public var folderPath: [String]
        public var dialectTagIDs: [UUID]
        public var dialectTagNames: [String]
        public var customTagIDs: [UUID]
        public var customTagNames: [String]
        public var createdAt: Date?
        public var updatedAt: Date?

        public init(
            id: UUID? = nil, text: String, reading: String? = nil, kanjiSpelling: String? = nil,
            kind: EntryKind = .word, wordClass: WordClass? = nil, senses: [Sense] = [],
            equivalents: [StandardEquivalent] = [], linkedWordID: String? = nil, linkedFormID: String? = nil,
            notes: String? = nil, folderID: UUID? = nil, folderPath: [String] = [],
            dialectTagIDs: [UUID] = [], dialectTagNames: [String] = [],
            customTagIDs: [UUID] = [], customTagNames: [String] = [],
            createdAt: Date? = nil, updatedAt: Date? = nil
        ) {
            self.id = id; self.text = text; self.reading = reading; self.kanjiSpelling = kanjiSpelling
            self.kind = kind; self.wordClass = wordClass; self.senses = senses; self.equivalents = equivalents
            self.linkedWordID = linkedWordID; self.linkedFormID = linkedFormID; self.notes = notes
            self.folderID = folderID; self.folderPath = folderPath
            self.dialectTagIDs = dialectTagIDs; self.dialectTagNames = dialectTagNames
            self.customTagIDs = customTagIDs; self.customTagNames = customTagNames
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }

        enum CodingKeys: String, CodingKey {
            case id, text, reading, kanjiSpelling, kind, wordClass, senses, equivalents, linkedWordID
            case linkedFormID, notes, folderID, folderPath, dialectTagIDs, dialectTagNames
            case customTagIDs, customTagNames, createdAt, updatedAt
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.lenient(UUID.self, .id)
            text = try c.decode(String.self, forKey: .text)
            reading = c.lenient(String.self, .reading)
            kanjiSpelling = c.lenient(String.self, .kanjiSpelling)
            kind = c.lenient(EntryKind.self, .kind) ?? .word
            wordClass = c.lenient(WordClass.self, .wordClass)
            senses = c.lenient([Sense].self, .senses) ?? []
            equivalents = c.lenient([StandardEquivalent].self, .equivalents) ?? []
            linkedWordID = c.lenient(String.self, .linkedWordID)
            linkedFormID = c.lenient(String.self, .linkedFormID)
            notes = c.lenient(String.self, .notes)
            folderID = c.lenient(UUID.self, .folderID)
            folderPath = c.lenient([String].self, .folderPath) ?? []
            dialectTagIDs = c.lenient([UUID].self, .dialectTagIDs) ?? []
            dialectTagNames = c.lenient([String].self, .dialectTagNames) ?? []
            customTagIDs = c.lenient([UUID].self, .customTagIDs) ?? []
            customTagNames = c.lenient([String].self, .customTagNames) ?? []
            createdAt = c.lenient(Date.self, .createdAt)
            updatedAt = c.lenient(Date.self, .updatedAt)
        }
    }

    public struct Skipped: Equatable, Sendable {
        public var section: String
        public var position: Int
        public var reason: String
        public init(section: String, position: Int, reason: String) {
            self.section = section; self.position = position; self.reason = reason
        }
    }

    public enum ArchiveError: Error, Equatable, Sendable {
        case notAWordBank
        case newerVersion(Int)
        case tooLarge
    }

    public var exportedAt: Date
    public var folders: [Folder]
    public var dialectTags: [DialectTag]
    public var customTags: [CustomTag]
    public var smartFolders: [SmartFolder]
    public var entries: [Entry]
    public var skipped: [Skipped]

    public init(
        exportedAt: Date = Date(), folders: [Folder] = [], dialectTags: [DialectTag] = [],
        customTags: [CustomTag] = [], smartFolders: [SmartFolder] = [], entries: [Entry] = [],
        skipped: [Skipped] = []
    ) {
        self.exportedAt = exportedAt; self.folders = folders; self.dialectTags = dialectTags
        self.customTags = customTags; self.smartFolders = smartFolders; self.entries = entries
        self.skipped = skipped
    }

    // MARK: - Writing

    private struct Output: Encodable {
        var format = WordBankArchive.formatName
        var version = WordBankArchive.currentVersion
        var exportedAt: Date
        var folders: [Folder]
        var dialectTags: [DialectTag]
        var customTags: [CustomTag]
        var smartFolders: [SmartFolder]
        var entries: [Entry]
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.dateFormatter.string(from: date))
        }
        return try encoder.encode(Output(
            exportedAt: exportedAt, folders: folders, dialectTags: dialectTags, customTags: customTags,
            smartFolders: smartFolders, entries: entries
        ))
    }

    // MARK: - Reading

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        let failure: String?
        init(from decoder: Decoder) throws {
            do {
                value = try T(from: decoder)
                failure = nil
            } catch {
                value = nil
                failure = "Unreadable record (missing or invalid fields)"
            }
        }
    }

    private struct Input: Decodable {
        var format: String?
        var version: Int?
        var exportedAt: Date?
        var folders: [Lossy<Folder>]?
        var dialectTags: [Lossy<DialectTag>]?
        var customTags: [Lossy<CustomTag>]?
        var smartFolders: [Lossy<SmartFolder>]?
        var entries: [Lossy<Entry>]?
    }

    public static func decode(_ data: Data) throws -> WordBankArchive {
        guard data.count <= maxBytes else { throw ArchiveError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = Self.dateFormatter.date(from: text) ?? Self.fractionalFormatter.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date"))
            }
            return date
        }
        guard let input = try? decoder.decode(Input.self, from: data) else { throw ArchiveError.notAWordBank }
        if let format = input.format, format != formatName { throw ArchiveError.notAWordBank }
        if input.format == nil, input.entries == nil { throw ArchiveError.notAWordBank }
        let version = input.version ?? 1
        guard version <= currentVersion else { throw ArchiveError.newerVersion(version) }

        var skipped: [Skipped] = []
        func unwrap<T>(_ section: String, _ items: [Lossy<T>]?) -> [T] {
            var result: [T] = []
            for (index, item) in (items ?? []).enumerated() {
                if let value = item.value { result.append(value) } else {
                    skipped.append(Skipped(section: section, position: index + 1, reason: item.failure ?? "Unreadable record"))
                }
            }
            return result
        }
        var archive = WordBankArchive(exportedAt: input.exportedAt ?? Date())
        archive.folders = unwrap("folders", input.folders)
        archive.dialectTags = unwrap("dialectTags", input.dialectTags)
        archive.customTags = unwrap("customTags", input.customTags)
        archive.smartFolders = unwrap("smartFolders", input.smartFolders)
        let decodedEntries = input.entries ?? []
        for (index, item) in decodedEntries.enumerated() {
            guard let entry = item.value else {
                skipped.append(Skipped(section: "entries", position: index + 1, reason: item.failure ?? "Missing text"))
                continue
            }
            if entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                skipped.append(Skipped(section: "entries", position: index + 1, reason: "Blank text"))
            } else {
                archive.entries.append(entry)
            }
        }
        archive.skipped = skipped
        return archive
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension KeyedDecodingContainer {
    /// The value if present and valid, otherwise nil: one bad field never loses the record.
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
```

`ISO8601DateFormatter` is not `Sendable`; if the compiler objects, mark the two statics `nonisolated(unsafe)`.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/VerbKit --filter WordBankArchiveTests`
Expected: PASS (8 tests). If `testBadRecordsAreSkippedWithReasons` shows an unexpected reason for `{"reading":"no text"}`, that is the `Lossy` message; the test only checks it is non-empty.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/WordBank/WordBankArchive.swift Packages/VerbKit/Tests/VerbKitTests/WordBankArchiveTests.swift
git commit -m "Word Bank file format: .wordbank archive with lenient reading"
```

---

### Task 2: Export scopes

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankExport.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/WordBankExportTests.swift`

**Interfaces:**
- Consumes: `WordBankArchive` (Task 1), `WordBankSnapshot`, `FolderTree`.
- Produces:

```swift
public enum WordBankExportScope: Equatable, Sendable {
    case everything
    case folder(UUID)          // the folder and its subfolders; the folder is the file's only top-level folder
    case entries([UUID])       // a selection or search results
}
extension WordBankArchive {
    public init(snapshot: WordBankSnapshot, scope: WordBankExportScope, exportedAt: Date = Date())
    public static func suggestedFileName(for scope: WordBankExportScope, in snapshot: WordBankSnapshot, on date: Date = Date()) -> String   // no extension
}
```

Rules: **everything** includes every folder, every tag (used or not), smart folders and all entries. **folder** includes the folder, its descendants, their entries and only the tags those entries use; the folder's `parentID` is dropped and each entry's `folderPath` starts at that folder. **entries** includes the selected entries, the folders on their paths (ancestors included) and the tags they use. Entries are sorted by `createdAt` then id so output is stable. Every entry carries `folderID`, `folderPath`, and both tag ids and tag names.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import VerbKit

final class WordBankExportTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private var trip = WordBankFolderValue(name: "Trip 2026")
    private var takayama = WordBankFolderValue(name: "Takayama")
    private var other = WordBankFolderValue(name: "Other")
    private var hida = DialectTagValue(name: "飛騨弁", prefectures: [.gifu], region: .chubu)
    private var osaka = DialectTagValue(name: "大阪弁", prefectures: [.osaka], region: .kansai)
    private var food = CustomTagValue(name: "food", color: .orange)
    private var snapshot = WordBankSnapshot()

    override func setUp() {
        takayama.parentID = trip.id
        let inTakayama = WordBankEntryValue(text: "だちかん", folderID: takayama.id, dialectTagIDs: [hida.id], customTagIDs: [food.id], createdAt: date)
        let inOther = WordBankEntryValue(text: "おおきに", folderID: other.id, dialectTagIDs: [osaka.id], createdAt: date.addingTimeInterval(10))
        let loose = WordBankEntryValue(text: "めんこい", createdAt: date.addingTimeInterval(20))
        snapshot = WordBankSnapshot(
            entries: [inTakayama, inOther, loose], folders: [trip, takayama, other],
            dialectTags: [hida, osaka], customTags: [food, CustomTagValue(name: "unused")],
            smartFolders: [WordBankSmartFolderValue(name: "Kansai", dialectTagIDs: [osaka.id])]
        )
    }

    func testEverythingIncludesUnusedTagsFoldersAndSmartFolders() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .everything, exportedAt: date)
        XCTAssertEqual(archive.entries.count, 3)
        XCTAssertEqual(archive.folders.count, 3)
        XCTAssertEqual(archive.dialectTags.count, 2)
        XCTAssertEqual(archive.customTags.map(\.name).sorted(), ["food", "unused"])
        XCTAssertEqual(archive.smartFolders, [.init(name: "Kansai", dialectTagNames: ["大阪弁"], customTagNames: [], match: .any)])
        let entry = archive.entries.first { $0.text == "だちかん" }!
        XCTAssertEqual(entry.folderPath, ["Trip 2026", "Takayama"])
        XCTAssertEqual(entry.dialectTagNames, ["飛騨弁"])
        XCTAssertEqual(entry.customTagNames, ["food"])
        XCTAssertEqual(entry.dialectTagIDs, [hida.id])
    }

    func testFolderScopeMakesThatFolderTheRootAndKeepsOnlyItsTags() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .folder(takayama.id), exportedAt: date)
        XCTAssertEqual(archive.entries.map(\.text), ["だちかん"])
        XCTAssertEqual(archive.folders.map(\.name), ["Takayama"])
        XCTAssertNil(archive.folders[0].parentID)
        XCTAssertEqual(archive.entries[0].folderPath, ["Takayama"])
        XCTAssertEqual(archive.dialectTags.map(\.name), ["飛騨弁"])
        XCTAssertEqual(archive.customTags.map(\.name), ["food"])
        XCTAssertTrue(archive.smartFolders.isEmpty)
    }

    func testFolderScopeIncludesSubfolders() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .folder(trip.id), exportedAt: date)
        XCTAssertEqual(Set(archive.folders.map(\.name)), ["Trip 2026", "Takayama"])
        XCTAssertEqual(archive.entries.first?.folderPath, ["Trip 2026", "Takayama"])
    }

    func testEntriesScopeKeepsPathsAndUsedTagsOnly() {
        let id = snapshot.entries.first { $0.text == "だちかん" }!.id
        let archive = WordBankArchive(snapshot: snapshot, scope: .entries([id]), exportedAt: date)
        XCTAssertEqual(archive.entries.count, 1)
        XCTAssertEqual(Set(archive.folders.map(\.name)), ["Trip 2026", "Takayama"])
        XCTAssertEqual(archive.dialectTags.map(\.name), ["飛騨弁"])
    }

    func testMissingFolderGivesAnEmptyArchive() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .folder(UUID()), exportedAt: date)
        XCTAssertTrue(archive.entries.isEmpty)
        XCTAssertTrue(archive.folders.isEmpty)
    }

    func testEntriesAreSortedForStableOutput() {
        let archive = WordBankArchive(snapshot: snapshot, scope: .everything, exportedAt: date)
        XCTAssertEqual(archive.entries.map(\.text), ["だちかん", "おおきに", "めんこい"])
    }

    func testSuggestedFileNames() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 12))!
        XCTAssertEqual(WordBankArchive.suggestedFileName(for: .everything, in: snapshot, on: day), "Word Bank 2026-10-06")
        XCTAssertEqual(WordBankArchive.suggestedFileName(for: .folder(takayama.id), in: snapshot, on: day), "Takayama")
        XCTAssertEqual(WordBankArchive.suggestedFileName(for: .entries([]), in: snapshot, on: day), "Word Bank selection 2026-10-06")
    }

    func testFileNameDropsPathCharacters() {
        var odd = WordBankFolderValue(name: "a/b:c")
        odd.parentID = nil
        let snap = WordBankSnapshot(folders: [odd])
        XCTAssertEqual(WordBankArchive.suggestedFileName(for: .folder(odd.id), in: snap), "a-b-c")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/VerbKit --filter WordBankExportTests`
Expected: FAIL to compile (`WordBankExportScope` not found).

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum WordBankExportScope: Equatable, Sendable {
    case everything
    case folder(UUID)
    case entries([UUID])
}

extension WordBankArchive {
    public init(snapshot: WordBankSnapshot, scope: WordBankExportScope, exportedAt: Date = Date()) {
        let tree = FolderTree(snapshot.folders)
        var entries: [WordBankEntryValue]
        var folderIDs = Set<UUID>()
        var rootFolder: UUID?

        switch scope {
        case .everything:
            entries = snapshot.entries
            folderIDs = Set(snapshot.folders.map(\.id))
        case .folder(let id):
            guard tree.folder(id) != nil else {
                self.init(exportedAt: exportedAt)
                return
            }
            rootFolder = id
            folderIDs = tree.descendants(of: id).union([id])
            entries = snapshot.entries.filter { $0.folderID.map(folderIDs.contains) ?? false }
        case .entries(let ids):
            let wanted = Set(ids)
            entries = snapshot.entries.filter { wanted.contains($0.id) }
            for entry in entries {
                if let folder = entry.folderID { folderIDs.formUnion(tree.path(of: folder).map(\.id)) }
            }
        }
        entries.sort { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }

        let everything = scope == .everything
        let usedDialect = Set(entries.flatMap(\.dialectTagIDs))
        let usedCustom = Set(entries.flatMap(\.customTagIDs))
        let dialectTags = snapshot.dialectTags.filter { everything || usedDialect.contains($0.id) }
        let customTags = snapshot.customTags.filter { everything || usedCustom.contains($0.id) }
        let dialectNames = Dictionary(snapshot.dialectTags.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let customNames = Dictionary(snapshot.customTags.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        func folderPath(_ id: UUID?) -> [String] {
            guard let id else { return [] }
            var path = tree.path(of: id)
            if let rootFolder { path = Array(path.drop { $0.id != rootFolder }) }
            return path.map(\.name)
        }

        self.init(
            exportedAt: exportedAt,
            folders: snapshot.folders.filter { folderIDs.contains($0.id) }.map {
                Folder(id: $0.id, name: $0.name, parentID: $0.id == rootFolder ? nil : $0.parentID)
            },
            dialectTags: dialectTags.map {
                DialectTag(id: $0.id, name: $0.name, romaji: $0.romaji, prefectures: $0.prefectures, region: $0.region, catalogueID: $0.catalogueID)
            },
            customTags: customTags.map { CustomTag(id: $0.id, name: $0.name, color: $0.color) },
            smartFolders: everything ? snapshot.smartFolders.map {
                SmartFolder(
                    name: $0.name,
                    dialectTagNames: $0.dialectTagIDs.compactMap { dialectNames[$0] },
                    customTagNames: $0.customTagIDs.compactMap { customNames[$0] },
                    match: $0.match
                )
            } : [],
            entries: entries.map { entry in
                Entry(
                    id: entry.id, text: entry.text, reading: entry.reading, kanjiSpelling: entry.kanjiSpelling,
                    kind: entry.kind, wordClass: entry.wordClass, senses: entry.senses, equivalents: entry.equivalents,
                    linkedWordID: entry.linkedWordID, linkedFormID: entry.linkedFormID, notes: entry.notes,
                    folderID: entry.folderID, folderPath: folderPath(entry.folderID),
                    dialectTagIDs: entry.dialectTagIDs, dialectTagNames: entry.dialectTagIDs.compactMap { dialectNames[$0] },
                    customTagIDs: entry.customTagIDs, customTagNames: entry.customTagIDs.compactMap { customNames[$0] },
                    createdAt: entry.createdAt, updatedAt: entry.updatedAt
                )
            }
        )
    }

    /// A file name without the extension.
    public static func suggestedFileName(
        for scope: WordBankExportScope, in snapshot: WordBankSnapshot, on date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        switch scope {
        case .everything:
            return "Word Bank \(day)"
        case .entries:
            return "Word Bank selection \(day)"
        case .folder(let id):
            guard let name = snapshot.folders.first(where: { $0.id == id })?.name else { return "Word Bank \(day)" }
            let cleaned = String(name.map { "/:\\".contains($0) ? "-" : $0 })
            return cleaned.isEmpty ? "Word Bank \(day)" : cleaned
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/VerbKit --filter WordBankExportTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/WordBank/WordBankExport.swift Packages/VerbKit/Tests/VerbKitTests/WordBankExportTests.swift
git commit -m "Word Bank export: everything, one folder, a selection"
```

---

### Task 3: Combining a matched entry

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankEntryCombiner.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Store/WordBankStore.swift` (`cleaned(_:)`, around line 335)
- Test: `Packages/VerbKit/Tests/VerbKitTests/WordBankEntryCombinerTests.swift`

**Interfaces:**
- Produces:

```swift
extension WordBankEntryValue {
    /// Trimmed text fields, blank senses and equivalents dropped, nil for blank optionals,
    /// `wordClass` only for words. Does not touch folder or tag ids.
    public func trimmed() -> WordBankEntryValue
}
public enum WordBankEntryCombiner {
    public struct Result: Equatable, Sendable { public var entry: WordBankEntryValue; public var changed: Bool }
    public static func combine(
        local: WordBankEntryValue, incoming: WordBankEntryValue, importedFolderID: UUID?,
        importedOn: Date, now: Date
    ) -> Result
}
```

Rules (from the spec): text, kind and anything filled locally stay; empty `reading`, `kanjiSpelling`, `wordClass` (words only), `linkedWordID`, `linkedFormID` are filled from the file; senses (by `key(meaning)`), equivalents (by `key(written)` + `|` + `key(reading ?? "")`) and tag ids are unioned, local order first; notes: if the file's note is non-blank and `key(local notes)` doesn't contain `key(note)`, append `"\n\nImported yyyy-MM-dd: <note>"` (or just the note when the local notes are empty); an unfiled local entry takes `importedFolderID`; `createdAt` becomes the earlier of the two; `updatedAt` becomes `now` only if something other than `createdAt` changed.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import VerbKit

final class WordBankEntryCombinerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private let early = Date(timeIntervalSince1970: 1_000_000_000)
    private let late = Date(timeIntervalSince1970: 1_500_000_000)

    private func combine(_ local: WordBankEntryValue, _ incoming: WordBankEntryValue, folder: UUID? = nil) -> WordBankEntryCombiner.Result {
        WordBankEntryCombiner.combine(local: local, incoming: incoming, importedFolderID: folder, importedOn: now, now: now)
    }

    func testFillsEmptyFieldsAndKeepsFilledOnes() {
        let local = WordBankEntryValue(text: "おおきに", kind: .phrase, createdAt: late)
        let incoming = WordBankEntryValue(text: "おおきに", reading: "おおきに", kanjiSpelling: "大きに", kind: .word, linkedWordID: "verb:x", createdAt: late)
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.reading, "おおきに")
        XCTAssertEqual(result.entry.kanjiSpelling, "大きに")
        XCTAssertEqual(result.entry.kind, .phrase)
        XCTAssertEqual(result.entry.linkedWordID, "verb:x")
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.entry.updatedAt, now)
    }

    func testFilledLocalFieldsAreNeverOverwritten() {
        let local = WordBankEntryValue(text: "a", reading: "あ", kanjiSpelling: "亜", createdAt: late)
        let incoming = WordBankEntryValue(text: "a", reading: "い", kanjiSpelling: "伊", createdAt: late)
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.reading, "あ")
        XCTAssertEqual(result.entry.kanjiSpelling, "亜")
        XCTAssertFalse(result.changed)
    }

    func testSensesAndEquivalentsAreUnionedWithoutDuplicates() {
        let local = WordBankEntryValue(
            text: "a", senses: [Sense(meaning: "Thank you")], equivalents: [StandardEquivalent(written: "ありがとう")], createdAt: late
        )
        let incoming = WordBankEntryValue(
            text: "a", senses: [Sense(meaning: "thank you"), Sense(meaning: "cheers")],
            equivalents: [StandardEquivalent(written: "アリガトウ"), StandardEquivalent(written: "どうも")], createdAt: late
        )
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.senses.map(\.meaning), ["Thank you", "cheers"])
        XCTAssertEqual(result.entry.equivalents.map(\.written), ["ありがとう", "どうも"])
    }

    func testTagsAreUnioned() {
        let a = UUID(), b = UUID(), c = UUID()
        let local = WordBankEntryValue(text: "x", dialectTagIDs: [a], customTagIDs: [c], createdAt: late)
        let incoming = WordBankEntryValue(text: "x", dialectTagIDs: [a, b], customTagIDs: [c], createdAt: late)
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.dialectTagIDs, [a, b])
        XCTAssertEqual(result.entry.customTagIDs, [c])
    }

    func testNotesAreAppendedOnceUnderAnImportedHeading() {
        let local = WordBankEntryValue(text: "x", notes: "Heard at the izakaya", createdAt: late)
        let incoming = WordBankEntryValue(text: "x", notes: "From Yuki", createdAt: late)
        let once = combine(local, incoming).entry
        XCTAssertTrue(once.notes!.hasPrefix("Heard at the izakaya\n\nImported "))
        XCTAssertTrue(once.notes!.hasSuffix(": From Yuki"))
        XCTAssertFalse(combine(once, incoming).changed)
    }

    func testNotesAlreadyContainedAreNotAppendedAndEmptyNotesAreFilledPlainly() {
        let local = WordBankEntryValue(text: "x", notes: "Heard at the izakaya in Osaka", createdAt: late)
        XCTAssertFalse(combine(local, WordBankEntryValue(text: "x", notes: "izakaya", createdAt: late)).changed)
        let empty = WordBankEntryValue(text: "x", createdAt: late)
        XCTAssertEqual(combine(empty, WordBankEntryValue(text: "x", notes: "From Yuki", createdAt: late)).entry.notes, "From Yuki")
    }

    func testUnfiledEntryMovesToImportedFolderButFiledOneStays() {
        let target = UUID(), kept = UUID()
        let unfiled = WordBankEntryValue(text: "x", createdAt: late)
        XCTAssertEqual(combine(unfiled, unfiled, folder: target).entry.folderID, target)
        let filed = WordBankEntryValue(text: "x", folderID: kept, createdAt: late)
        XCTAssertEqual(combine(filed, unfiled, folder: target).entry.folderID, kept)
    }

    func testCreatedAtBecomesTheEarlierAndAloneDoesNotCountAsAChange() {
        let local = WordBankEntryValue(text: "x", createdAt: late, updatedAt: late)
        let incoming = WordBankEntryValue(text: "x", createdAt: early)
        let result = combine(local, incoming)
        XCTAssertEqual(result.entry.createdAt, early)
        XCTAssertEqual(result.entry.updatedAt, late)
        XCTAssertFalse(result.changed)
    }

    func testTrimmedCleansTextFields() {
        let entry = WordBankEntryValue(
            text: "  おおきに \n", reading: "  ", kanjiSpelling: " 大 ", kind: .phrase, wordClass: .noun,
            senses: [Sense(meaning: "  "), Sense(meaning: " thanks ", note: " ")],
            equivalents: [StandardEquivalent(written: " ありがとう ", reading: "")], notes: "\n"
        ).trimmed()
        XCTAssertEqual(entry.text, "おおきに")
        XCTAssertNil(entry.reading)
        XCTAssertEqual(entry.kanjiSpelling, "大")
        XCTAssertNil(entry.wordClass)
        XCTAssertEqual(entry.senses, [Sense(meaning: "thanks", note: nil)])
        XCTAssertEqual(entry.equivalents, [StandardEquivalent(written: "ありがとう")])
        XCTAssertNil(entry.notes)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/VerbKit --filter WordBankEntryCombinerTests`
Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`WordBankEntryCombiner.swift`:

```swift
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
```

`WordBankStore.cleaned(_:)`: replace the body up to and including `if entry.kind != .word { entry.wordClass = nil }` with `var entry = entry.trimmed()` and keep the folder and tag-id filtering lines unchanged.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/VerbKit`
Expected: exit code 0; the combiner tests (9) pass and the existing store tests are unchanged.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/WordBank/WordBankEntryCombiner.swift Packages/VerbKit/Sources/VerbKit/Store/WordBankStore.swift Packages/VerbKit/Tests/VerbKitTests/WordBankEntryCombinerTests.swift
git commit -m "Word Bank import: merge rules for entries that already exist"
```

---

### Task 4: Changes and all-or-nothing writes

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankChanges.swift`
- Modify: `Packages/VerbKit/Sources/VerbKit/Persistence/WordBankPersisting.swift`, `.../Persistence/SwiftDataWordBankPersisting.swift`, `.../Store/WordBankStore.swift`
- Modify (test double): `Packages/VerbKit/Tests/VerbKitTests/WordBankStoreTests.swift` (`Double` gets `apply`)
- Test: `Packages/VerbKit/Tests/VerbKitTests/WordBankChangesTests.swift`; add cases to `SwiftDataWordBankPersistingTests.swift` and `WordBankStoreTests.swift`

**Interfaces:**
- Produces:

```swift
public struct WordBankChanges: Equatable, Sendable {
    public var entries: [WordBankEntryValue] = []          // upserts
    public var folders: [WordBankFolderValue] = []
    public var dialectTags: [DialectTagValue] = []
    public var customTags: [CustomTagValue] = []
    public var smartFolders: [WordBankSmartFolderValue] = []
    public var deletedEntryIDs: [UUID] = []
    public var deletedFolderIDs: [UUID] = []
    public var deletedDialectTagIDs: [UUID] = []
    public var deletedCustomTagIDs: [UUID] = []
    public var deletedSmartFolderIDs: [UUID] = []
    public init()
    public var isEmpty: Bool
    /// The bank after these changes: upserts by id, deletes, sorted like `load()`.
    public func applied(to snapshot: WordBankSnapshot) -> WordBankSnapshot
    /// Writes that turn `current` into `replacement`.
    public static func replacing(_ current: WordBankSnapshot, with replacement: WordBankSnapshot) -> WordBankChanges
}
// WordBankPersisting
func apply(_ changes: WordBankChanges) throws        // all or nothing: if it throws, nothing was written
// WordBankStore
public var snapshot: WordBankSnapshot { get }
public func apply(_ changes: WordBankChanges) throws // throws WordBankError.saveFailed; memory changes only after the write succeeded
```

- [ ] **Step 1: Write the failing tests**

`WordBankChangesTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class WordBankChangesTests: XCTestCase {
    func testAppliedUpsertsReplacesAndDeletes() {
        let keep = WordBankEntryValue(text: "keep"), drop = WordBankEntryValue(text: "drop")
        var edited = keep
        edited.reading = "きーぷ"
        let added = WordBankEntryValue(text: "new")
        var changes = WordBankChanges()
        changes.entries = [edited, added]
        changes.deletedEntryIDs = [drop.id]
        let result = changes.applied(to: WordBankSnapshot(entries: [keep, drop]))
        XCTAssertEqual(Set(result.entries.map(\.text)), ["keep", "new"])
        XCTAssertEqual(result.entries.first { $0.id == keep.id }?.reading, "きーぷ")
    }

    func testIsEmpty() {
        XCTAssertTrue(WordBankChanges().isEmpty)
        var changes = WordBankChanges()
        changes.deletedFolderIDs = [UUID()]
        XCTAssertFalse(changes.isEmpty)
    }

    func testReplacingTurnsOneBankIntoAnother() {
        let folder = WordBankFolderValue(name: "Old")
        let oldEntry = WordBankEntryValue(text: "old", folderID: folder.id)
        let tag = DialectTagValue(name: "大阪弁", region: .kansai)
        let current = WordBankSnapshot(entries: [oldEntry], folders: [folder], dialectTags: [tag])
        let newEntry = WordBankEntryValue(text: "new")
        let replacement = WordBankSnapshot(entries: [newEntry])
        let changes = WordBankChanges.replacing(current, with: replacement)
        XCTAssertEqual(changes.deletedEntryIDs, [oldEntry.id])
        XCTAssertEqual(changes.deletedFolderIDs, [folder.id])
        XCTAssertEqual(changes.deletedDialectTagIDs, [tag.id])
        XCTAssertEqual(changes.entries, [newEntry])
        XCTAssertEqual(changes.applied(to: current), replacement)
    }

    func testReplacingWithTheSameBankIsEmpty() {
        let snap = WordBankSnapshot(entries: [WordBankEntryValue(text: "a")], folders: [WordBankFolderValue(name: "f")])
        XCTAssertTrue(WordBankChanges.replacing(snap, with: snap).isEmpty)
    }
}
```

In `SwiftDataWordBankPersistingTests` add (use the file's existing helper that makes an in-memory persister; follow the pattern of its other tests):

```swift
func testApplyWritesAFolderTreeTagsAndEntriesInOneGo() throws {
    let persisting = try makePersisting()          // use the helper the other tests in this file use
    let parent = WordBankFolderValue(name: "Trip"), child = WordBankFolderValue(name: "Takayama", parentID: parent.id)
    let tag = DialectTagValue(name: "飛騨弁", region: .chubu), custom = CustomTagValue(name: "food")
    let entry = WordBankEntryValue(text: "だちかん", folderID: child.id, dialectTagIDs: [tag.id], customTagIDs: [custom.id])
    var changes = WordBankChanges()
    changes.folders = [child, parent]               // child first on purpose: parents may arrive later
    changes.dialectTags = [tag]; changes.customTags = [custom]; changes.entries = [entry]
    changes.smartFolders = [WordBankSmartFolderValue(name: "Hida", dialectTagIDs: [tag.id])]
    try persisting.apply(changes)
    let loaded = try persisting.load()
    XCTAssertEqual(loaded.entries.first?.folderID, child.id)
    XCTAssertEqual(loaded.entries.first?.dialectTagIDs, [tag.id])
    XCTAssertEqual(Set(loaded.folders.map(\.name)), ["Trip", "Takayama"])
    XCTAssertEqual(loaded.folders.first { $0.id == child.id }?.parentID, parent.id)
    XCTAssertEqual(loaded.smartFolders.count, 1)
}

func testApplyDeletesAndUpdates() throws {
    let persisting = try makePersisting()
    let entry = WordBankEntryValue(text: "a"), gone = WordBankEntryValue(text: "b")
    try persisting.upsert(entry: entry); try persisting.upsert(entry: gone)
    var edited = entry
    edited.reading = "え"
    var changes = WordBankChanges()
    changes.entries = [edited]; changes.deletedEntryIDs = [gone.id]
    try persisting.apply(changes)
    let loaded = try persisting.load()
    XCTAssertEqual(loaded.entries.map(\.id), [entry.id])
    XCTAssertEqual(loaded.entries.first?.reading, "え")
}
```

In `WordBankStoreTests` add (after giving `Double` this method, shown in step 3):

```swift
func testApplyUpdatesMemoryAfterAGoodWrite() throws {
    var changes = WordBankChanges()
    changes.entries = [WordBankEntryValue(text: "a")]
    try store.apply(changes)
    XCTAssertEqual(store.entries.map(\.text), ["a"])
    XCTAssertEqual(persisting.snapshot.entries.count, 1)
}

func testFailedApplyThrowsAndLeavesMemoryUntouched() {
    persisting.failing = true
    var changes = WordBankChanges()
    changes.entries = [WordBankEntryValue(text: "a")]
    XCTAssertThrowsError(try store.apply(changes)) { XCTAssertEqual($0 as? WordBankError, .saveFailed) }
    XCTAssertTrue(store.entries.isEmpty)
    XCTAssertEqual(store.lastError, .saveFailed)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --package-path Packages/VerbKit --filter "WordBankChangesTests|SwiftDataWordBankPersistingTests|WordBankStoreTests"`
Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`WordBankChanges.swift`:

```swift
import Foundation

/// A set of writes to apply together (an import, or a restore).
public struct WordBankChanges: Equatable, Sendable {
    public var entries: [WordBankEntryValue] = []
    public var folders: [WordBankFolderValue] = []
    public var dialectTags: [DialectTagValue] = []
    public var customTags: [CustomTagValue] = []
    public var smartFolders: [WordBankSmartFolderValue] = []
    public var deletedEntryIDs: [UUID] = []
    public var deletedFolderIDs: [UUID] = []
    public var deletedDialectTagIDs: [UUID] = []
    public var deletedCustomTagIDs: [UUID] = []
    public var deletedSmartFolderIDs: [UUID] = []

    public init() {}

    public var isEmpty: Bool {
        entries.isEmpty && folders.isEmpty && dialectTags.isEmpty && customTags.isEmpty && smartFolders.isEmpty
            && deletedEntryIDs.isEmpty && deletedFolderIDs.isEmpty && deletedDialectTagIDs.isEmpty
            && deletedCustomTagIDs.isEmpty && deletedSmartFolderIDs.isEmpty
    }

    public func applied(to snapshot: WordBankSnapshot) -> WordBankSnapshot {
        func merge<T: Identifiable>(_ existing: [T], upserts: [T], deleted: [UUID]) -> [T] where T.ID == UUID {
            var result = existing.filter { !deleted.contains($0.id) }
            for item in upserts {
                if let index = result.firstIndex(where: { $0.id == item.id }) { result[index] = item } else { result.append(item) }
            }
            return result
        }
        var result = WordBankSnapshot(
            entries: merge(snapshot.entries, upserts: entries, deleted: deletedEntryIDs),
            folders: merge(snapshot.folders, upserts: folders, deleted: deletedFolderIDs),
            dialectTags: merge(snapshot.dialectTags, upserts: dialectTags, deleted: deletedDialectTagIDs),
            customTags: merge(snapshot.customTags, upserts: customTags, deleted: deletedCustomTagIDs),
            smartFolders: merge(snapshot.smartFolders, upserts: smartFolders, deleted: deletedSmartFolderIDs)
        )
        // Same order as `SwiftDataWordBankPersisting.load()`.
        result.entries.sort { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        result.folders.sort { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        result.dialectTags.sort { $0.name < $1.name }
        result.customTags.sort { $0.name < $1.name }
        result.smartFolders.sort { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        return result
    }

    public static func replacing(_ current: WordBankSnapshot, with replacement: WordBankSnapshot) -> WordBankChanges {
        func diff<T: Identifiable & Equatable>(_ old: [T], _ new: [T]) -> (upserts: [T], deleted: [UUID]) where T.ID == UUID {
            let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let newIDs = Set(new.map(\.id))
            return (new.filter { oldByID[$0.id] != $0 }, old.map(\.id).filter { !newIDs.contains($0) })
        }
        var changes = WordBankChanges()
        (changes.entries, changes.deletedEntryIDs) = diff(current.entries, replacement.entries)
        (changes.folders, changes.deletedFolderIDs) = diff(current.folders, replacement.folders)
        (changes.dialectTags, changes.deletedDialectTagIDs) = diff(current.dialectTags, replacement.dialectTags)
        (changes.customTags, changes.deletedCustomTagIDs) = diff(current.customTags, replacement.customTags)
        (changes.smartFolders, changes.deletedSmartFolderIDs) = diff(current.smartFolders, replacement.smartFolders)
        return changes
    }
}
```

`WordBankPersisting` protocol: add

```swift
/// Writes everything in `changes` in one save. If it throws, nothing was written.
func apply(_ changes: WordBankChanges) throws
```

`SwiftDataWordBankPersisting.apply` (one `save()`, rollback on failure; rows are looked up in dictionaries filled from one fetch each, so rows inserted earlier in the same call can be referenced):

```swift
public func apply(_ changes: WordBankChanges) throws {
    guard !changes.isEmpty else { return }
    do {
        var folders = Dictionary(try modelContext.fetch(FetchDescriptor<WordBankFolderEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var dialect = Dictionary(try modelContext.fetch(FetchDescriptor<DialectTagEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var custom = Dictionary(try modelContext.fetch(FetchDescriptor<CustomTagEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var entries = Dictionary(try modelContext.fetch(FetchDescriptor<WordBankEntryEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var smart = Dictionary(try modelContext.fetch(FetchDescriptor<WordBankSmartFolderEntity>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for id in changes.deletedEntryIDs { if let row = entries.removeValue(forKey: id) { modelContext.delete(row) } }
        for id in changes.deletedSmartFolderIDs { if let row = smart.removeValue(forKey: id) { modelContext.delete(row) } }
        for id in changes.deletedFolderIDs { if let row = folders.removeValue(forKey: id) { modelContext.delete(row) } }
        for id in changes.deletedDialectTagIDs { if let row = dialect.removeValue(forKey: id) { modelContext.delete(row) } }
        for id in changes.deletedCustomTagIDs { if let row = custom.removeValue(forKey: id) { modelContext.delete(row) } }

        for tag in changes.dialectTags {
            if let row = dialect[tag.id] { row.update(from: tag) } else {
                let row = DialectTagEntity(tag); modelContext.insert(row); dialect[tag.id] = row
            }
        }
        for tag in changes.customTags {
            if let row = custom[tag.id] { row.update(from: tag) } else {
                let row = CustomTagEntity(tag); modelContext.insert(row); custom[tag.id] = row
            }
        }
        for folder in changes.folders where folders[folder.id] == nil {
            let row = WordBankFolderEntity(id: folder.id); modelContext.insert(row); folders[folder.id] = row
        }
        for folder in changes.folders {          // second pass: every row exists, so parents resolve in any order
            guard let row = folders[folder.id] else { continue }
            row.name = folder.name
            row.sortOrder = folder.sortOrder
            row.parent = folder.parentID.flatMap { folders[$0] }
        }
        for entry in changes.entries {
            let row: WordBankEntryEntity
            if let existing = entries[entry.id] { row = existing } else {
                row = WordBankEntryEntity(entry); modelContext.insert(row); entries[entry.id] = row
            }
            row.update(from: entry)
            row.folder = entry.folderID.flatMap { folders[$0] }
            row.dialectTags = entry.dialectTagIDs.compactMap { dialect[$0] }
            row.customTags = entry.customTagIDs.compactMap { custom[$0] }
        }
        for folder in changes.smartFolders {
            if let row = smart[folder.id] { row.update(from: folder) } else {
                let row = WordBankSmartFolderEntity(folder); modelContext.insert(row); smart[folder.id] = row
            }
        }
        try modelContext.save()
    } catch {
        modelContext.rollback()
        throw error
    }
}
```

`WordBankStore`:

```swift
public var snapshot: WordBankSnapshot {
    WordBankSnapshot(entries: entries, folders: folders, dialectTags: dialectTags, customTags: customTags, smartFolders: smartFolders)
}

/// Applies the changes in one save. Memory changes only after the write worked, so a
/// failed import leaves the bank exactly as it was.
public func apply(_ changes: WordBankChanges) throws {
    guard !changes.isEmpty else { return }
    do { try persisting.apply(changes) } catch {
        lastError = .saveFailed
        throw WordBankError.saveFailed
    }
    let updated = changes.applied(to: snapshot)
    entries = updated.entries
    folders = updated.folders
    dialectTags = updated.dialectTags
    customTags = updated.customTags
    smartFolders = updated.smartFolders
}
```

Test double in `WordBankStoreTests.Double` (add this method; `write()` already throws when `failing` and counts):

```swift
func apply(_ changes: WordBankChanges) throws {
    try write()
    snapshot = changes.applied(to: snapshot)
}
```

Any other `WordBankPersisting` conformers in the package or app (grep for `: WordBankPersisting`) need the same method; fix compile errors until none remain.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/VerbKit`
Expected: exit code 0.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit Packages/VerbKit/Tests/VerbKitTests
git commit -m "Word Bank: apply a set of changes in one save, or none"
```

---

### Task 5: The import planner

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankImportPlanner.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/WordBankImportPlannerTests.swift`

**Interfaces:**
- Consumes: `WordBankArchive`, `WordBankEntryCombiner`, `WordBankChanges`, `DialectCatalogue`, `FolderTree`, `JapaneseNormalizer`.
- Produces:

```swift
public enum ImportDestination: Equatable, Sendable { case root; case folder(UUID) }

public struct WordBankImportSummary: Equatable, Sendable {
    public var newEntries = 0
    public var combinedEntries = 0          // existing entries that gained something
    public var unchangedEntries = 0
    public var newFolders: [[String]] = []  // paths relative to the destination
    public var newDialectTags: [String] = []
    public var newCustomTags: [String] = []
    public var newSmartFolders: [String] = []
    public var skipped: [WordBankArchive.Skipped] = []
    public var changesAnything: Bool { get }
}
public struct WordBankImportPlan: Equatable, Sendable {
    public var changes: WordBankChanges
    public var summary: WordBankImportSummary
}
public enum WordBankImportPlanner {
    public static func plan(
        archive: WordBankArchive, into current: WordBankSnapshot, destination: ImportDestination = .root,
        now: Date = Date(), newID: () -> UUID = UUID.init, catalogue: DialectCatalogue = .bundled
    ) -> WordBankImportPlan
}
```

Algorithm (order matters: folders, tags, smart folders, entries):

1. **Folders.** For each archive folder, resolve its parent first (an unknown parent or a cycle means "the destination"). A folder whose archive id equals a local folder id maps to it. Otherwise find a sibling under the mapped parent with the same `key(name)`, else create one (id = the file's id if unused, else `newID()`; `sortOrder` = max sibling + 1; blank name becomes "Untitled").
2. **Tags.** Resolve every archive tag record up front (so a full backup imports unused tags too). A dialect tag with no match is created from the file's region/prefectures, filling gaps from the bundled catalogue (match by `tagKey` of name or alias, or by `catalogueID`); region comes from the file, else the first prefecture's `region`, else the catalogue's. **If no region can be found the tag becomes a custom tag** (listed in the summary under custom tags) because `DialectTagValue.region` is required. Tag names on entries with no tag record are resolved the same way. Memoise by archive id and by `tagKey` so one tag is created once.
3. **Smart folders.** Skip one whose `key(name)` already exists; otherwise create it from resolved tag names if at least one resolved.
4. **Entries.** Build the incoming entry (`trimmed()`, folder from `folderID` → mapped folder, else `folderPath` walked from the destination creating segments, else the destination), then match: by id, else by the text + reading rule (use two dictionaries, `byID` and `byTextKey`, built once and updated as entries are added, so 5,000 × 5,000 does not become 25 million comparisons). A match is combined; no match is added, keeping the file's id and dates when unused.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import VerbKit

final class WordBankImportPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func plan(
        _ archive: WordBankArchive, into snapshot: WordBankSnapshot = WordBankSnapshot(),
        destination: ImportDestination = .root
    ) -> WordBankImportPlan {
        WordBankImportPlanner.plan(archive: archive, into: snapshot, destination: destination, now: now)
    }

    private func result(_ plan: WordBankImportPlan, from snapshot: WordBankSnapshot = WordBankSnapshot()) -> WordBankSnapshot {
        plan.changes.applied(to: snapshot)
    }

    private func decode(_ json: String) throws -> WordBankArchive { try WordBankArchive.decode(Data(json.utf8)) }

    func testPathsCreateFoldersAndNamesCreateTags() throws {
        let archive = try decode(#"{"entries":[{"text":"おおきに","folderPath":["Trip","Osaka"],"dialectTagNames":["大阪弁"],"customTagNames":["food"]}]}"#)
        let plan = plan(archive)
        let bank = result(plan)
        XCTAssertEqual(bank.entries.count, 1)
        let folder = bank.folders.first { $0.id == bank.entries[0].folderID }
        XCTAssertEqual(folder?.name, "Osaka")
        XCTAssertEqual(bank.folders.first { $0.id == folder?.parentID }?.name, "Trip")
        XCTAssertEqual(bank.dialectTags.map(\.name), ["大阪弁"])
        XCTAssertEqual(bank.dialectTags.first?.region, .kansai)       // filled in from the catalogue
        XCTAssertEqual(bank.customTags.map(\.name), ["food"])
        XCTAssertEqual(plan.summary.newEntries, 1)
        XCTAssertEqual(plan.summary.newFolders, [["Trip"], ["Trip", "Osaka"]])
        XCTAssertEqual(plan.summary.newDialectTags, ["大阪弁"])
    }

    func testUnknownDialectWithoutRegionBecomesACustomTag() throws {
        let archive = try decode(#"{"entries":[{"text":"x","dialectTagNames":["ほげ弁"]}]}"#)
        let plan = plan(archive)
        XCTAssertTrue(plan.changes.dialectTags.isEmpty)
        XCTAssertEqual(result(plan).customTags.map(\.name), ["ほげ弁"])
        XCTAssertEqual(plan.summary.newCustomTags, ["ほげ弁"])
        XCTAssertEqual(result(plan).entries[0].customTagIDs.count, 1)
    }

    func testDestinationFolderHoldsNewFoldersAndUnfiledEntries() throws {
        let dest = WordBankFolderValue(name: "Packs")
        let snapshot = WordBankSnapshot(folders: [dest])
        let archive = try decode(#"{"entries":[{"text":"a"},{"text":"b","folderPath":["Sub"]}]}"#)
        let bank = result(plan(archive, into: snapshot, destination: .folder(dest.id)), from: snapshot)
        let a = bank.entries.first { $0.text == "a" }!, b = bank.entries.first { $0.text == "b" }!
        XCTAssertEqual(a.folderID, dest.id)
        XCTAssertEqual(bank.folders.first { $0.id == b.folderID }?.parentID, dest.id)
    }

    func testRootDestinationLeavesUnfiledEntriesUnfiled() throws {
        let bank = result(plan(try decode(#"{"entries":[{"text":"a"}]}"#)))
        XCTAssertNil(bank.entries[0].folderID)
    }

    func testSiblingFolderMatchIgnoresCaseAndWidth() throws {
        let existing = WordBankFolderValue(name: "Trip ２０２６")
        let snapshot = WordBankSnapshot(folders: [existing])
        let archive = try decode(#"{"entries":[{"text":"a","folderPath":["trip 2026"]}]}"#)
        let plan = plan(archive, into: snapshot)
        XCTAssertTrue(plan.changes.folders.isEmpty)
        XCTAssertEqual(result(plan, from: snapshot).entries[0].folderID, existing.id)
    }

    func testMatchingByIdThenByTextAndReading() throws {
        let local = WordBankEntryValue(text: "おおきに", reading: "おおきに")
        let snapshot = WordBankSnapshot(entries: [local])
        let byReading = try decode(#"{"entries":[{"text":"オオキニ","reading":"おおきに","senses":[{"meaning":"thanks"}]}]}"#)
        let plan = plan(byReading, into: snapshot)
        XCTAssertEqual(plan.summary.newEntries, 0)
        XCTAssertEqual(plan.summary.combinedEntries, 1)
        XCTAssertEqual(result(plan, from: snapshot).entries.count, 1)
        let otherReading = try decode(#"{"entries":[{"text":"おおきに","reading":"おーきに"}]}"#)
        XCTAssertEqual(self.plan(otherReading, into: snapshot).summary.newEntries, 1)
        let byID = WordBankArchive(entries: [.init(id: local.id, text: "completely different")])
        XCTAssertEqual(self.plan(byID, into: snapshot).summary.newEntries, 0)
    }

    func testTextOnlyMatchesWhenExactlyOneLocalEntryHasThatText() throws {
        let one = WordBankEntryValue(text: "かける", reading: "かける")
        let two = WordBankEntryValue(text: "かける", reading: "かける2")
        let archive = try decode(#"{"entries":[{"text":"かける"}]}"#)
        XCTAssertEqual(plan(archive, into: WordBankSnapshot(entries: [one])).summary.newEntries, 0)
        XCTAssertEqual(plan(archive, into: WordBankSnapshot(entries: [one, two])).summary.newEntries, 1)
    }

    func testCombiningNeverOverwritesAndFillsGaps() throws {
        let local = WordBankEntryValue(text: "おおきに", reading: "おおきに", notes: "mine")
        let snapshot = WordBankSnapshot(entries: [local])
        let archive = try decode(#"{"entries":[{"text":"おおきに","reading":"other","kanjiSpelling":"大きに","notes":"theirs"}]}"#)
        let entry = result(plan(archive, into: snapshot), from: snapshot).entries[0]
        XCTAssertEqual(entry.reading, "おおきに")
        XCTAssertEqual(entry.kanjiSpelling, "大きに")
        XCTAssertTrue(entry.notes!.hasPrefix("mine"))
        XCTAssertTrue(entry.notes!.contains("theirs"))
    }

    func testImportingTheSameFileTwiceChangesNothing() throws {
        let archive = try decode(#"{"entries":[{"text":"おおきに","folderPath":["Trip"],"dialectTagNames":["大阪弁"],"customTagNames":["food"],"notes":"n","senses":[{"meaning":"thanks"}]}],"smartFolders":[{"name":"Kansai","dialectTagNames":["大阪弁"]}]}"#)
        let first = plan(archive)
        let bank = result(first)
        let second = plan(archive, into: bank)
        XCTAssertTrue(second.changes.isEmpty)
        XCTAssertFalse(second.summary.changesAnything)
        XCTAssertEqual(second.summary.unchangedEntries, 1)
    }

    func testRoundTripThroughExportReproducesTheBank() throws {
        let folder = WordBankFolderValue(name: "Trip"), child = WordBankFolderValue(name: "Osaka", parentID: folder.id)
        let tag = DialectTagValue(name: "大阪弁", prefectures: [.osaka], region: .kansai, catalogueID: "osaka")
        let custom = CustomTagValue(name: "food", color: .orange)
        let entry = WordBankEntryValue(
            text: "おおきに", reading: "おおきに", kind: .phrase, senses: [Sense(meaning: "thanks")],
            notes: "n", folderID: child.id, dialectTagIDs: [tag.id], customTagIDs: [custom.id],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let original = WordBankSnapshot(
            entries: [entry], folders: [folder, child], dialectTags: [tag], customTags: [custom],
            smartFolders: [WordBankSmartFolderValue(name: "Kansai", dialectTagIDs: [tag.id], match: .all)]
        )
        let data = try WordBankArchive(snapshot: original, scope: .everything, exportedAt: now).encoded()
        let rebuilt = result(plan(try WordBankArchive.decode(data)))
        XCTAssertEqual(rebuilt.entries, original.entries)
        XCTAssertEqual(rebuilt.folders.map { [$0.id, $0.parentID ?? UUID(uuid: UUID_NULL)] }, original.folders.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }.map { [$0.id, $0.parentID ?? UUID(uuid: UUID_NULL)] })
        XCTAssertEqual(rebuilt.dialectTags, original.dialectTags)
        XCTAssertEqual(rebuilt.customTags, original.customTags)
        XCTAssertEqual(rebuilt.smartFolders.map(\.name), ["Kansai"])
        XCTAssertEqual(rebuilt.smartFolders.first?.dialectTagIDs, [tag.id])
        XCTAssertEqual(rebuilt.smartFolders.first?.match, .all)
    }

    func testSkippedRecordsAreReportedInTheSummary() throws {
        let archive = try decode(#"{"entries":[{"text":"ok"},{"reading":"no text"}]}"#)
        XCTAssertEqual(plan(archive).summary.skipped.count, 1)
    }

    func testBlankFolderNameBecomesUntitled() {
        let archive = WordBankArchive(folders: [.init(name: "  ")], entries: [.init(text: "a")])
        XCTAssertEqual(result(plan(archive)).folders.map(\.name), ["Untitled"])
    }

    func testFolderCycleInTheFileDoesNotHang() {
        let a = UUID(), b = UUID()
        let archive = WordBankArchive(folders: [.init(id: a, name: "A", parentID: b), .init(id: b, name: "B", parentID: a)])
        XCTAssertEqual(result(plan(archive)).folders.count, 2)
    }

    func testFiveThousandEntriesPlanQuickly() {
        let local = (0..<5000).map { WordBankEntryValue(text: "word\($0)", reading: "reading\($0)") }
        let archive = WordBankArchive(entries: (0..<5000).map { .init(text: "word\($0)", reading: "reading\($0)") })
        let started = Date()
        let plan = plan(archive, into: WordBankSnapshot(entries: local))
        XCTAssertEqual(plan.summary.unchangedEntries, 5000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
```

Replace the awkward `UUID_NULL` line in `testRoundTripThroughExportReproducesTheBank` with a plain comparison if it does not compile: compare `Set(rebuilt.folders.map(\.id))` to `Set(original.folders.map(\.id))` and `rebuilt.folders.first { $0.id == child.id }?.parentID` to `folder.id`.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/VerbKit --filter WordBankImportPlannerTests`
Expected: FAIL to compile.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum ImportDestination: Equatable, Sendable {
    case root
    case folder(UUID)
}

public struct WordBankImportSummary: Equatable, Sendable {
    public var newEntries = 0
    public var combinedEntries = 0
    public var unchangedEntries = 0
    public var newFolders: [[String]] = []
    public var newDialectTags: [String] = []
    public var newCustomTags: [String] = []
    public var newSmartFolders: [String] = []
    public var skipped: [WordBankArchive.Skipped] = []

    public init() {}

    public var changesAnything: Bool {
        newEntries > 0 || combinedEntries > 0 || !newFolders.isEmpty || !newDialectTags.isEmpty
            || !newCustomTags.isEmpty || !newSmartFolders.isEmpty
    }
}

public struct WordBankImportPlan: Equatable, Sendable {
    public var changes: WordBankChanges
    public var summary: WordBankImportSummary
}

public enum WordBankImportPlanner {
    public static func plan(
        archive: WordBankArchive, into current: WordBankSnapshot, destination: ImportDestination = .root,
        now: Date = Date(), newID: () -> UUID = UUID.init, catalogue: DialectCatalogue = .bundled
    ) -> WordBankImportPlan {
        var run = Run(current: current, destination: destination, now: now, newID: newID, catalogue: catalogue)
        run.importFolders(archive.folders)
        run.importTags(archive)
        run.importSmartFolders(archive.smartFolders)
        run.importEntries(archive.entries)
        return run.finish(skipped: archive.skipped)
    }

    private enum LocalTag { case dialect(UUID), custom(UUID) }

    private struct Run {
        var snapshot: WordBankSnapshot                  // grows as things are added
        let destination: UUID?
        let destinationDepth: Int
        let now: Date
        let newID: () -> UUID
        let catalogue: DialectCatalogue
        var changes = WordBankChanges()
        var summary = WordBankImportSummary()
        var usedIDs: Set<UUID>
        var newFolderIDs: [UUID] = []
        var folderMap: [UUID: UUID] = [:]               // file id -> local id
        var dialectByFileID: [UUID: LocalTag] = [:]
        var customByFileID: [UUID: LocalTag] = [:]
        var entryIndexByID: [UUID: Int] = [:]
        var entryIndexesByText: [String: [Int]] = [:]
        var touched: [UUID: WordBankEntryValue] = [:]
        var touchedOrder: [UUID] = []

        init(current: WordBankSnapshot, destination: ImportDestination, now: Date, newID: @escaping () -> UUID, catalogue: DialectCatalogue) {
            snapshot = current
            if case .folder(let id) = destination, current.folders.contains(where: { $0.id == id }) {
                self.destination = id
                destinationDepth = FolderTree(current.folders).path(of: id).count
            } else {
                self.destination = nil
                destinationDepth = 0
            }
            self.now = now
            self.newID = newID
            self.catalogue = catalogue
            usedIDs = Set(current.entries.map(\.id) + current.folders.map(\.id) + current.dialectTags.map(\.id)
                + current.customTags.map(\.id) + current.smartFolders.map(\.id))
            for (index, entry) in current.entries.enumerated() {
                entryIndexByID[entry.id] = index
                entryIndexesByText[JapaneseNormalizer.key(entry.text), default: []].append(index)
            }
        }

        mutating func freshID(preferring id: UUID?) -> UUID {
            if let id, !usedIDs.contains(id) { usedIDs.insert(id); return id }
            var id = newID()
            while !usedIDs.insert(id).inserted { id = newID() }
            return id
        }

        // MARK: Folders

        mutating func childFolder(named rawName: String, under parent: UUID?, preferring id: UUID? = nil) -> UUID {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = name.isEmpty ? "Untitled" : name
            let key = JapaneseNormalizer.key(shown)
            if let existing = snapshot.folders.first(where: { $0.parentID == parent && JapaneseNormalizer.key($0.name) == key }) {
                return existing.id
            }
            let order = (snapshot.folders.filter { $0.parentID == parent }.map(\.sortOrder).max() ?? -1) + 1
            let folder = WordBankFolderValue(id: freshID(preferring: id), name: shown, parentID: parent, sortOrder: order)
            snapshot.folders.append(folder)
            changes.folders.append(folder)
            newFolderIDs.append(folder.id)
            return folder.id
        }

        mutating func resolve(folder id: UUID, in byID: [UUID: WordBankArchive.Folder], visiting: Set<UUID> = []) -> UUID? {
            if let done = folderMap[id] { return done }
            guard let folder = byID[id], !visiting.contains(id) else { return nil }
            let parent: UUID?
            if let parentID = folder.parentID, byID[parentID] != nil {
                parent = resolve(folder: parentID, in: byID, visiting: visiting.union([id])) ?? destination
            } else {
                parent = destination
            }
            let local: UUID
            if snapshot.folders.contains(where: { $0.id == id }) {
                local = id
            } else {
                local = childFolder(named: folder.name, under: parent, preferring: id)
            }
            folderMap[id] = local
            return local
        }

        mutating func importFolders(_ folders: [WordBankArchive.Folder]) {
            let byID = Dictionary(folders.compactMap { folder in folder.id.map { ($0, folder) } }, uniquingKeysWith: { first, _ in first })
            for folder in folders {
                if let id = folder.id { _ = resolve(folder: id, in: byID) } else {
                    _ = childFolder(named: folder.name, under: destination)
                }
            }
        }

        mutating func folder(forPath path: [String]) -> UUID? {
            var parent = destination
            for segment in path { parent = childFolder(named: segment, under: parent) }
            return parent
        }

        // MARK: Tags

        mutating func importTags(_ archive: WordBankArchive) {
            for record in archive.dialectTags { _ = dialect(record) }
            for record in archive.customTags { _ = custom(record) }
        }

        mutating func dialect(_ record: WordBankArchive.DialectTag) -> LocalTag {
            if let id = record.id, let known = dialectByFileID[id] { return known }
            let key = JapaneseNormalizer.tagKey(record.name)
            let local: LocalTag
            if let existing = snapshot.dialectTags.first(where: {
                $0.id == record.id || (record.catalogueID != nil && $0.catalogueID == record.catalogueID)
                    || JapaneseNormalizer.tagKey($0.name) == key
            }) {
                local = .dialect(existing.id)
            } else if let existing = snapshot.customTags.first(where: { JapaneseNormalizer.tagKey($0.name) == key }) {
                local = .custom(existing.id)
            } else {
                let known = catalogue.dialects.first {
                    $0.id == record.catalogueID || JapaneseNormalizer.tagKey($0.name) == key
                        || $0.aliases.contains { JapaneseNormalizer.tagKey($0) == key }
                }
                let prefectures = record.prefectures ?? known?.prefectures ?? []
                if let region = record.region ?? prefectures.first?.region ?? known?.region {
                    let tag = DialectTagValue(
                        id: freshID(preferring: record.id), name: record.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        romaji: record.romaji ?? known?.romaji, prefectures: prefectures, region: region,
                        catalogueID: record.catalogueID ?? known?.id
                    )
                    snapshot.dialectTags.append(tag)
                    changes.dialectTags.append(tag)
                    summary.newDialectTags.append(tag.name)
                    local = .dialect(tag.id)
                } else {
                    local = custom(WordBankArchive.CustomTag(id: record.id, name: record.name))
                }
            }
            if let id = record.id { dialectByFileID[id] = local }
            return local
        }

        mutating func custom(_ record: WordBankArchive.CustomTag) -> LocalTag {
            if let id = record.id, let known = customByFileID[id] { return known }
            let key = JapaneseNormalizer.tagKey(record.name)
            let local: LocalTag
            if let existing = snapshot.customTags.first(where: { $0.id == record.id || JapaneseNormalizer.tagKey($0.name) == key }) {
                local = .custom(existing.id)
            } else {
                let tag = CustomTagValue(
                    id: freshID(preferring: record.id), name: record.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    color: record.color ?? .gray
                )
                snapshot.customTags.append(tag)
                changes.customTags.append(tag)
                summary.newCustomTags.append(tag.name)
                local = .custom(tag.id)
            }
            if let id = record.id { customByFileID[id] = local }
            return local
        }

        // MARK: Smart folders

        mutating func importSmartFolders(_ folders: [WordBankArchive.SmartFolder]) {
            for folder in folders {
                let key = JapaneseNormalizer.key(folder.name)
                guard !snapshot.smartFolders.contains(where: { JapaneseNormalizer.key($0.name) == key }) else { continue }
                var dialectIDs: [UUID] = [], customIDs: [UUID] = []
                for name in folder.dialectTagNames {
                    switch dialect(.init(name: name)) { case .dialect(let id): dialectIDs.append(id); case .custom(let id): customIDs.append(id) }
                }
                for name in folder.customTagNames {
                    switch custom(.init(name: name)) { case .custom(let id), .dialect(let id): customIDs.append(id) }
                }
                guard !dialectIDs.isEmpty || !customIDs.isEmpty else { continue }
                let order = (snapshot.smartFolders.map(\.sortOrder).max() ?? -1) + 1
                let smart = WordBankSmartFolderValue(
                    id: freshID(preferring: nil), name: folder.name, dialectTagIDs: dialectIDs,
                    customTagIDs: customIDs, match: folder.match, sortOrder: order
                )
                snapshot.smartFolders.append(smart)
                changes.smartFolders.append(smart)
                summary.newSmartFolders.append(smart.name)
            }
        }

        // MARK: Entries

        mutating func importEntries(_ entries: [WordBankArchive.Entry]) {
            for record in entries { importEntry(record) }
        }

        mutating func importEntry(_ record: WordBankArchive.Entry) {
            var folderID: UUID? = destination
            if let id = record.folderID, let mapped = folderMap[id] ?? (snapshot.folders.contains { $0.id == id } ? id : nil) {
                folderID = mapped
            } else if !record.folderPath.isEmpty {
                folderID = folder(forPath: record.folderPath)
            }
            var dialectIDs: [UUID] = [], customIDs: [UUID] = []
            func add(_ tag: LocalTag) {
                switch tag {
                case .dialect(let id): if !dialectIDs.contains(id) { dialectIDs.append(id) }
                case .custom(let id): if !customIDs.contains(id) { customIDs.append(id) }
                }
            }
            for id in record.dialectTagIDs { if let known = dialectByFileID[id] { add(known) } }
            for name in record.dialectTagNames { add(dialect(.init(name: name))) }
            for id in record.customTagIDs { if let known = customByFileID[id] { add(known) } }
            for name in record.customTagNames { add(custom(.init(name: name))) }

            let created = record.createdAt ?? now
            let incoming = WordBankEntryValue(
                id: record.id ?? UUID(), text: record.text, reading: record.reading, kanjiSpelling: record.kanjiSpelling,
                kind: record.kind, wordClass: record.wordClass, senses: record.senses, equivalents: record.equivalents,
                linkedWordID: record.linkedWordID, linkedFormID: record.linkedFormID, notes: record.notes,
                folderID: folderID, dialectTagIDs: dialectIDs, customTagIDs: customIDs,
                createdAt: created, updatedAt: record.updatedAt ?? created
            ).trimmed()

            if let index = match(incoming) {
                let local = snapshot.entries[index]
                let combined = WordBankEntryCombiner.combine(
                    local: local, incoming: incoming, importedFolderID: folderID, importedOn: now, now: now
                )
                if combined.changed { summary.combinedEntries += 1 } else { summary.unchangedEntries += 1 }
                if combined.entry != local {
                    snapshot.entries[index] = combined.entry
                    touch(combined.entry)
                }
            } else {
                var entry = incoming
                entry.id = freshID(preferring: record.id)
                snapshot.entries.append(entry)
                entryIndexByID[entry.id] = snapshot.entries.count - 1
                entryIndexesByText[JapaneseNormalizer.key(entry.text), default: []].append(snapshot.entries.count - 1)
                touch(entry)
                summary.newEntries += 1
            }
        }

        func match(_ incoming: WordBankEntryValue) -> Int? {
            if let index = entryIndexByID[incoming.id] { return index }
            let candidates = entryIndexesByText[JapaneseNormalizer.key(incoming.text)] ?? []
            if let reading = incoming.reading {
                let key = JapaneseNormalizer.key(reading)
                return candidates.first { JapaneseNormalizer.key(snapshot.entries[$0].reading ?? "") == key }
            }
            return candidates.count == 1 ? candidates[0] : nil
        }

        mutating func touch(_ entry: WordBankEntryValue) {
            if touched[entry.id] == nil { touchedOrder.append(entry.id) }
            touched[entry.id] = entry
        }

        // MARK: Result

        mutating func finish(skipped: [WordBankArchive.Skipped]) -> WordBankImportPlan {
            changes.entries = touchedOrder.compactMap { touched[$0] }
            let tree = FolderTree(snapshot.folders)
            summary.newFolders = newFolderIDs.map { Array(tree.path(of: $0).dropFirst(destinationDepth).map(\.name)) }
            summary.skipped = skipped
            return WordBankImportPlan(changes: changes, summary: summary)
        }
    }
}
```

Compile notes for the executor: `DialectRecord.id`, `.aliases`, `.romaji`, `.prefectures`, `.region` and `Prefecture.region` exist (checked 2026-10-06). `Run` is a struct mutated through `var run`; the nested `match` reads `snapshot` so it must not be `mutating`. If `switch` pattern `case .custom(let id), .dialect(let id)` is rejected, split into two cases.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/VerbKit --filter WordBankImportPlannerTests`
Expected: PASS (14 tests). If `testImportingTheSameFileTwiceChangesNothing` fails, print `second.summary` and `second.changes`: the usual cause is a field that is `trimmed()` on the way in but compared untrimmed, or tag ids that differ in order.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/WordBank/WordBankImportPlanner.swift Packages/VerbKit/Tests/VerbKitTests/WordBankImportPlannerTests.swift
git commit -m "Word Bank import: plan and preview from a file, without touching anything"
```

---

### Task 6: Backups and the transfer coordinator

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/WordBank/WordBankBackupStore.swift`, `.../WordBank/WordBankTransfer.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/WordBankBackupTests.swift`

**Interfaces:**
- Consumes: `WordBankArchive`, `WordBankChanges`, `WordBankImportPlanner`, `WordBankStore.snapshot/apply`.
- Produces:

```swift
public struct WordBankBackup: Identifiable, Equatable, Sendable {
    public var id: String            // file name
    public var url: URL
    public var createdAt: Date
}
public final class WordBankBackupStore: @unchecked Sendable {   // plain class: file system only
    public init(directory: URL, keeping: Int = 3, now: @escaping () -> Date = Date.init)
    @discardableResult public func backUp(_ snapshot: WordBankSnapshot) throws -> WordBankBackup
    public func backups() -> [WordBankBackup]                    // newest first
    public func archive(of backup: WordBankBackup) throws -> WordBankArchive
}
public enum WordBankTransferError: Error, Equatable, Sendable { case backupFailed, saveFailed }
@MainActor public final class WordBankTransfer {
    public init(store: WordBankStore, backups: WordBankBackupStore, now: @escaping () -> Date = Date.init)
    public func plan(_ archive: WordBankArchive, destination: ImportDestination) -> WordBankImportPlan
    /// Backs up the current bank (skipped when it is empty), then applies the plan.
    public func perform(_ plan: WordBankImportPlan) throws
    /// Backs up the current bank, then makes the bank exactly what the backup holds.
    public func restore(_ backup: WordBankBackup) throws
}
```

Backups are full archives (`.everything` scope) named `Backup yyyy-MM-dd HH.mm.ss.wordbank`, with ` (2)`, ` (3)` appended if the name exists; `createdAt` is the file's creation date (fall back to the modification date). After writing, all but the newest `keeping` are removed.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import VerbKit

@MainActor
final class WordBankBackupTests: XCTestCase {
    private var directory: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("wb-backups-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func backupStore(keeping: Int = 3) -> WordBankBackupStore {
        WordBankBackupStore(directory: directory, keeping: keeping, now: { [unowned self] in self.clock })
    }
    private func tick() { clock = clock.addingTimeInterval(61) }

    func testBackUpWritesAReadableArchive() throws {
        let store = backupStore()
        let entry = WordBankEntryValue(text: "おおきに")
        let backup = try store.backUp(WordBankSnapshot(entries: [entry]))
        XCTAssertTrue(backup.id.hasSuffix(".wordbank"))
        XCTAssertEqual(try store.archive(of: backup).entries.map(\.text), ["おおきに"])
    }

    func testOnlyTheNewestThreeAreKeptAndListedNewestFirst() throws {
        let store = backupStore()
        var names: [String] = []
        for number in 1...5 {
            names.append(try store.backUp(WordBankSnapshot(entries: [WordBankEntryValue(text: "e\(number)")])).id)
            tick()
        }
        XCTAssertEqual(store.backups().map(\.id), Array(names.suffix(3).reversed()))
    }

    func testSameSecondBackupsDoNotOverwrite() throws {
        let store = backupStore()
        let first = try store.backUp(WordBankSnapshot()), second = try store.backUp(WordBankSnapshot())
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(store.backups().count, 2)
    }

    func testBackupsOfAMissingDirectoryIsEmpty() {
        XCTAssertTrue(backupStore().backups().isEmpty)
    }

    // MARK: Transfer

    private final class Persister: WordBankPersisting {
        var snapshot = WordBankSnapshot()
        var failing = false
        func load() throws -> WordBankSnapshot { snapshot }
        func apply(_ changes: WordBankChanges) throws {
            if failing { throw NSError(domain: "t", code: 1) }
            snapshot = changes.applied(to: snapshot)
        }
        func upsert(entry: WordBankEntryValue) throws { snapshot = { var c = WordBankChanges(); c.entries = [entry]; return c.applied(to: snapshot) }() }
        func delete(entryIDs: [UUID]) throws {}
        func upsert(folder: WordBankFolderValue) throws {}
        func delete(folderIDs: [UUID]) throws {}
        func upsert(dialectTag: DialectTagValue) throws {}
        func upsert(customTag: CustomTagValue) throws {}
        func delete(dialectTagIDs: [UUID], customTagIDs: [UUID]) throws {}
        func upsert(smartFolder: WordBankSmartFolderValue) throws {}
        func delete(smartFolderIDs: [UUID]) throws {}
    }

    private func transfer(bank: [WordBankEntryValue] = []) -> (WordBankTransfer, WordBankStore, Persister, WordBankBackupStore) {
        let persister = Persister()
        persister.snapshot = WordBankSnapshot(entries: bank)
        let store = WordBankStore(persisting: persister, now: { [unowned self] in self.clock })
        let backups = backupStore()
        return (WordBankTransfer(store: store, backups: backups, now: { [unowned self] in self.clock }), store, persister, backups)
    }

    func testImportBacksUpTheOldBankFirstThenApplies() throws {
        let old = WordBankEntryValue(text: "old")
        let (transfer, store, _, backups) = transfer(bank: [old])
        let archive = WordBankArchive(entries: [.init(text: "new")])
        try transfer.perform(transfer.plan(archive, destination: .root))
        XCTAssertEqual(Set(store.entries.map(\.text)), ["old", "new"])
        let saved = try backups.archive(of: backups.backups()[0])
        XCTAssertEqual(saved.entries.map(\.text), ["old"])
    }

    func testEmptyBankIsNotBackedUp() throws {
        let (transfer, _, _, backups) = transfer()
        try transfer.perform(transfer.plan(WordBankArchive(entries: [.init(text: "new")]), destination: .root))
        XCTAssertTrue(backups.backups().isEmpty)
    }

    func testNothingToDoMakesNoBackupAndNoWrite() throws {
        let entry = WordBankEntryValue(text: "same")
        let (transfer, _, _, backups) = transfer(bank: [entry])
        let archive = WordBankArchive(entries: [.init(id: entry.id, text: "same")])
        try transfer.perform(transfer.plan(archive, destination: .root))
        XCTAssertTrue(backups.backups().isEmpty)
    }

    func testFailedSaveThrowsAndLeavesTheBankAlone() {
        let (transfer, store, persister, _) = transfer(bank: [WordBankEntryValue(text: "old")])
        persister.failing = true
        XCTAssertThrowsError(try transfer.perform(transfer.plan(WordBankArchive(entries: [.init(text: "new")]), destination: .root))) {
            XCTAssertEqual($0 as? WordBankTransferError, .saveFailed)
        }
        XCTAssertEqual(store.entries.map(\.text), ["old"])
    }

    func testRestoreReplacesTheBankAndBacksUpTheCurrentOneFirst() throws {
        let original = WordBankEntryValue(text: "original")
        let (transfer, store, persister, backups) = transfer(bank: [original])
        let wanted = try backups.backUp(persister.snapshot)
        tick()
        try store.save(WordBankEntryValue(text: "added later"))
        tick()
        try transfer.restore(wanted)
        XCTAssertEqual(store.entries.map(\.text), ["original"])
        let newest = try backups.archive(of: backups.backups()[0])
        XCTAssertEqual(Set(newest.entries.map(\.text)), ["original", "added later"])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path Packages/VerbKit --filter WordBankBackupTests`
Expected: FAIL to compile.

- [ ] **Step 3: Implement**

`WordBankBackupStore.swift`:

```swift
import Foundation

public struct WordBankBackup: Identifiable, Equatable, Sendable {
    public var id: String
    public var url: URL
    public var createdAt: Date
}

/// Full-bank `.wordbank` files, newest three kept. The app takes one before every import
/// and restore, so any of them can be undone.
public final class WordBankBackupStore: @unchecked Sendable {
    private let directory: URL
    private let keeping: Int
    private let now: () -> Date

    public init(directory: URL, keeping: Int = 3, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.keeping = max(1, keeping)
        self.now = now
    }

    @discardableResult
    public func backUp(_ snapshot: WordBankSnapshot) throws -> WordBankBackup {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try WordBankArchive(snapshot: snapshot, scope: .everything, exportedAt: now()).encoded()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = "Backup \(formatter.string(from: now()))"
        var name = "\(base).wordbank"
        var number = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "\(base) (\(number)).wordbank"
            number += 1
        }
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        for old in backups().dropFirst(keeping) { try? FileManager.default.removeItem(at: old.url) }
        return WordBankBackup(id: name, url: url, createdAt: now())
    }

    public func backups() -> [WordBankBackup] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == "wordbank" }.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return WordBankBackup(
                id: url.lastPathComponent, url: url,
                createdAt: values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            )
        }
        .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }

    public func archive(of backup: WordBankBackup) throws -> WordBankArchive {
        try WordBankArchive.decode(try Data(contentsOf: backup.url))
    }
}
```

File creation dates come from the real clock, not the injected one, so the "newest three kept" test relies on files being written in order; if two files get the same creation date the tie-break is the name, which sorts by timestamp then suffix. If `testOnlyTheNewestThreeAreKeptAndListedNewestFirst` is flaky for that reason, parse the date back out of the file name instead of using file attributes.

`WordBankTransfer.swift`:

```swift
import Foundation

public enum WordBankTransferError: Error, Equatable, Sendable {
    case backupFailed
    case saveFailed
}

@MainActor
public final class WordBankTransfer {
    private let store: WordBankStore
    private let backups: WordBankBackupStore

    public init(store: WordBankStore, backups: WordBankBackupStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.backups = backups
    }

    public func plan(_ archive: WordBankArchive, destination: ImportDestination) -> WordBankImportPlan {
        WordBankImportPlanner.plan(archive: archive, into: store.snapshot, destination: destination)
    }

    public func perform(_ plan: WordBankImportPlan) throws {
        guard !plan.changes.isEmpty else { return }
        try backUpCurrentBank()
        try apply(plan.changes)
    }

    public func restore(_ backup: WordBankBackup) throws {
        let archive: WordBankArchive
        do { archive = try backups.archive(of: backup) } catch { throw WordBankTransferError.backupFailed }
        let target = WordBankImportPlanner.plan(archive: archive, into: WordBankSnapshot()).changes.applied(to: WordBankSnapshot())
        try backUpCurrentBank()
        try apply(WordBankChanges.replacing(store.snapshot, with: target))
    }

    private func backUpCurrentBank() throws {
        let snapshot = store.snapshot
        guard !(snapshot.entries.isEmpty && snapshot.folders.isEmpty && snapshot.dialectTags.isEmpty
            && snapshot.customTags.isEmpty && snapshot.smartFolders.isEmpty) else { return }
        do { try backups.backUp(snapshot) } catch { throw WordBankTransferError.backupFailed }
    }

    private func apply(_ changes: WordBankChanges) throws {
        do { try store.apply(changes) } catch { throw WordBankTransferError.saveFailed }
    }
}
```

Restoring a backup always plans into an **empty** bank, so every record is new and keeps its file id (the "new records keep ids" rule); `replacing` then turns the live bank into that exact snapshot. In `testRestoreReplacesTheBank…`, `try store.save(...)` returns a value; add `_ =` if the compiler warns.

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path Packages/VerbKit`
Expected: exit code 0.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/WordBank Packages/VerbKit/Tests/VerbKitTests/WordBankBackupTests.swift
git commit -m "Word Bank: automatic backups before import and restore"
```

---

### Task 7: The app: file type, export, import, restore

**Files:**
- Modify: `project.yml` (exported type, document type)
- Create: `App/WordBank/WordBankFileType.swift`, `App/WordBank/WordBankExportSheet.swift`, `App/WordBank/WordBankImportSheet.swift`, `App/WordBank/WordBankBackupsView.swift`
- Modify: `App/JPVerbConjugationApp.swift` (make the backup store and `WordBankTransfer`, inject), `App/WordBank/WordBankListView.swift` (More menu: Export…, Import…), `App/RootView.swift` (`.onOpenURL` for `.wordbank` files), `App/WordBank/WordBankTab.swift` (a pending-import state it can show the sheet from), `App/SettingsView.swift` (Word Bank › Restore backup)

No unit tests: the logic is covered in Tasks 1–6. Verify by build and on the simulator.

- [ ] **Step 1: Declare the file type** in `project.yml` under the app target's `info.properties`:

```yaml
        UTExportedTypeDeclarations:
          - UTTypeIdentifier: dev.martinloeseth.jpverbconjugation.wordbank
            UTTypeDescription: Word Bank
            UTTypeConformsTo:
              - public.json
            UTTypeTagSpecification:
              public.filename-extension:
                - wordbank
              public.mime-type:
                - application/x-wordbank+json
        CFBundleDocumentTypes:
          - CFBundleTypeName: Word Bank
            CFBundleTypeRole: Editor
            LSHandlerRank: Owner
            LSItemContentTypes:
              - dev.martinloeseth.jpverbconjugation.wordbank
```

`App/WordBank/WordBankFileType.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let wordBank = UTType(exportedAs: "dev.martinloeseth.jpverbconjugation.wordbank", conformingTo: .json)
}

/// For `fileExporter`: the bytes of a `.wordbank` file.
struct WordBankFile: FileDocument {
    static var readableContentTypes: [UTType] { [.wordBank] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
```

- [ ] **Step 2: Wire the services.** In `App/JPVerbConjugationApp.swift`, where `WordBankStore` is created: build `WordBankBackupStore(directory: <App Group container>/WordBankBackups)` (use `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: VerbModelContainer.appGroupIdentifier)`, falling back to Application Support), create `WordBankTransfer(store:backups:)`, keep both in `@State`, and inject them with `.environment(...)` next to the store. `WordBankTransfer` and `WordBankBackupStore` are not `@Observable`; pass them with `.environment(transfer)` after making `WordBankTransfer` `@Observable`, or via a small `EnvironmentKey`. Choose the `EnvironmentKey` route (`WordBankTransferKey`) so VerbKit stays free of `Observation` for these types.

- [ ] **Step 3: Export sheet.** `WordBankExportSheet` takes the scopes that make sense where it was opened: **Everything** always; **This folder** when the user is inside a folder; **These results** when a search is active (pass the result ids); **Selected entries** in edit mode. Show each with its entry count. Below the choice: a `ShareLink(item: url)` for a temp file named `suggestedFileName + ".wordbank"` written to `FileManager.default.temporaryDirectory`, and a **Save to Files** button that presents `.fileExporter(isPresented:document:contentType:defaultFilename:)` with `WordBankFile`. Build the archive with `WordBankArchive(snapshot: store.snapshot, scope:)`. Add **Export…** to the list's More menu (`App/WordBank/WordBankListView.swift`, the `Menu("More"…)` block) and to a folder's context menu in `FolderActions.swift`.

- [ ] **Step 4: Import sheet.** `WordBankImportSheet(url: URL)`:
  - on appear: `url.startAccessingSecurityScopedResource()` (balance with `defer`), read the data, `WordBankArchive.decode`. Errors become a plain message: `.newerVersion` → "This file was made by a newer version of the app. Update the app to import it."; `.tooLarge` → "This file is larger than 20 MB."; `.notAWordBank` → "This isn't a Word Bank file."
  - a destination picker: **Word Bank root** or **Into a folder…** (present the existing `FolderPicker(title: "Import into…")`);
  - the preview, recomputed with `transfer.plan(archive, destination:)` whenever the destination changes: rows for new entries, combined with existing ones, unchanged, new folders (as `A › B` paths), new tags, new smart folders, and a "Skipped" section with each reason and record number; if `!summary.changesAnything` show "Everything in this file is already in your Word Bank." and disable Import;
  - **Import** calls `try transfer.perform(plan)`; success dismisses and shows a short "Imported n entries" confirmation; `WordBankTransferError.backupFailed` → "Couldn't make a backup first, so nothing was imported."; `.saveFailed` → "Couldn't save. Nothing was changed."
  - Add **Import…** to the More menu using `.fileImporter(isPresented:allowedContentTypes: [.wordBank, .json])` and present the sheet with the chosen URL.

- [ ] **Step 5: Open from outside the app.** In `App/RootView.swift`'s `open(_ url:)`, before route handling: if `url.isFileURL && url.pathExtension == "wordbank"`, switch to the Word Bank tab and set a `pendingImport: URL?` the Word Bank tab observes to present `WordBankImportSheet`. Keep the existing route handling untouched for other URLs.

- [ ] **Step 6: Restore.** `App/WordBank/WordBankBackupsView.swift`: a list of `WordBankBackupStore.backups()` showing the date and the entry count (read with `archive(of:)`), an empty state ("No backups yet. One is made before every import."), and a confirmation dialog per row: "Replace your Word Bank with this backup? A backup of the current one is made first." → `transfer.restore(backup)`, with errors shown as above. Link it from `App/SettingsView.swift` as a "Word Bank" section row **Restore backup** (the section that already holds "Suggest while typing").

- [ ] **Step 7: Build.**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=F8A1F047-9215-4C1F-8202-661A87975FB9' -derivedDataPath <scratch>/dd build 2>&1 | grep -E "warning:|error:|BUILD"
```

Expected: `BUILD SUCCEEDED` and no new warnings.

- [ ] **Step 8: Simulator check** (iPhone only; iPad and macOS stay parked; remember the first tap after launch is often dropped and screenshots lag one step). Report what you saw for each:
  1. With a few entries, folders and tags in the bank: More › Export… › Everything › **Save to Files** › On My iPhone.
  2. Export again with **This folder** from inside a folder.
  3. Delete some entries, then More › Import… and pick the saved "Word Bank" file: the preview shows the deleted entries as new, the rest as unchanged; import; they come back, in their folders, with their tags.
  4. Import the same file again: "Everything in this file is already in your Word Bank."
  5. Import the folder export **Into a folder…**: it is created inside the chosen folder.
  6. Settings › Word Bank › Restore backup: two or more backups are listed with counts; restore the oldest and confirm the bank matches it.
  7. Best effort: `xcrun simctl openurl booted "file://<path to a .wordbank file>"` opens the import sheet; if the simulator can't do it, say so.
  8. Hand-written file: put `{"entries":[{"text":"おおきに","folderPath":["Test","Osaka"],"dialectTagNames":["大阪弁"]}]}` in a file, save it to Files from another app or the Files app, and import it; a Test › Osaka folder and a 大阪弁 tag appear.

- [ ] **Step 9: Commit.**

```bash
git add project.yml App
git commit -m "Word Bank import and export screens, backups and restore"
```

---

### Task 8: Final checks and spec

**Files:**
- Modify: `docs/superpowers/specs/2026-10-03-word-bank-design.md`

- [ ] **Step 1: Whole suite and data check.** `swift test --package-path Packages/VerbKit` exits 0; `python3 scripts/update_data.py --check` prints "data is up to date". Record the test count (new tests: archive 8, export 8, combiner 9, changes 4+persisting 2+store 2, planner 14, backups 9).
- [ ] **Step 2: iOS build** with no new warnings (command in Task 7). The macOS scheme is not built (parked).
- [ ] **Step 3: Fresh install and over-existing install.** Fresh: empty Word Bank, More › Import… with a saved file works and shows no backup entry in Settings (empty bank is never backed up). Over an existing install with Word Bank data: entries survive the update, and Export then Import of everything reports all unchanged.
- [ ] **Step 4: Update the spec.** In "Import and export":
  - add `smartFolders` (name, tag names, match) to the file format paragraph and say a full backup includes them;
  - say a dialect tag from a file with no region, prefecture or catalogue match becomes a custom tag;
  - say new folders, tags and entries keep the file's ids when unused, so a restore reproduces the bank exactly;
  - say Restore backup replaces the bank after taking a backup of the current one, and an empty bank is never backed up;
  - say review history is not in the file yet (milestone 5 adds it; unknown fields are ignored, so older apps can read newer files of the same major version);
  - in "Milestones" mark 2 as done with the date, and note the iPad and macOS checks are still parked.
- [ ] **Step 5: Commit, push, PR.**

```bash
git add docs/superpowers/specs/2026-10-03-word-bank-design.md
git commit -m "Spec: milestone 2 done, and what changed from the plan"
git push -u origin claude/word-bank-import-export
gh pr create --draft --title "Word Bank import and export" --body-file <description file>
```

PR description: what shipped (file format, export scopes, import preview and matching, backups and restore), what was checked on the simulator and what was not (item 7 and 8 of Task 7 if skipped), deviations from the spec (smart folders in the file, dialect tags without a region become custom tags, ids kept), the test count, and "iPad and macOS checks parked". End with the footer from the attribution reminder.

---

## Self-review

**Spec coverage.** File format with header, folders, tags, entries, folder paths, tag names, only `text` required, unknown fields ignored (Task 1). Export of everything, one folder (root), selection, search results (Task 2; search results use `.entries`); share sheet and `fileExporter` (Task 7). Review history in a full backup: deliberately not included, review does not exist until milestone 5 (noted in Task 8). Import flow: pick file or open from outside, destination (root or into a folder), preview, one save or nothing, automatic backup keeping three, restore in Settings (Tasks 4, 5, 6, 7). Matching for folders, tags, entries incl. the ambiguous-text rule (Task 5). Combining rules incl. notes heading, folder, dates, idempotency (Tasks 3, 5). Validation: newer version refused, skipped records listed, 20 MB cap (Tasks 1, 5, 7). Logic in VerbKit and unit-tested (Tasks 1–6). Starter packs depend on `WordBankArchive` and `WordBankImportPlanner` only; the "no tags created" option they need is a small parameter to add in the packs plan.

**Placeholders.** None: every code step has code. Task 7 UI steps describe views by behaviour and exact file, API and message text rather than full SwiftUI code, because the UI follows existing patterns (`FolderPicker`, sheets, Settings sections) that the executor has to read; each ends in a build and a numbered simulator check.

**Type consistency.** `WordBankArchive.Entry` fields match the combiner and planner use; `WordBankChanges` field names are the same in Tasks 4, 5 and 6; `ImportDestination`, `WordBankImportPlan.changes/summary`, `WordBankTransfer.perform/restore/plan` are used with the same names in Tasks 5, 6 and 7; `WordBankStore.snapshot` and `apply` are defined in Task 4 before use in Task 6.
