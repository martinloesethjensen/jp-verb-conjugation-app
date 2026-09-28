# Native Core App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Tauri/React web app with a native SwiftUI app (iOS/iPadOS/macOS) that has full feature parity — verb list, search/filter, verb detail with grouped conjugation forms, examples, Kahoot-style quiz, tri-state appearance — plus persisted preferences, backed by a GitHub-sourced verb data set synced into a local SwiftData cache.

**Architecture:** A local Swift package (`VerbKit`) holds all platform-agnostic logic (models, quiz generation, data fetch/sync, SwiftData persistence) so it's unit-testable via `swift test` without any UI. Two XcodeGen-generated app targets (`JPVerbConjugation_iOS`, `JPVerbConjugation_macOS`) share the same `App/` SwiftUI source folder and depend on `VerbKit`. Verb data lives in `data/verbs.json` + `data/manifest.json` in this repo, fetched via `raw.githubusercontent.com` and cached in SwiftData; the first launch requires a successful fetch, later launches work offline with silent background re-sync.

**Tech Stack:** Swift 5 (language mode) on Xcode 27 / Swift 6.4 toolchain, SwiftUI, SwiftData, `URLSession`, `NWPathMonitor`, `CryptoKit`, XCTest, XcodeGen 2.46 for project generation.

**Spec:** [docs/superpowers/specs/2026-09-23-native-apple-rewrite-design.md](../specs/2026-09-23-native-apple-rewrite-design.md)

## Global Constraints

- Deployment target: **iOS 26.0 / macOS 26.0 minimum** (raised
  mid-implementation from the original iOS 17.0/macOS 14.0 — see spec
  section 10, added after Task 16 — specifically because Liquid Glass
  APIs `.glassEffect()`/`.buttonStyle(.glass)`/`.buttonStyle(.glassProminent)`
  require it; Task 17 updates `project.yml`/`Package.swift` accordingly.
  Backward-compatible with everything already built — SwiftData/
  Observation/NavigationSplitView are all available well below iOS 17
  already, so this only raises the floor, it doesn't require touching
  earlier tasks' logic).
- Bundle ID: `dev.martinloeseth.jpverbconjugation`; App Group:
  `group.dev.martinloeseth.jpverbconjugation` (spec section 1).
- No Mac Catalyst; no App Store submission in this plan's scope (spec
  section 1 — personal use / TestFlight / AltStore later).
- `VerbForms`'s 9 new conjugation fields (potential, volitional, passive,
  causative, causative_passive, conditional_ba, conditional_tara,
  imperative, tai) are **optional** — this plan migrates existing data
  as-is without populating them (spec section 4, refined during planning).
- Quiz history, widgets, Shortcuts, and the JMdict/Tatoeba content
  pipeline are **out of scope** for this plan — separate plans per the
  brainstorming decomposition.
- Any `git push` to the GitHub remote requires explicit user confirmation
  at execution time — do not push without asking first, per this session's
  standing safety rules.
- No accessibility-specific code (`.accessibilityLabel`/`.accessibilityHint`/
  Dynamic Type tuning) is added deliberately — standing user preference,
  added mid-implementation (spec section 10). Standard controls keep
  whatever baseline behavior they get for free from the system; nothing
  extra is written on top of it.

---

## Task 1: Remove legacy web app; bootstrap native project scaffolding

The repo currently holds an uncommitted React/Tauri web app (`src/`,
`src-tauri/`, `public/`, npm/Tauri config, a Firebase-deploy GitHub
workflow). Per the spec, this native rewrite replaces it entirely. Since
none of it is committed to git yet, it must be committed first (so it's
recoverable via git history) before being removed — otherwise deleting it
is unrecoverable.

**Files:**
- Create: `.gitignore` (rewritten for the Swift/Xcode project)
- Create: `Packages/VerbKit/Package.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/VerbKit.swift`
- Create: `App/JPVerbConjugationApp.swift`
- Create: `project.yml`
- Create: `scripts/generate-project.sh`
- Delete: `src/`, `src-tauri/`, `public/`, `package.json`,
  `package-lock.json`, `tsconfig.json`, `vite.config.ts`, `index.html`,
  `.firebaserc`, `firebase.json`, `.github/workflows/deploy.yml`
- Keep: `.github/ISSUE_TEMPLATE/add-verb.yml` (still linked from the app)

**Interfaces:**
- Produces: `public let verbKitPlaceholder: Bool` (temporary, in
  `VerbKit.swift` — Task 2 replaces this file with the real models and
  removes the constant). Two buildable Xcode schemes:
  `JPVerbConjugation_iOS`, `JPVerbConjugation_macOS`.

- [ ] **Step 1: Snapshot the legacy web app in git before touching it**

```bash
git add -A -- src src-tauri public package.json package-lock.json tsconfig.json vite.config.ts index.html .firebaserc firebase.json .github
git status --short
```

Confirm the listed files are staged, then commit:

```bash
git commit -m "$(cat <<'EOF'
Snapshot legacy Tauri/React web app before native rewrite

Preserved in history so it can be recovered later even though this
repo is switching entirely to a native Swift/SwiftUI app per
docs/superpowers/specs/2026-09-23-native-apple-rewrite-design.md.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 2: Remove the web app files, keeping the issue template**

```bash
git rm -r --quiet src src-tauri public package.json package-lock.json tsconfig.json vite.config.ts index.html .firebaserc firebase.json .github/workflows/deploy.yml
git status --short
```

Verify `.github/ISSUE_TEMPLATE/add-verb.yml` is **not** in the deleted list
(it's still linked from the app's "Suggest a verb" button).

- [ ] **Step 3: Rewrite `.gitignore` for the Swift project**

```
# Xcode / XcodeGen
*.xcodeproj/
.build/
DerivedData/
*.xcuserstate
.swiftpm/

# macOS
.DS_Store
```

- [ ] **Step 4: Create the `VerbKit` package skeleton**

`Packages/VerbKit/Package.swift`:

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VerbKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VerbKit", targets: ["VerbKit"])
    ],
    targets: [
        .target(name: "VerbKit")
    ]
)
```

`Packages/VerbKit/Sources/VerbKit/VerbKit.swift`:

```swift
/// Temporary marker so the package has a buildable source file before
/// Task 2 adds the real models. Deleted once Models/Verb.swift exists.
public let verbKitPlaceholder = true
```

- [ ] **Step 5: Create the app entry point**

`App/JPVerbConjugationApp.swift`:

```swift
import SwiftUI
import VerbKit

@main
struct JPVerbConjugationApp: App {
    var body: some Scene {
        WindowGroup {
            Text(verbKitPlaceholder ? "JP Verb Conjugation" : "")
                .padding()
        }
    }
}
```

- [ ] **Step 6: Write the XcodeGen project spec**

`project.yml`:

```yaml
name: JPVerbConjugation
options:
  bundleIdPrefix: dev.martinloeseth
packages:
  VerbKit:
    path: Packages/VerbKit
targets:
  JPVerbConjugation:
    type: application
    platform: [iOS, macOS]
    deploymentTarget:
      iOS: "17.0"
      macOS: "14.0"
    sources:
      - path: App
    dependencies:
      - package: VerbKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.martinloeseth.jpverbconjugation
        PRODUCT_NAME: "JP Verb Conjugation"
        SWIFT_VERSION: "5.0"
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_STYLE: Automatic
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
```

- [ ] **Step 7: Write the generate script**

`scripts/generate-project.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
```

```bash
chmod +x scripts/generate-project.sh
```

- [ ] **Step 8: Generate the project and build both platforms**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" build 2>&1 | tail -15
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 9: Commit**

```bash
git add .gitignore Packages App project.yml scripts
git commit -m "$(cat <<'EOF'
Bootstrap native SwiftUI project scaffolding

XcodeGen-generated multiplatform targets (iOS + macOS, sharing App/
sources and the local VerbKit package), replacing the removed
Tauri/React web app per the native rewrite spec.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: VerbKit models + JSON decoding

**Files:**
- Modify: `Packages/VerbKit/Package.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/VerbType.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/TeGroup.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/FormKey.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/VerbForms.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/VerbExample.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/Verb.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Models/VerbDataFile.swift`
- Delete: `Packages/VerbKit/Sources/VerbKit/VerbKit.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/Fixtures/verbs-fixture.json`
- Create: `Packages/VerbKit/Tests/VerbKitTests/VerbDecodingTests.swift`
- Modify: `App/JPVerbConjugationApp.swift` (remove reference to the
  deleted `verbKitPlaceholder`)

**Interfaces:**
- Consumes: nothing (first real logic in the package).
- Produces: `VerbType` (`.irregular`/`.ru`/`.u`), `TeGroup`
  (`.tte`/`.nde`/`.ite`/`.ide`/`.shite`), `FormKey` (9 cases, the required
  forms), `VerbForms` (9 required `String` properties + 9 optional
  `String?` properties, plus `subscript(_ key: FormKey) -> String`),
  `VerbExample { form: FormKey, jp: String, en: String }`, `Verb { type,
  label, dict, kanji: String?, meaning, description, notes: String?,
  teGroup: TeGroup?, forms: VerbForms, examples: [VerbExample] }`
  (`Identifiable` via `id == dict`), `VerbDataFile { version, description,
  verbs: [Verb] }`. All `Codable`, `Sendable`; `VerbType`, `TeGroup`,
  `FormKey`, `VerbForms`, `VerbExample`, and `Verb` are also `Hashable`
  (needed later for SwiftUI `List(selection:)`/`NavigationLink(value:)`
  in Task 12 — `VerbDataFile` isn't, it's never used as an identity).

- [ ] **Step 1: Write the fixture JSON**

`Packages/VerbKit/Tests/VerbKitTests/Fixtures/verbs-fixture.json`:

```json
{
  "version": "test-fixture",
  "description": "Fixture for VerbKit decoding tests.",
  "verbs": [
    {
      "type": "irr.",
      "label": "Irregular",
      "dict": "する",
      "kanji": null,
      "meaning": "to do",
      "description": "The most common irregular verb.",
      "notes": "Compounds like べんきょうする follow する's pattern.",
      "forms": {
        "masu_pos": "します",
        "masu_neg": "しません",
        "masu_past": "しました",
        "masu_past_neg": "しませんでした",
        "te": "して",
        "short_pos": "する",
        "short_neg": "しない",
        "short_past": "した",
        "short_past_neg": "しなかった"
      },
      "examples": [
        { "form": "masu_pos", "jp": "まいにちべんきょうします。", "en": "I study every day." }
      ]
    },
    {
      "type": "ru",
      "label": "Ru-verb",
      "dict": "たべる",
      "kanji": "食べる",
      "meaning": "to eat",
      "description": "A common ichidan verb.",
      "forms": {
        "masu_pos": "たべます",
        "masu_neg": "たべません",
        "masu_past": "たべました",
        "masu_past_neg": "たべませんでした",
        "te": "たべて",
        "short_pos": "たべる",
        "short_neg": "たべない",
        "short_past": "たべた",
        "short_past_neg": "たべなかった"
      },
      "examples": [
        { "form": "te", "jp": "たべてください。", "en": "Please eat." },
        { "form": "short_pos", "jp": "まいにちたべる。", "en": "I eat every day." }
      ]
    }
  ]
}
```

- [ ] **Step 2: Write the failing decoding tests**

`Packages/VerbKit/Tests/VerbKitTests/VerbDecodingTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class VerbDecodingTests: XCTestCase {
    private func loadFixture() throws -> VerbDataFile {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VerbDataFile.self, from: data)
    }

    func testDecodesVerbDataFile() throws {
        let file = try loadFixture()
        XCTAssertEqual(file.verbs.count, 2)
        XCTAssertEqual(file.version, "test-fixture")
    }

    func testDecodesIrregularVerbWithoutTeGroup() throws {
        let file = try loadFixture()
        let suru = try XCTUnwrap(file.verbs.first { $0.dict == "する" })
        XCTAssertEqual(suru.type, .irregular)
        XCTAssertNil(suru.teGroup)
        XCTAssertNil(suru.kanji)
        XCTAssertEqual(suru.forms.masuPos, "します")
        XCTAssertEqual(suru.forms.shortPastNeg, "しなかった")
        XCTAssertNil(suru.forms.potential)
    }

    func testDecodesRuVerbWithExamples() throws {
        let file = try loadFixture()
        let taberu = try XCTUnwrap(file.verbs.first { $0.dict == "たべる" })
        XCTAssertEqual(taberu.type, .ru)
        XCTAssertEqual(taberu.kanji, "食べる")
        XCTAssertNil(taberu.notes)
        XCTAssertEqual(taberu.examples.count, 2)
        XCTAssertEqual(taberu.examples[0].form, .te)
        XCTAssertEqual(taberu.examples[0].jp, "たべてください。")
    }

    func testFormSubscriptMatchesNamedProperty() throws {
        let file = try loadFixture()
        let suru = try XCTUnwrap(file.verbs.first { $0.dict == "する" })
        XCTAssertEqual(suru.forms[.masuPos], suru.forms.masuPos)
        XCTAssertEqual(suru.forms[.te], "して")
    }

    func testVerbIDIsDictForm() throws {
        let file = try loadFixture()
        let suru = try XCTUnwrap(file.verbs.first { $0.dict == "する" })
        XCTAssertEqual(suru.id, "する")
    }
}
```

- [ ] **Step 3: Add the test target to `Package.swift` and run — expect a build failure**

Modify `Packages/VerbKit/Package.swift`:

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VerbKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "VerbKit", targets: ["VerbKit"])
    ],
    targets: [
        .target(name: "VerbKit"),
        .testTarget(
            name: "VerbKitTests",
            dependencies: ["VerbKit"],
            resources: [.copy("Fixtures/verbs-fixture.json")]
        )
    ]
)
```

```bash
cd Packages/VerbKit && swift test 2>&1 | tail -30
```

Expected: build failure — `VerbDataFile`, `Verb`, etc. don't exist yet.

- [ ] **Step 4: Implement the models**

`Packages/VerbKit/Sources/VerbKit/Models/VerbType.swift`:

```swift
public enum VerbType: String, Codable, Hashable, Sendable {
    case irregular = "irr."
    case ru = "ru"
    case u = "u"
}
```

`Packages/VerbKit/Sources/VerbKit/Models/TeGroup.swift`:

```swift
public enum TeGroup: String, Codable, Hashable, Sendable {
    case tte
    case nde
    case ite
    case ide
    case shite
}
```

`Packages/VerbKit/Sources/VerbKit/Models/FormKey.swift`:

```swift
/// The 9 conjugation forms every verb is guaranteed to have.
/// (The 9 additional advanced forms on `VerbForms` are optional and don't
/// have `FormKey` cases yet — quiz generation and search only need the
/// guaranteed set. See the spec's data-layer section for why.)
public enum FormKey: String, CaseIterable, Codable, Equatable, Sendable {
    case masuPos = "masu_pos"
    case masuNeg = "masu_neg"
    case masuPast = "masu_past"
    case masuPastNeg = "masu_past_neg"
    case te
    case shortPos = "short_pos"
    case shortNeg = "short_neg"
    case shortPast = "short_past"
    case shortPastNeg = "short_past_neg"
}
```

`Packages/VerbKit/Sources/VerbKit/Models/VerbForms.swift`:

```swift
public struct VerbForms: Codable, Hashable, Sendable {
    public var masuPos: String
    public var masuNeg: String
    public var masuPast: String
    public var masuPastNeg: String
    public var te: String
    public var shortPos: String
    public var shortNeg: String
    public var shortPast: String
    public var shortPastNeg: String

    public var potential: String?
    public var volitional: String?
    public var passive: String?
    public var causative: String?
    public var causativePassive: String?
    public var conditionalBa: String?
    public var conditionalTara: String?
    public var imperative: String?
    public var tai: String?

    public init(
        masuPos: String,
        masuNeg: String,
        masuPast: String,
        masuPastNeg: String,
        te: String,
        shortPos: String,
        shortNeg: String,
        shortPast: String,
        shortPastNeg: String,
        potential: String? = nil,
        volitional: String? = nil,
        passive: String? = nil,
        causative: String? = nil,
        causativePassive: String? = nil,
        conditionalBa: String? = nil,
        conditionalTara: String? = nil,
        imperative: String? = nil,
        tai: String? = nil
    ) {
        self.masuPos = masuPos
        self.masuNeg = masuNeg
        self.masuPast = masuPast
        self.masuPastNeg = masuPastNeg
        self.te = te
        self.shortPos = shortPos
        self.shortNeg = shortNeg
        self.shortPast = shortPast
        self.shortPastNeg = shortPastNeg
        self.potential = potential
        self.volitional = volitional
        self.passive = passive
        self.causative = causative
        self.causativePassive = causativePassive
        self.conditionalBa = conditionalBa
        self.conditionalTara = conditionalTara
        self.imperative = imperative
        self.tai = tai
    }

    enum CodingKeys: String, CodingKey {
        case masuPos = "masu_pos"
        case masuNeg = "masu_neg"
        case masuPast = "masu_past"
        case masuPastNeg = "masu_past_neg"
        case te
        case shortPos = "short_pos"
        case shortNeg = "short_neg"
        case shortPast = "short_past"
        case shortPastNeg = "short_past_neg"
        case potential
        case volitional
        case passive
        case causative
        case causativePassive = "causative_passive"
        case conditionalBa = "conditional_ba"
        case conditionalTara = "conditional_tara"
        case imperative
        case tai
    }

    public subscript(_ key: FormKey) -> String {
        switch key {
        case .masuPos: return masuPos
        case .masuNeg: return masuNeg
        case .masuPast: return masuPast
        case .masuPastNeg: return masuPastNeg
        case .te: return te
        case .shortPos: return shortPos
        case .shortNeg: return shortNeg
        case .shortPast: return shortPast
        case .shortPastNeg: return shortPastNeg
        }
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Models/VerbExample.swift`:

```swift
public struct VerbExample: Codable, Hashable, Sendable {
    public var form: FormKey
    public var jp: String
    public var en: String

    public init(form: FormKey, jp: String, en: String) {
        self.form = form
        self.jp = jp
        self.en = en
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Models/Verb.swift`:

```swift
public struct Verb: Codable, Hashable, Identifiable, Sendable {
    public var type: VerbType
    public var label: String
    public var dict: String
    public var kanji: String?
    public var meaning: String
    public var description: String
    public var notes: String?
    public var teGroup: TeGroup?
    public var forms: VerbForms
    public var examples: [VerbExample]

    public var id: String { dict }

    public init(
        type: VerbType,
        label: String,
        dict: String,
        kanji: String?,
        meaning: String,
        description: String,
        notes: String? = nil,
        teGroup: TeGroup? = nil,
        forms: VerbForms,
        examples: [VerbExample]
    ) {
        self.type = type
        self.label = label
        self.dict = dict
        self.kanji = kanji
        self.meaning = meaning
        self.description = description
        self.notes = notes
        self.teGroup = teGroup
        self.forms = forms
        self.examples = examples
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Models/VerbDataFile.swift`:

```swift
public struct VerbDataFile: Codable, Sendable {
    public var version: String
    public var description: String
    public var verbs: [Verb]

    public init(version: String, description: String, verbs: [Verb]) {
        self.version = version
        self.description = description
        self.verbs = verbs
    }
}
```

Delete the placeholder:

```bash
rm Packages/VerbKit/Sources/VerbKit/VerbKit.swift
```

Update `App/JPVerbConjugationApp.swift` (drop the now-gone `verbKitPlaceholder`):

```swift
import SwiftUI
import VerbKit

@main
struct JPVerbConjugationApp: App {
    var body: some Scene {
        WindowGroup {
            Text("JP Verb Conjugation")
                .padding()
        }
    }
}
```

- [ ] **Step 5: Run tests — expect all to pass**

```bash
cd Packages/VerbKit && swift test 2>&1 | tail -30
```

Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 6: Rebuild the app targets to confirm nothing broke**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Packages App
git commit -m "$(cat <<'EOF'
Add VerbKit models and JSON decoding

Verb, VerbForms (9 required + 9 optional conjugation fields),
VerbExample, VerbType, TeGroup, FormKey, and the top-level
VerbDataFile wrapper, all Codable and tested against a fixture
matching the real verbs.json schema.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Search & type-filter logic

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Search/VerbSearch.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/VerbSearchTests.swift`

**Interfaces:**
- Consumes: `Verb`, `VerbType`, `FormKey`, `VerbForms` (Task 2).
- Produces: `matchesSearch(_ verb: Verb, query: String) -> Bool`,
  `matchesType(_ verb: Verb, filter: VerbType?) -> Bool` — both pure
  functions, used later by `VerbListView` (Task 12).

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/VerbSearchTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class VerbSearchTests: XCTestCase {
    private let taberu = Verb(
        type: .ru, label: "Ru-verb", dict: "たべる", kanji: "食べる",
        meaning: "to eat", description: "A common ichidan verb.",
        forms: VerbForms(
            masuPos: "たべます", masuNeg: "たべません", masuPast: "たべました",
            masuPastNeg: "たべませんでした", te: "たべて", shortPos: "たべる",
            shortNeg: "たべない", shortPast: "たべた", shortPastNeg: "たべなかった"
        ),
        examples: []
    )

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(matchesSearch(taberu, query: ""))
        XCTAssertTrue(matchesSearch(taberu, query: "   "))
    }

    func testMatchesDictForm() {
        XCTAssertTrue(matchesSearch(taberu, query: "たべる"))
    }

    func testMatchesKanji() {
        XCTAssertTrue(matchesSearch(taberu, query: "食べる"))
    }

    func testMatchesMeaningCaseInsensitive() {
        XCTAssertTrue(matchesSearch(taberu, query: "EAT"))
    }

    func testMatchesConjugatedForm() {
        XCTAssertTrue(matchesSearch(taberu, query: "たべません"))
    }

    func testNoMatchReturnsFalse() {
        XCTAssertFalse(matchesSearch(taberu, query: "のむ"))
    }

    func testTypeFilterNilMatchesAll() {
        XCTAssertTrue(matchesType(taberu, filter: nil))
    }

    func testTypeFilterMatchesExactType() {
        XCTAssertTrue(matchesType(taberu, filter: .ru))
        XCTAssertFalse(matchesType(taberu, filter: .u))
    }
}
```

```bash
cd Packages/VerbKit && swift test --filter VerbSearchTests 2>&1 | tail -20
```

Expected: build failure — `matchesSearch`/`matchesType` don't exist yet.

- [ ] **Step 2: Implement**

`Packages/VerbKit/Sources/VerbKit/Search/VerbSearch.swift`:

```swift
import Foundation

public func matchesSearch(_ verb: Verb, query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }

    if verb.dict.contains(trimmed) { return true }
    if let kanji = verb.kanji, kanji.contains(trimmed) { return true }
    if verb.meaning.localizedCaseInsensitiveContains(trimmed) { return true }
    for key in FormKey.allCases where verb.forms[key].contains(trimmed) {
        return true
    }
    return false
}

public func matchesType(_ verb: Verb, filter: VerbType?) -> Bool {
    guard let filter else { return true }
    return verb.type == filter
}
```

- [ ] **Step 3: Run tests — expect all to pass**

```bash
cd Packages/VerbKit && swift test --filter VerbSearchTests 2>&1 | tail -20
```

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Search Packages/VerbKit/Tests/VerbKitTests/VerbSearchTests.swift
git commit -m "$(cat <<'EOF'
Add verb search and type-filter logic

Pure functions ported from the web app's matchesSearch: dict/kanji/
form substring match plus case-insensitive meaning match, and a
simple type-filter predicate. Used by VerbListView once it exists.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Quiz question generation

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizQuestion.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizGenerator.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/QuizGeneratorTests.swift`

**Interfaces:**
- Consumes: `Verb`, `FormKey` (Task 2).
- Produces: `QuizQuestion { verb: Verb, form: FormKey, correct: String,
  choices: [String] }`, `buildQuestions(verbs: [Verb], count: Int) ->
  [QuizQuestion]` — used by `QuizViewModel` (Task 5).

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/QuizGeneratorTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class QuizGeneratorTests: XCTestCase {
    private func makeVerb(dict: String, masuPos: String) -> Verb {
        Verb(
            type: .u, label: "U-verb", dict: dict, kanji: nil,
            meaning: "to \(dict)", description: "d",
            forms: VerbForms(
                masuPos: masuPos, masuNeg: "\(dict)-neg", masuPast: "\(dict)-past",
                masuPastNeg: "\(dict)-pastneg", te: "\(dict)-te", shortPos: dict,
                shortNeg: "\(dict)-sneg", shortPast: "\(dict)-spast", shortPastNeg: "\(dict)-spastneg"
            ),
            examples: []
        )
    }

    private var verbs: [Verb] {
        [
            makeVerb(dict: "のむ", masuPos: "のみます"),
            makeVerb(dict: "よむ", masuPos: "よみます"),
            makeVerb(dict: "かく", masuPos: "かきます"),
        ]
    }

    func testReturnsRequestedCount() {
        let questions = buildQuestions(verbs: verbs, count: 5)
        XCTAssertEqual(questions.count, 5)
    }

    func testCapsAtAvailablePoolSize() {
        let questions = buildQuestions(verbs: verbs, count: 100)
        XCTAssertEqual(questions.count, verbs.count * FormKey.allCases.count)
    }

    func testCorrectAnswerMatchesVerbForm() {
        let questions = buildQuestions(verbs: verbs, count: 27)
        for question in questions {
            XCTAssertEqual(question.correct, question.verb.forms[question.form])
        }
    }

    func testChoicesContainCorrectAnswer() {
        let questions = buildQuestions(verbs: verbs, count: 10)
        for question in questions {
            XCTAssertTrue(question.choices.contains(question.correct))
        }
    }

    func testChoicesHaveNoDuplicates() {
        let questions = buildQuestions(verbs: verbs, count: 27)
        for question in questions {
            XCTAssertEqual(Set(question.choices).count, question.choices.count)
        }
    }

    func testChoicesCapAtFour() {
        let questions = buildQuestions(verbs: verbs, count: 27)
        for question in questions {
            XCTAssertLessThanOrEqual(question.choices.count, 4)
        }
    }
}
```

```bash
cd Packages/VerbKit && swift test --filter QuizGeneratorTests 2>&1 | tail -20
```

Expected: build failure — `QuizQuestion`/`buildQuestions` don't exist yet.

- [ ] **Step 2: Implement**

`Packages/VerbKit/Sources/VerbKit/Quiz/QuizQuestion.swift`:

```swift
public struct QuizQuestion: Equatable, Sendable {
    public var verb: Verb
    public var form: FormKey
    public var correct: String
    public var choices: [String]

    public init(verb: Verb, form: FormKey, correct: String, choices: [String]) {
        self.verb = verb
        self.form = form
        self.correct = correct
        self.choices = choices
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Quiz/QuizGenerator.swift`:

```swift
/// Ported from the web app's buildQuestions: pick `count` random
/// (verb, form) pairs, then for each build up to 3 unique distractors —
/// preferring the same verb's other forms, falling back to other verbs'
/// forms — deduplicated and shuffled alongside the correct answer.
public func buildQuestions(verbs: [Verb], count: Int) -> [QuizQuestion] {
    struct PoolEntry {
        let verb: Verb
        let form: FormKey
        let correct: String
    }

    var pool: [PoolEntry] = []
    for verb in verbs {
        for form in FormKey.allCases {
            pool.append(PoolEntry(verb: verb, form: form, correct: verb.forms[form]))
        }
    }
    let selected = pool.shuffled().prefix(count)

    return selected.map { entry in
        let wrongSameVerb = FormKey.allCases
            .filter { $0 != entry.form }
            .map { entry.verb.forms[$0] }
            .filter { $0 != entry.correct }
        let wrongOtherVerbs = verbs
            .filter { $0.dict != entry.verb.dict }
            .map { $0.forms[entry.form] }
            .filter { $0 != entry.correct }

        var seen = Set<String>()
        let distractors = (wrongSameVerb + wrongOtherVerbs)
            .shuffled()
            .filter { seen.insert($0).inserted }
            .prefix(3)

        let choices = ([entry.correct] + distractors).shuffled()
        return QuizQuestion(verb: entry.verb, form: entry.form, correct: entry.correct, choices: choices)
    }
}
```

- [ ] **Step 3: Run tests — expect all to pass**

```bash
cd Packages/VerbKit && swift test --filter QuizGeneratorTests 2>&1 | tail -20
```

Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Quiz/QuizQuestion.swift Packages/VerbKit/Sources/VerbKit/Quiz/QuizGenerator.swift Packages/VerbKit/Tests/VerbKitTests/QuizGeneratorTests.swift
git commit -m "$(cat <<'EOF'
Add quiz question generation

Ports buildQuestions from the web app: same-verb-then-cross-verb
distractor selection, deduplicated and capped at 3, using Swift's
native shuffled() in place of the JS app's hand-rolled Fisher-Yates.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Quiz view model (scoring/state; timer tick logic)

The 20-second countdown's *ticking mechanism* (a repeating `Task` or
`TimelineView`) is UI plumbing verified manually in Task 15. This task
covers everything about the quiz that's deterministic and worth testing
without real time passing: answering, scoring, advancing, and the
countdown's *arithmetic* via an externally-driven `tickTimer()` call.

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizResult.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Quiz/QuizViewModel.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/QuizViewModelTests.swift`

**Interfaces:**
- Consumes: `QuizQuestion`, `FormKey` (Task 4).
- Produces: `QuizResult { verb: String, form: FormKey, correct: String,
  chosen: String, ok: Bool }`, `@Observable final class QuizViewModel`
  with `questions: [QuizQuestion]`, `index: Int`, `selected: String?`,
  `score: Int`, `results: [QuizResult]`, `timedOut: Bool`, `timeLeft:
  Int`, `finished: Bool`, `currentQuestion: QuizQuestion?`, `isAnswered:
  Bool`, and methods `choose(_:)`, `markTimedOut()`, `advance()`,
  `tickTimer()` — used by `QuizView` (Task 15).

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/QuizViewModelTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class QuizViewModelTests: XCTestCase {
    private func makeQuestion(correct: String, choices: [String], dict: String = "たべる") -> QuizQuestion {
        let verb = Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "to eat", description: "d",
            forms: VerbForms(masuPos: correct, masuNeg: "x", masuPast: "x", masuPastNeg: "x", te: "x", shortPos: "x", shortNeg: "x", shortPast: "x", shortPastNeg: "x"),
            examples: []
        )
        return QuizQuestion(verb: verb, form: .masuPos, correct: correct, choices: choices)
    }

    func testChoosingCorrectAnswerIncrementsScore() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.choose("たべます")
        XCTAssertEqual(vm.score, 1)
        XCTAssertEqual(vm.results.count, 1)
        XCTAssertTrue(vm.results[0].ok)
    }

    func testChoosingWrongAnswerDoesNotIncrementScore() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.choose("のみます")
        XCTAssertEqual(vm.score, 0)
        XCTAssertFalse(vm.results[0].ok)
        XCTAssertEqual(vm.results[0].chosen, "のみます")
    }

    func testChoosingTwiceIsIgnored() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.choose("たべます")
        vm.choose("のみます")
        XCTAssertEqual(vm.score, 1)
        XCTAssertEqual(vm.results.count, 1)
    }

    func testTimeoutMarksAnsweredWithoutRecordingResult() {
        // Matches the web app: a timeout does not append to `results`,
        // it only flips the answered/timedOut flags.
        let vm = QuizViewModel(questions: [makeQuestion(correct: "たべます", choices: ["たべます", "のみます"])])
        vm.markTimedOut()
        XCTAssertTrue(vm.timedOut)
        XCTAssertTrue(vm.isAnswered)
        XCTAssertTrue(vm.results.isEmpty)
    }

    func testAdvanceMovesToNextQuestionAndResetsState() {
        let vm = QuizViewModel(questions: [
            makeQuestion(correct: "A", choices: ["A", "B"], dict: "1"),
            makeQuestion(correct: "C", choices: ["C", "D"], dict: "2"),
        ])
        vm.choose("A")
        vm.advance()
        XCTAssertEqual(vm.index, 1)
        XCTAssertNil(vm.selected)
        XCTAssertFalse(vm.timedOut)
        XCTAssertEqual(vm.timeLeft, 20)
        XCTAssertFalse(vm.finished)
    }

    func testAdvanceOnLastQuestionFinishesQuiz() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "A", choices: ["A", "B"])])
        vm.choose("A")
        vm.advance()
        XCTAssertTrue(vm.finished)
    }

    func testTickTimerCountsDownAndTimesOutAtZero() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "A", choices: ["A", "B"])])
        XCTAssertEqual(vm.timeLeft, 20)
        for _ in 0..<19 { vm.tickTimer() }
        XCTAssertEqual(vm.timeLeft, 1)
        XCTAssertFalse(vm.timedOut)
        vm.tickTimer()
        XCTAssertEqual(vm.timeLeft, 0)
        XCTAssertTrue(vm.timedOut)
    }

    func testTickTimerStopsOnceAnswered() {
        let vm = QuizViewModel(questions: [makeQuestion(correct: "A", choices: ["A", "B"])])
        vm.choose("A")
        vm.tickTimer()
        XCTAssertEqual(vm.timeLeft, 20)
    }
}
```

```bash
cd Packages/VerbKit && swift test --filter QuizViewModelTests 2>&1 | tail -20
```

Expected: build failure — `QuizViewModel`/`QuizResult` don't exist yet.

- [ ] **Step 2: Implement**

`Packages/VerbKit/Sources/VerbKit/Quiz/QuizResult.swift`:

```swift
public struct QuizResult: Equatable, Sendable {
    public var verb: String
    public var form: FormKey
    public var correct: String
    public var chosen: String
    public var ok: Bool

    public init(verb: String, form: FormKey, correct: String, chosen: String, ok: Bool) {
        self.verb = verb
        self.form = form
        self.correct = correct
        self.chosen = chosen
        self.ok = ok
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Quiz/QuizViewModel.swift`:

```swift
import Observation

@Observable
public final class QuizViewModel {
    public let questions: [QuizQuestion]
    public private(set) var index = 0
    public private(set) var selected: String?
    public private(set) var score = 0
    public private(set) var results: [QuizResult] = []
    public private(set) var timedOut = false
    public private(set) var timeLeft = 20
    public private(set) var finished = false

    public var currentQuestion: QuizQuestion? {
        questions.indices.contains(index) ? questions[index] : nil
    }

    public var isAnswered: Bool { selected != nil || timedOut }

    public init(questions: [QuizQuestion]) {
        self.questions = questions
    }

    public func choose(_ choice: String) {
        guard !isAnswered, let question = currentQuestion else { return }
        selected = choice
        let ok = choice == question.correct
        if ok { score += 1 }
        results.append(QuizResult(verb: question.verb.dict, form: question.form, correct: question.correct, chosen: choice, ok: ok))
    }

    /// Matches the web app: a timeout flips `timedOut` but does not
    /// append a `QuizResult` — the end-of-quiz breakdown silently omits
    /// timed-out questions there, and this ports that faithfully.
    public func markTimedOut() {
        guard !isAnswered else { return }
        timedOut = true
    }

    public func advance() {
        guard isAnswered else { return }
        if index + 1 >= questions.count {
            finished = true
        } else {
            index += 1
            selected = nil
            timedOut = false
            timeLeft = 20
        }
    }

    public func tickTimer() {
        guard !isAnswered else { return }
        if timeLeft <= 1 {
            timeLeft = 0
            markTimedOut()
        } else {
            timeLeft -= 1
        }
    }
}
```

- [ ] **Step 3: Run tests — expect all to pass**

```bash
cd Packages/VerbKit && swift test --filter QuizViewModelTests 2>&1 | tail -20
```

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Quiz/QuizResult.swift Packages/VerbKit/Sources/VerbKit/Quiz/QuizViewModel.swift Packages/VerbKit/Tests/VerbKitTests/QuizViewModelTests.swift
git commit -m "$(cat <<'EOF'
Add QuizViewModel scoring/advance/timer-tick logic

@Observable state machine for the quiz: choose/markTimedOut/advance
plus a deterministic tickTimer() for the 20s countdown's arithmetic.
The actual ticking mechanism (Task/TimelineView) is UI plumbing
added and manually verified in Task 15, not unit tested here.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Verb data fetching + manifest-driven sync

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Data/VerbManifest.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Data/VerbSyncError.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Data/VerbDataFetching.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Data/SyncStateStoring.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Data/UserDefaultsSyncStateStore.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Data/Hashing.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Data/VerbSyncService.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/VerbSyncServiceTests.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/GitHubVerbFetcherTests.swift`

**Interfaces:**
- Consumes: `VerbDataFile`, `Verb` (Task 2). Reuses the
  `Fixtures/verbs-fixture.json` resource from Task 2.
- Produces: `VerbManifest { version: String, sha256: String }`,
  `VerbSyncError` (`.offline`/`.serverUnreachable`/`.malformedData`),
  `VerbDataFetching` protocol (`fetchManifest() async throws ->
  VerbManifest`, `fetchVerbData() async throws -> Data`),
  `SyncStateStoring` protocol (`lastSyncedManifest() -> VerbManifest?`,
  `saveLastSyncedManifest(_:)`), `UserDefaultsSyncStateStore:
  SyncStateStoring`, `GitHubVerbFetcher: VerbDataFetching` (with a
  `.githubMain(session:)` factory pointing at this repo's `data/`
  files), `VerbSyncResult` (`.upToDate` / `.updated(manifest:,
  verbs:)`), `VerbSyncService { init(fetcher:, syncState:); func sync()
  async throws -> VerbSyncResult }` — used by `VerbStore` (Task 9).

- [ ] **Step 1: Write the failing sync-logic tests**

`Packages/VerbKit/Tests/VerbKitTests/VerbSyncServiceTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class VerbSyncServiceTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testUpToDateSkipsVerbDataFetch() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .failure(VerbSyncError.serverUnreachable) // must not be called

        let syncState = InMemorySyncStateStore()
        syncState.saveLastSyncedManifest(manifest)

        let service = VerbSyncService(fetcher: fetcher, syncState: syncState)
        let result = try await service.sync()

        XCTAssertEqual(result, .upToDate)
    }

    func testChangedManifestFetchesAndDecodesVerbs() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.1.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let syncState = InMemorySyncStateStore()
        let service = VerbSyncService(fetcher: fetcher, syncState: syncState)
        let result = try await service.sync()

        guard case let .updated(updatedManifest, verbs) = result else {
            return XCTFail("expected .updated")
        }
        XCTAssertEqual(updatedManifest, manifest)
        XCTAssertEqual(verbs.count, 2)
        XCTAssertEqual(syncState.lastSyncedManifest(), manifest)
    }

    func testHashMismatchThrowsMalformedData() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.1.0", sha256: "not-the-real-hash")
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let service = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        do {
            _ = try await service.sync()
            XCTFail("expected malformedData error")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    func testMalformedJSONThrowsMalformedData() async throws {
        let badData = Data("not json".utf8)
        let manifest = VerbManifest(version: "1.1.0", sha256: sha256Hex(of: badData))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(badData)

        let service = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        do {
            _ = try await service.sync()
            XCTFail("expected malformedData error")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    func testOfflineErrorPropagates() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let service = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        do {
            _ = try await service.sync()
            XCTFail("expected offline error")
        } catch VerbSyncError.offline {
            // expected
        }
    }
}

// Internal (not `private`) so Task 9's VerbStoreTests can reuse them —
// test files in the same target share internal declarations freely.
final class MockVerbDataFetcher: VerbDataFetching, @unchecked Sendable {
    var manifestResult: Result<VerbManifest, Error> = .failure(VerbSyncError.offline)
    var verbDataResult: Result<Data, Error> = .failure(VerbSyncError.offline)

    func fetchManifest() async throws -> VerbManifest { try manifestResult.get() }
    func fetchVerbData() async throws -> Data { try verbDataResult.get() }
}

final class InMemorySyncStateStore: SyncStateStoring, @unchecked Sendable {
    private var manifest: VerbManifest?
    func lastSyncedManifest() -> VerbManifest? { manifest }
    func saveLastSyncedManifest(_ manifest: VerbManifest) { self.manifest = manifest }
}
```

```bash
cd Packages/VerbKit && swift test --filter VerbSyncServiceTests 2>&1 | tail -20
```

Expected: build failure — none of the sync types exist yet.

- [ ] **Step 2: Implement the manifest, error, protocols, hashing, and sync service**

`Packages/VerbKit/Sources/VerbKit/Data/VerbManifest.swift`:

```swift
public struct VerbManifest: Codable, Equatable, Sendable {
    public var version: String
    public var sha256: String

    public init(version: String, sha256: String) {
        self.version = version
        self.sha256 = sha256
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Data/VerbSyncError.swift`:

```swift
public enum VerbSyncError: Error, Equatable, Sendable {
    case offline
    case serverUnreachable
    case malformedData
}
```

`Packages/VerbKit/Sources/VerbKit/Data/VerbDataFetching.swift`:

```swift
import Foundation

public protocol VerbDataFetching: Sendable {
    func fetchManifest() async throws -> VerbManifest
    func fetchVerbData() async throws -> Data
}
```

`Packages/VerbKit/Sources/VerbKit/Data/SyncStateStoring.swift`:

```swift
public protocol SyncStateStoring: Sendable {
    func lastSyncedManifest() -> VerbManifest?
    func saveLastSyncedManifest(_ manifest: VerbManifest)
}
```

`Packages/VerbKit/Sources/VerbKit/Data/UserDefaultsSyncStateStore.swift`:

```swift
import Foundation

public final class UserDefaultsSyncStateStore: SyncStateStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let versionKey = "VerbKit.lastSyncedManifest.version"
    private let hashKey = "VerbKit.lastSyncedManifest.sha256"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastSyncedManifest() -> VerbManifest? {
        guard let version = defaults.string(forKey: versionKey),
              let sha256 = defaults.string(forKey: hashKey) else { return nil }
        return VerbManifest(version: version, sha256: sha256)
    }

    public func saveLastSyncedManifest(_ manifest: VerbManifest) {
        defaults.set(manifest.version, forKey: versionKey)
        defaults.set(manifest.sha256, forKey: hashKey)
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Data/Hashing.swift`:

```swift
import CryptoKit
import Foundation

func sha256Hex(of data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}
```

`Packages/VerbKit/Sources/VerbKit/Data/VerbSyncService.swift`:

```swift
import Foundation

public enum VerbSyncResult: Equatable, Sendable {
    case upToDate
    case updated(manifest: VerbManifest, verbs: [Verb])
}

public struct VerbSyncService: Sendable {
    private let fetcher: VerbDataFetching
    private let syncState: SyncStateStoring

    public init(fetcher: VerbDataFetching, syncState: SyncStateStoring) {
        self.fetcher = fetcher
        self.syncState = syncState
    }

    /// Fetches the manifest; if unchanged from the last sync, returns
    /// `.upToDate` without ever fetching the (larger) verb data. If
    /// changed, fetches it, verifies its hash against the manifest
    /// (a mismatch is treated as corrupted/incomplete data), decodes
    /// it, records the new manifest as synced, and returns the verbs.
    public func sync() async throws -> VerbSyncResult {
        let manifest = try await fetcher.fetchManifest()
        if let last = syncState.lastSyncedManifest(), last == manifest {
            return .upToDate
        }

        let data = try await fetcher.fetchVerbData()
        guard sha256Hex(of: data) == manifest.sha256 else {
            throw VerbSyncError.malformedData
        }

        let decoded: VerbDataFile
        do {
            decoded = try JSONDecoder().decode(VerbDataFile.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }

        syncState.saveLastSyncedManifest(manifest)
        return .updated(manifest: manifest, verbs: decoded.verbs)
    }
}
```

- [ ] **Step 3: Run the sync-logic tests — expect all to pass**

```bash
cd Packages/VerbKit && swift test --filter VerbSyncServiceTests 2>&1 | tail -20
```

Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 4: Write the failing `GitHubVerbFetcher` tests**

`Packages/VerbKit/Tests/VerbKitTests/GitHubVerbFetcherTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class GitHubVerbFetcherTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private let manifestURL = URL(string: "https://raw.githubusercontent.com/example/repo/main/data/manifest.json")!
    private let verbsURL = URL(string: "https://raw.githubusercontent.com/example/repo/main/data/verbs.json")!

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchManifestDecodesSuccessfulResponse() async throws {
        let json = Data(#"{"version": "1.0.0", "sha256": "abc"}"#.utf8)
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, session: makeSession())

        let manifest = try await fetcher.fetchManifest()
        XCTAssertEqual(manifest, VerbManifest(version: "1.0.0", sha256: "abc"))
    }

    func testFetchManifestMapsServerErrorToServerUnreachable() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, session: makeSession())

        do {
            _ = try await fetcher.fetchManifest()
            XCTFail("expected serverUnreachable")
        } catch VerbSyncError.serverUnreachable {
            // expected
        }
    }

    func testFetchManifestMapsOfflineURLErrorToOffline() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, session: makeSession())

        do {
            _ = try await fetcher.fetchManifest()
            XCTFail("expected offline")
        } catch VerbSyncError.offline {
            // expected
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

```bash
cd Packages/VerbKit && swift test --filter GitHubVerbFetcherTests 2>&1 | tail -20
```

Expected: build failure — `GitHubVerbFetcher` doesn't exist yet.

- [ ] **Step 5: Implement `GitHubVerbFetcher`**

`Packages/VerbKit/Sources/VerbKit/Data/GitHubVerbFetcher.swift`:

```swift
import Foundation

public struct GitHubVerbFetcher: VerbDataFetching {
    private let manifestURL: URL
    private let verbsURL: URL
    private let session: URLSession

    public init(manifestURL: URL, verbsURL: URL, session: URLSession = .shared) {
        self.manifestURL = manifestURL
        self.verbsURL = verbsURL
        self.session = session
    }

    public func fetchManifest() async throws -> VerbManifest {
        let data = try await fetchData(from: manifestURL)
        do {
            return try JSONDecoder().decode(VerbManifest.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }
    }

    public func fetchVerbData() async throws -> Data {
        try await fetchData(from: verbsURL)
    }

    private func fetchData(from url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .timedOut:
                throw VerbSyncError.offline
            default:
                throw VerbSyncError.serverUnreachable
            }
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VerbSyncError.serverUnreachable
        }
        return data
    }
}

public extension GitHubVerbFetcher {
    /// Points at this repo's `data/` files on the `main` branch.
    static func githubMain(session: URLSession = .shared) -> GitHubVerbFetcher {
        let base = "https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/data/"
        return GitHubVerbFetcher(
            manifestURL: URL(string: base + "manifest.json")!,
            verbsURL: URL(string: base + "verbs.json")!,
            session: session
        )
    }
}
```

- [ ] **Step 6: Run the fetcher tests — expect all to pass**

```bash
cd Packages/VerbKit && swift test --filter GitHubVerbFetcherTests 2>&1 | tail -20
```

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 7: Run the full package test suite**

```bash
cd Packages/VerbKit && swift test 2>&1 | tail -15
```

Expected: all tests across every test class pass.

- [ ] **Step 8: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Data Packages/VerbKit/Tests/VerbKitTests/VerbSyncServiceTests.swift Packages/VerbKit/Tests/VerbKitTests/GitHubVerbFetcherTests.swift
git commit -m "$(cat <<'EOF'
Add GitHub-sourced verb data fetching and manifest-driven sync

VerbDataFetching protocol + GitHubVerbFetcher (URLSession, maps
URLError/HTTP status to offline vs serverUnreachable), and
VerbSyncService: checks manifest.json first, skips the full
verbs.json fetch when unchanged, verifies its sha256 against the
manifest, and decodes it. Tested via a mock fetcher (sync logic)
and a stubbed URLProtocol (real HTTP/error mapping).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Network connectivity monitor

`NWPathMonitor`'s actual connectivity transitions can't be meaningfully
forced in a unit test environment (no fake network stack to flip). Per
the spec, real verification of "goes offline / comes back online" happens
manually in Simulator (airplane-mode toggle) once the first-launch screen
exists (Task 11) — this task just wraps it cleanly and confirms it
doesn't crash.

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Data/NetworkMonitor.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/NetworkMonitorTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `@Observable final class NetworkMonitor` with
  `isConnected: Bool`, `onChange: ((Bool) -> Void)?`, `start()`, `stop()`
  — used by `VerbStore` (Task 9, which uses `onChange` to auto-retry the
  first-launch fetch when connectivity returns) and `DataLoadingView`
  (Task 11).

- [ ] **Step 1: Write the (compile-and-run) tests**

`Packages/VerbKit/Tests/VerbKitTests/NetworkMonitorTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class NetworkMonitorTests: XCTestCase {
    func testStartAndStopDoesNotCrash() {
        let monitor = NetworkMonitor()
        monitor.start()
        monitor.stop()
    }

    func testOnChangeCanBeAssignedWithoutCrashing() {
        // Real transitions can't be forced in-process (no fake network
        // stack) — this only confirms wiring the callback compiles and
        // doesn't crash; actual reconnect behavior is verified manually
        // in Task 11 via Simulator airplane mode.
        let monitor = NetworkMonitor()
        monitor.onChange = { _ in }
        monitor.start()
        monitor.stop()
    }
}
```

```bash
cd Packages/VerbKit && swift test --filter NetworkMonitorTests 2>&1 | tail -20
```

Expected: build failure — `NetworkMonitor` doesn't exist yet.

- [ ] **Step 2: Implement**

`Packages/VerbKit/Sources/VerbKit/Data/NetworkMonitor.swift`:

```swift
import Network
import Observation

@Observable
public final class NetworkMonitor: @unchecked Sendable {
    public private(set) var isConnected: Bool
    /// Fires on every transition (including the initial status reported
    /// right after `start()`). `VerbStore` (Task 9) uses this to retry
    /// the first-launch fetch automatically once connectivity returns.
    public var onChange: ((Bool) -> Void)?
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "VerbKit.NetworkMonitor")

    public init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        self.isConnected = monitor.currentPath.status == .satisfied
    }

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = connected
                self?.onChange?(connected)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    deinit {
        monitor.cancel()
    }
}
```

- [ ] **Step 3: Run tests — expect pass**

```bash
cd Packages/VerbKit && swift test --filter NetworkMonitorTests 2>&1 | tail -20
```

Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Data/NetworkMonitor.swift Packages/VerbKit/Tests/VerbKitTests/NetworkMonitorTests.swift
git commit -m "$(cat <<'EOF'
Add NWPathMonitor-backed connectivity monitor

@Observable wrapper exposing isConnected. Real connectivity-change
behavior is verified manually via Simulator airplane mode once the
first-launch data-loading screen exists (Task 11), not unit tested
here — NWPathMonitor's real transitions can't be forced in-process.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: SwiftData persistence (App Group-backed)

`Verb` (Task 2) stays a plain `Codable` DTO used for JSON decoding, quiz
generation, and search — none of that needs a `ModelContext` in scope,
which is exactly why those were testable without SwiftData at all. This
task adds a separate SwiftData entity plus conversion functions, keeping
that separation.

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Persistence/VerbEntity.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Persistence/VerbPersisting.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Persistence/SwiftDataVerbPersisting.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Persistence/VerbModelContainer.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/SwiftDataVerbPersistingTests.swift`

**Interfaces:**
- Consumes: `Verb`, `VerbForms`, `VerbExample`, `VerbType`, `TeGroup`
  (Task 2).
- Produces: `@Model final class VerbEntity` (+ `VerbEntity.init(_ verb:
  Verb)`, `func toVerb() -> Verb?`), `@MainActor protocol VerbPersisting
  { func loadAllVerbs() throws -> [Verb]; func replaceAllVerbs(with
  verbs: [Verb]) throws }`, `@MainActor final class
  SwiftDataVerbPersisting: VerbPersisting`, `enum VerbModelContainer {
  static func make() throws -> ModelContainer; static func
  makeInMemory() throws -> ModelContainer }` — used by `VerbStore`
  (Task 9).

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/SwiftDataVerbPersistingTests.swift`:

```swift
import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class SwiftDataVerbPersistingTests: XCTestCase {
    private func makePersisting() throws -> SwiftDataVerbPersisting {
        let container = try VerbModelContainer.makeInMemory()
        let context = ModelContext(container)
        return SwiftDataVerbPersisting(modelContext: context)
    }

    private func makeVerb(dict: String) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: "漢字",
            meaning: "to \(dict)", description: "d", notes: "n", teGroup: nil,
            forms: VerbForms(
                masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h",
                shortPastNeg: "i", potential: "j"
            ),
            examples: [VerbExample(form: .te, jp: "jp", en: "en")]
        )
    }

    func testLoadAllVerbsIsEmptyInitially() throws {
        let persisting = try makePersisting()
        XCTAssertEqual(try persisting.loadAllVerbs(), [])
    }

    func testReplaceAllVerbsInsertsAndRoundTrips() throws {
        let persisting = try makePersisting()
        let verb = makeVerb(dict: "たべる")
        try persisting.replaceAllVerbs(with: [verb])

        let loaded = try persisting.loadAllVerbs()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], verb)
        XCTAssertEqual(loaded[0].forms.potential, "j")
    }

    func testReplaceAllVerbsRemovesStaleEntries() throws {
        let persisting = try makePersisting()
        try persisting.replaceAllVerbs(with: [makeVerb(dict: "のむ")])
        try persisting.replaceAllVerbs(with: [makeVerb(dict: "よむ")])

        let loaded = try persisting.loadAllVerbs()
        XCTAssertEqual(loaded.map(\.dict), ["よむ"])
    }
}
```

```bash
cd Packages/VerbKit && swift test --filter SwiftDataVerbPersistingTests 2>&1 | tail -20
```

Expected: build failure — none of the persistence types exist yet.

- [ ] **Step 2: Implement the entity and conversions**

`Packages/VerbKit/Sources/VerbKit/Persistence/VerbEntity.swift`:

```swift
import SwiftData

@Model
public final class VerbEntity {
    @Attribute(.unique) public var dict: String
    public var type: String
    public var label: String
    public var kanji: String?
    public var meaning: String
    public var verbDescription: String
    public var notes: String?
    public var teGroup: String?
    public var forms: VerbForms
    public var examples: [VerbExample]

    public init(
        dict: String,
        type: String,
        label: String,
        kanji: String?,
        meaning: String,
        verbDescription: String,
        notes: String?,
        teGroup: String?,
        forms: VerbForms,
        examples: [VerbExample]
    ) {
        self.dict = dict
        self.type = type
        self.label = label
        self.kanji = kanji
        self.meaning = meaning
        self.verbDescription = verbDescription
        self.notes = notes
        self.teGroup = teGroup
        self.forms = forms
        self.examples = examples
    }
}

public extension VerbEntity {
    convenience init(_ verb: Verb) {
        self.init(
            dict: verb.dict,
            type: verb.type.rawValue,
            label: verb.label,
            kanji: verb.kanji,
            meaning: verb.meaning,
            verbDescription: verb.description,
            notes: verb.notes,
            teGroup: verb.teGroup?.rawValue,
            forms: verb.forms,
            examples: verb.examples
        )
    }

    /// `nil` if `type`/`teGroup` hold a raw value this build's enums
    /// don't recognize (e.g. old cached data from a newer app version) —
    /// callers skip such entities rather than crash.
    func toVerb() -> Verb? {
        guard let verbType = VerbType(rawValue: type) else { return nil }
        let resolvedTeGroup = teGroup.flatMap { TeGroup(rawValue: $0) }
        return Verb(
            type: verbType,
            label: label,
            dict: dict,
            kanji: kanji,
            meaning: meaning,
            description: verbDescription,
            notes: notes,
            teGroup: resolvedTeGroup,
            forms: forms,
            examples: examples
        )
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Persistence/VerbPersisting.swift`:

```swift
@MainActor
public protocol VerbPersisting {
    func loadAllVerbs() throws -> [Verb]
    func replaceAllVerbs(with verbs: [Verb]) throws
}
```

`Packages/VerbKit/Sources/VerbKit/Persistence/SwiftDataVerbPersisting.swift`:

```swift
import SwiftData

@MainActor
public final class SwiftDataVerbPersisting: VerbPersisting {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func loadAllVerbs() throws -> [Verb] {
        let entities = try modelContext.fetch(FetchDescriptor<VerbEntity>())
        return entities.compactMap { $0.toVerb() }
    }

    public func replaceAllVerbs(with verbs: [Verb]) throws {
        try modelContext.delete(model: VerbEntity.self)
        for verb in verbs {
            modelContext.insert(VerbEntity(verb))
        }
        try modelContext.save()
    }
}
```

`Packages/VerbKit/Sources/VerbKit/Persistence/VerbModelContainer.swift`:

```swift
import Foundation
import SwiftData

public enum VerbModelContainerError: Error {
    case appGroupUnavailable
}

public enum VerbModelContainer {
    public static let appGroupIdentifier = "group.dev.martinloeseth.jpverbconjugation"

    /// The real, on-disk, App Group-shared store — used by the app and,
    /// later, the widget/Shortcuts extension.
    public static func make() throws -> ModelContainer {
        let schema = Schema([VerbEntity.self])
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw VerbModelContainerError.appGroupUnavailable
        }
        let storeURL = groupURL.appendingPathComponent("VerbKit.sqlite")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// An in-memory store for tests and previews — never touches disk.
    public static func makeInMemory() throws -> ModelContainer {
        let schema = Schema([VerbEntity.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
```

- [ ] **Step 3: Run tests — expect all to pass**

```bash
cd Packages/VerbKit && swift test --filter SwiftDataVerbPersistingTests 2>&1 | tail -20
```

Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 4: Run the full package suite and rebuild the app targets**

```bash
cd Packages/VerbKit && swift test 2>&1 | tail -15
cd .. && ./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" build 2>&1 | tail -10
```

Expected: all package tests pass; `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Persistence Packages/VerbKit/Tests/VerbKitTests/SwiftDataVerbPersistingTests.swift
git commit -m "$(cat <<'EOF'
Add SwiftData persistence for the verb cache

VerbEntity (a separate SwiftData model from the plain Codable Verb
DTO, with conversion functions both ways), VerbPersisting protocol,
and a ModelContainer factory pointed at the App Group container so
the widget/Shortcuts extension can read the same store later.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: VerbStore integration

Ties together data loading, sync, and persistence: on startup, load
whatever's cached locally; if there's nothing cached, drive the
first-launch fetch state machine; if there is, show it immediately and
sync in the background, silently. This is the type `DataLoadingView`
(Task 11) and `VerbListView` (Task 12) observe directly.

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Store/FirstLaunchState.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Store/VerbStore.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/VerbStoreTests.swift`

**Interfaces:**
- Consumes: `Verb`, `VerbSyncService`, `VerbSyncResult`, `VerbSyncError`,
  `VerbPersisting`, `NetworkMonitor` (Tasks 2, 6, 7, 8).
- Produces: `FirstLaunchState` (`.checking` / `.fetching` /
  `.failed(VerbSyncError)` / `.success`), `@MainActor @Observable final
  class VerbStore` with `verbs: [Verb]`, `firstLaunchState:
  FirstLaunchState`, `hasLocalData: Bool`, `init(syncService:,
  persisting:, networkMonitor:)`, `func start() async`, `func
  retryFirstLaunch() async` — used by `DataLoadingView` (Task 11) and
  `VerbListView` (Task 12). **Note:** `VerbStore` only assigns
  `networkMonitor.onChange` — it does **not** call
  `networkMonitor.start()`/`stop()`; the caller (Task 11's app entry
  point) owns that lifecycle, so tests can construct a real
  `NetworkMonitor` and drive `onChange` manually without its real
  `NWPathMonitor` ever running and firing unpredictably.

- [ ] **Step 1: Write the failing tests**

`Packages/VerbKit/Tests/VerbKitTests/VerbStoreTests.swift`:

```swift
import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class VerbStoreTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func makePersisting() throws -> SwiftDataVerbPersisting {
        let container = try VerbModelContainer.makeInMemory()
        return SwiftDataVerbPersisting(modelContext: ModelContext(container))
    }

    func testFirstLaunchSuccessPopulatesVerbsAndPersists() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        let persisting = try makePersisting()
        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
        XCTAssertTrue(store.hasLocalData)
        XCTAssertEqual(try persisting.loadAllVerbs().count, 2)
    }

    func testFirstLaunchOfflineFailureSetsFailedState() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.firstLaunchState, .failed(.offline))
        XCTAssertTrue(store.verbs.isEmpty)
    }

    func testFirstLaunchServerUnreachableFailureSetsFailedState() async throws {
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.serverUnreachable)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.firstLaunchState, .failed(.serverUnreachable))
    }

    func testManualRetryAfterFailureCanSucceed() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: NetworkMonitor())

        await store.start()
        XCTAssertEqual(store.firstLaunchState, .failed(.offline))

        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)
        await store.retryFirstLaunch()

        XCTAssertEqual(store.firstLaunchState, .success)
        XCTAssertEqual(store.verbs.count, 2)
    }

    func testReconnectCallbackRetriesAfterOfflineFailure() async throws {
        let data = try fixtureData()
        let manifest = VerbManifest(version: "1.0.0", sha256: sha256Hex(of: data))
        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline)

        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let networkMonitor = NetworkMonitor()
        let store = VerbStore(syncService: syncService, persisting: try makePersisting(), networkMonitor: networkMonitor)

        await store.start()
        XCTAssertEqual(store.firstLaunchState, .failed(.offline))

        fetcher.manifestResult = .success(manifest)
        fetcher.verbDataResult = .success(data)

        // NetworkMonitor's real NWPathMonitor was never started (VerbStore
        // only assigns onChange, doesn't call start()), so this manual
        // call is the only thing that can trigger it here — deterministic.
        networkMonitor.onChange?(true)
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(store.firstLaunchState, .success)
    }

    func testExistingLocalDataSkipsFirstLaunchFlowAndSyncsInBackground() async throws {
        let persisting = try makePersisting()
        let seedVerb = Verb(
            type: .u, label: "U-verb", dict: "のむ", kanji: nil, meaning: "to drink", description: "d",
            forms: VerbForms(masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d", te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"),
            examples: []
        )
        try persisting.replaceAllVerbs(with: [seedVerb])

        let fetcher = MockVerbDataFetcher()
        fetcher.manifestResult = .failure(VerbSyncError.offline) // background sync fails silently
        let syncService = VerbSyncService(fetcher: fetcher, syncState: InMemorySyncStateStore())
        let store = VerbStore(syncService: syncService, persisting: persisting, networkMonitor: NetworkMonitor())

        await store.start()

        XCTAssertEqual(store.verbs.map(\.dict), ["のむ"])
        XCTAssertEqual(store.firstLaunchState, .checking) // first-launch flow never entered
    }
}
```

```bash
cd Packages/VerbKit && swift test --filter VerbStoreTests 2>&1 | tail -30
```

Expected: build failure — `VerbStore`/`FirstLaunchState` don't exist yet.

- [ ] **Step 2: Implement**

`Packages/VerbKit/Sources/VerbKit/Store/FirstLaunchState.swift`:

```swift
public enum FirstLaunchState: Equatable, Sendable {
    case checking
    case fetching
    case failed(VerbSyncError)
    case success
}
```

`Packages/VerbKit/Sources/VerbKit/Store/VerbStore.swift`:

```swift
import Observation

@MainActor
@Observable
public final class VerbStore {
    public private(set) var verbs: [Verb] = []
    public private(set) var firstLaunchState: FirstLaunchState = .checking
    public var hasLocalData: Bool { !verbs.isEmpty }

    private let syncService: VerbSyncService
    private let persisting: VerbPersisting
    private let networkMonitor: NetworkMonitor

    public init(syncService: VerbSyncService, persisting: VerbPersisting, networkMonitor: NetworkMonitor) {
        self.syncService = syncService
        self.persisting = persisting
        self.networkMonitor = networkMonitor
    }

    public func start() async {
        networkMonitor.onChange = { [weak self] connected in
            guard connected else { return }
            guard case .failed(.offline) = self?.firstLaunchState else { return }
            Task { @MainActor [weak self] in
                await self?.retryFirstLaunch()
            }
        }

        if let cached = try? persisting.loadAllVerbs(), !cached.isEmpty {
            verbs = cached
            await syncInBackground()
            return
        }

        await runFirstLaunchFetch()
    }

    public func retryFirstLaunch() async {
        await runFirstLaunchFetch()
    }

    private func runFirstLaunchFetch() async {
        firstLaunchState = .checking
        firstLaunchState = .fetching
        do {
            let result = try await syncService.sync()
            switch result {
            case .upToDate:
                // Only reachable if a manifest was somehow already
                // recorded as synced with nothing locally persisted —
                // treat as corrupt local state rather than silently
                // leaving the user on an empty verb list forever.
                firstLaunchState = .failed(.malformedData)
            case let .updated(_, fetchedVerbs):
                try persisting.replaceAllVerbs(with: fetchedVerbs)
                verbs = fetchedVerbs
                firstLaunchState = .success
            }
        } catch let error as VerbSyncError {
            firstLaunchState = .failed(error)
        } catch {
            firstLaunchState = .failed(.malformedData)
        }
    }

    private func syncInBackground() async {
        guard let result = try? await syncService.sync() else { return }
        if case let .updated(_, fetchedVerbs) = result {
            try? persisting.replaceAllVerbs(with: fetchedVerbs)
            verbs = fetchedVerbs
        }
    }
}
```

- [ ] **Step 3: Run tests — expect all to pass**

```bash
cd Packages/VerbKit && swift test --filter VerbStoreTests 2>&1 | tail -30
```

Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 4: Run the full package suite**

```bash
cd Packages/VerbKit && swift test 2>&1 | tail -15
```

Expected: every test across the package passes.

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit/Sources/VerbKit/Store Packages/VerbKit/Tests/VerbKitTests/VerbStoreTests.swift
git commit -m "$(cat <<'EOF'
Add VerbStore: ties fetch, sync, and persistence together

On start(): loads cached verbs if present (syncing in the
background, silently) or drives a first-launch fetch state machine
(checking/fetching/failed/success) otherwise. Auto-retries the
first-launch fetch when NetworkMonitor reports connectivity
restored. VerbStore only wires networkMonitor.onChange — it does
not start/stop the monitor itself, keeping tests deterministic.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Migrate verb data to `data/` and publish it on GitHub

The legacy `public/verbs.json` wrapper shape (`{version, description,
verbs: [...]}`) already matches `VerbDataFile` exactly — the 9 new
optional `VerbForms` fields simply aren't present, which decodes fine
as `nil`. No reshaping is needed, just relocating it and generating its
manifest. This task also requires an actual `git push` — per this plan's
Global Constraints, **do not push without asking the user first.**

**Files:**
- Create: `data/verbs.json` (copied from the Task 1 snapshot commit's
  `public/verbs.json` — the working tree no longer has it, Task 1 removed
  it after committing it)
- Create: `data/manifest.json`

**Interfaces:**
- Consumes: nothing from prior tasks (this is content, not code) — but
  its output is what `GitHubVerbFetcher.githubMain()` (Task 6) fetches
  once pushed, and what Task 17's live smoke test depends on.
- Produces: the real hosted `data/verbs.json` / `data/manifest.json` this
  repo's `main` branch serves via `raw.githubusercontent.com`.

- [ ] **Step 1: Recover the legacy verb data from the Task 1 snapshot commit**

```bash
SNAPSHOT_COMMIT=$(git log --oneline --all --grep="Snapshot legacy Tauri/React web app" --format="%H" | head -1)
echo "Snapshot commit: $SNAPSHOT_COMMIT"
mkdir -p data
git show "$SNAPSHOT_COMMIT:public/verbs.json" > data/verbs.json
```

- [ ] **Step 2: Verify it's intact**

```bash
python3 -c "
import json
d = json.load(open('data/verbs.json'))
print('version:', d['version'])
print('verb count:', len(d['verbs']))
print('sample dict forms:', [v['dict'] for v in d['verbs'][:5]])
"
```

Expected: `verb count: 25` and recognizable dictionary forms (する,
くる, たべる, ...).

- [ ] **Step 3: Generate the manifest**

```bash
HASH=$(shasum -a 256 data/verbs.json | awk '{print $1}')
VERSION=$(python3 -c "import json; print(json.load(open('data/verbs.json'))['version'])")
python3 -c "
import json
manifest = {'version': '$VERSION', 'sha256': '$HASH'}
with open('data/manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)
    f.write('\n')
"
cat data/manifest.json
```

- [ ] **Step 4: Verify the manifest's hash actually matches the file**

```bash
python3 -c "
import json, hashlib
manifest = json.load(open('data/manifest.json'))
actual = hashlib.sha256(open('data/verbs.json', 'rb').read()).hexdigest()
assert manifest['sha256'] == actual, f'MISMATCH: {manifest[\"sha256\"]} != {actual}'
print('hash OK:', actual)
"
```

Expected: `hash OK: <64 hex chars>`, no assertion error.

- [ ] **Step 5: Commit**

```bash
git add data/verbs.json data/manifest.json
git commit -m "$(cat <<'EOF'
Publish verb data under data/ for GitHub-sourced fetching

Relocated from the removed public/verbs.json (same VerbDataFile
schema — the app's GitHubVerbFetcher reads these two files from
raw.githubusercontent.com once pushed). manifest.json's sha256 is
verified to match verbs.json's actual content.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Ask the user, then push**

**Stop here and ask the user for explicit confirmation before pushing** —
this makes the data live at a public URL
(`raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/data/...`)
immediately. If they decline or want to defer it, skip this step and
note in Task 17 that the live-fetch smoke test isn't possible yet (only
the mocked/unit-tested sync logic is verified) — everything else in this
plan still works. If they approve:

```bash
git push origin main
```

- [ ] **Step 7: Verify the live fetch actually works**

```bash
curl -s https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/data/manifest.json
curl -s https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/data/verbs.json | python3 -c "import json,sys; print(len(json.load(sys.stdin)['verbs']), 'verbs')"
```

Expected: the manifest JSON prints, and `25 verbs` prints. (GitHub's raw
content can take a minute to become available after a push — retry once
if it 404s immediately.)

---

## Task 11: App entry point, App Group entitlement, and first-launch UI

This is the first task that needs the App Group entitlement wired up
(Task 8's `VerbModelContainer.make()` requires it), so it adds that to
`project.yml` alongside building the actual first-launch screen.

**Files:**
- Modify: `project.yml` (add entitlements + development team)
- Create: `App/JPVerbConjugation.entitlements`
- Create: `App/DataLoadingView.swift`
- Create: `App/RootView.swift`
- Modify: `App/JPVerbConjugationApp.swift`

**Interfaces:**
- Consumes: `VerbStore`, `FirstLaunchState`, `NetworkMonitor`,
  `GitHubVerbFetcher`, `VerbSyncService`, `UserDefaultsSyncStateStore`,
  `SwiftDataVerbPersisting`, `VerbModelContainer` (Tasks 6, 7, 8, 9).
- Produces: a `DataLoadingView(state:, onRetry:)` SwiftUI view; a
  `RootView` that switches between it and a placeholder verb list (Task
  12 replaces the placeholder with the real navigation shell); an app
  entry point that constructs the real `VerbStore` and starts it.

- [ ] **Step 1: Find your Apple Developer Team ID**

Open Xcode → Settings → Accounts → select your Apple ID → the team name
shown (e.g. "Jane Doe (Personal Team)") has an ID in parentheses, or run:

```bash
security find-identity -v -p codesigning
```

and note the team ID from a matching signing identity. You'll use this
in Step 3.

- [ ] **Step 2: Create the entitlements file**

`App/JPVerbConjugation.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.dev.martinloeseth.jpverbconjugation</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Wire the entitlements and team ID into `project.yml`**

Modify `project.yml`'s `settings.base` block, adding two keys (replace
`YOUR_TEAM_ID` with the value from Step 1):

```yaml
        CODE_SIGN_ENTITLEMENTS: App/JPVerbConjugation.entitlements
        DEVELOPMENT_TEAM: "YOUR_TEAM_ID"
```

- [ ] **Step 4: Build `DataLoadingView`**

`App/DataLoadingView.swift`:

```swift
import SwiftUI
import VerbKit

struct DataLoadingView: View {
    let state: FirstLaunchState
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            switch state {
            case .checking, .fetching:
                ProgressView()
                Text("Loading verb data…")
                    .font(.headline)

            case .failed(.offline):
                Image(systemName: "wifi.slash")
                    .font(.system(size: 48))
                Text("No Internet Connection")
                    .font(.headline)
                Text("JP Verb Conjugation needs to download verb data the first time it runs. Connect to the internet and try again.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)

            case .failed(.serverUnreachable):
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 48))
                Text("Can't Reach the Server")
                    .font(.headline)
                Text("Your device is online, but the verb data couldn't be downloaded. This is usually temporary — try again in a moment.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)

            case .failed(.malformedData):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                Text("Something Went Wrong")
                    .font(.headline)
                Text("The downloaded verb data couldn't be read. Please try again.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)

            case .success:
                ProgressView()
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}
```

- [ ] **Step 5: Build `RootView` and wire the app entry point**

`App/RootView.swift`:

```swift
import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore

    var body: some View {
        if verbStore.hasLocalData {
            // Task 12 replaces this placeholder with the real
            // search/filter/navigation shell.
            List(verbStore.verbs) { verb in
                Text(verb.dict)
            }
        } else {
            DataLoadingView(state: verbStore.firstLaunchState) {
                Task { await verbStore.retryFirstLaunch() }
            }
        }
    }
}
```

`App/JPVerbConjugationApp.swift`:

```swift
import SwiftUI
import SwiftData
import VerbKit

@main
struct JPVerbConjugationApp: App {
    @State private var networkMonitor: NetworkMonitor
    @State private var verbStore: VerbStore

    init() {
        let container = Self.makeModelContainer()
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(container))
        let syncService = VerbSyncService(
            fetcher: GitHubVerbFetcher.githubMain(),
            syncState: UserDefaultsSyncStateStore()
        )
        let monitor = NetworkMonitor()
        _networkMonitor = State(initialValue: monitor)
        _verbStore = State(initialValue: VerbStore(syncService: syncService, persisting: persisting, networkMonitor: monitor))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(verbStore)
                .task {
                    networkMonitor.start()
                    await verbStore.start()
                }
        }
    }

    /// Falls back to an in-memory (non-persistent) store rather than
    /// crashing if the App Group container is unavailable — this can
    /// only happen from a signing/entitlement misconfiguration, which is
    /// a dev-time bug per the spec, not a scenario to build recovery UI
    /// for. One console log is enough.
    private static func makeModelContainer() -> ModelContainer {
        do {
            return try VerbModelContainer.make()
        } catch {
            print("⚠️ VerbModelContainer.make() failed (\(error)); falling back to an in-memory store. Check the App Group entitlement and DEVELOPMENT_TEAM in project.yml.")
            return try! VerbModelContainer.makeInMemory()
        }
    }
}
```

- [ ] **Step 6: Regenerate, build, and run**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" build 2>&1 | tail -15
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **` for both.

- [ ] **Step 7: Manually verify in Simulator**

Using the iOS Simulator tool: boot a simulator, install and launch the
built `.app` (from the iOS Simulator build's product path under
`DerivedData`), attach the live panel, and screenshot.

Expected: a brief "Loading verb data…" spinner, then (if Task 10's data
is live on GitHub) a plain list of 25 verb dictionary forms. If Task 10's
push was deferred, expect the "No Internet Connection" or "Can't Reach
the Server" screen instead — that's also a valid confirmation the screen
works; note in Task 17 that a live-data check is still pending.

- [ ] **Step 8: Commit**

```bash
git add project.yml App
git commit -m "$(cat <<'EOF'
Add app entry point, App Group entitlement, and first-launch UI

DataLoadingView covers all four FirstLaunchState cases with distinct
messaging (loading / offline / server-unreachable / malformed data)
and a retry button. RootView switches between it and a placeholder
verb list once VerbStore has local data — Task 12 replaces the
placeholder with the real navigation shell.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Verb list — search, filter, guide, navigation shell

Replaces `RootView`'s placeholder `List` with the real
`NavigationSplitView`-based shell: a sidebar/root list with search,
type-filter, the collapsible verb-type guide, and the て-form legend.
`NavigationSplitView`'s 2-column form collapses to stack navigation
automatically on compact width (iPhone) — no separate iPhone-specific
view is needed.

**Files:**
- Create: `App/VerbRow.swift`
- Create: `App/TeFormLegend.swift`
- Create: `App/VerbListView.swift`
- Modify: `App/RootView.swift`

**Interfaces:**
- Consumes: `Verb`, `VerbType`, `TeGroup`, `matchesSearch`,
  `matchesType`, `VerbStore` (Tasks 2, 3, 9).
- Produces: `VerbRow(verb:)`, `TeFormLegend`, `VerbListView(selection:
  Binding<Verb?>)` — the detail pane placeholder `RootView` gets here is
  replaced by the real `VerbDetailView` in Task 13.

- [ ] **Step 1: Build the row and legend views**

`App/VerbRow.swift`:

```swift
import SwiftUI
import VerbKit

struct VerbRow: View {
    let verb: Verb

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verb.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.tertiary, in: Capsule())

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verb.dict)
                        .font(.title3.weight(.bold))
                    if let kanji = verb.kanji {
                        Text(kanji)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(verb.meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

`App/TeFormLegend.swift`:

```swift
import SwiftUI
import VerbKit

struct TeFormLegend: View {
    private let rules: [(TeGroup, String)] = [
        (.tte, "う/つ/る → って"),
        (.nde, "む/ぶ/ぬ → んで"),
        (.ite, "く → いて"),
        (.ide, "ぐ → いで"),
        (.shite, "す → して"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(rules, id: \.0) { _, rule in
                    Text(rule)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tertiary, in: Capsule())
                }
            }
        }
        .listRowSeparator(.hidden)
    }
}
```

- [ ] **Step 2: Build `VerbListView`**

`App/VerbListView.swift`:

```swift
import SwiftUI
import VerbKit

private let githubSuggestVerbURL = URL(string: "https://github.com/martinloesethjensen/jp-verb-conjugation-app/issues/new?template=add-verb.yml")!

struct VerbListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var selection: Verb?
    @State private var search = ""
    @State private var typeFilter: VerbType?
    @State private var showGuide = false

    private var filtered: [Verb] {
        verbStore.verbs.filter { matchesType($0, filter: typeFilter) && matchesSearch($0, query: search) }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Picker("Type", selection: $typeFilter) {
                    Text("All").tag(VerbType?.none)
                    Text("Irregular").tag(VerbType?.some(.irregular))
                    Text("Ru-verbs").tag(VerbType?.some(.ru))
                    Text("U-verbs").tag(VerbType?.some(.u))
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                DisclosureGroup("Verb type guide", isExpanded: $showGuide) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("**Ru-verb (一段):** ends in -eru or -iru. Drop る and add the ending. Exceptions: はいる, かえる, きる look like ru-verbs but are u-verbs.")
                        Text("**U-verb (五段):** ends in any -u sound. If not -eru/-iru, it's a u-verb.")
                        Text("**Irregular:** only する and くる (and compounds like べんきょうする).")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                TeFormLegend()
            }

            Section {
                ForEach(filtered) { verb in
                    VerbRow(verb: verb)
                }
            } footer: {
                Link("Suggest a verb", destination: githubSuggestVerbURL)
                    .font(.caption)
            }
        }
        .searchable(text: $search, prompt: "Search hiragana, kanji, or English…")
        .navigationTitle("動詞活用表")
        .overlay {
            if !search.isEmpty && filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}
```

- [ ] **Step 3: Wire it into the navigation shell**

Modify `App/RootView.swift`:

```swift
import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore
    @State private var selection: Verb?

    var body: some View {
        if verbStore.hasLocalData {
            NavigationSplitView {
                VerbListView(selection: $selection)
            } detail: {
                // Task 13 replaces this placeholder with the real
                // VerbDetailView (forms, description, examples/quiz/Jisho).
                if let selection {
                    Text(selection.dict)
                        .font(.largeTitle)
                } else {
                    ContentUnavailableView("Select a Verb", systemImage: "text.book.closed")
                }
            }
        } else {
            DataLoadingView(state: verbStore.firstLaunchState) {
                Task { await verbStore.retryFirstLaunch() }
            }
        }
    }
}
```

- [ ] **Step 4: Rebuild and verify**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" build 2>&1 | tail -15
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **` for both.

In Simulator: confirm the verb list loads with dict/kanji/meaning per
row, typing in the search field filters it, the segmented control
filters by type, the "Verb type guide" section expands/collapses, the
て-form legend scrolls horizontally, and tapping a verb shows its
dictionary form in the detail pane (or pushes to it, on iPhone width).

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "$(cat <<'EOF'
Add verb list: search, type filter, guide, and navigation shell

NavigationSplitView-based root view — collapses to stack navigation
automatically on iPhone width, no separate compact-width view
needed. VerbListView covers search (.searchable), type filtering
(segmented Picker), the collapsible verb-type guide, and the
て-form legend, matching the web app's header controls.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: Verb detail — grouped forms, description, actions

Replaces `RootView`'s placeholder detail pane with the real
`VerbDetailView`: description, notes, the Polite/Plain/て-form/Advanced
grouped form breakdown from the spec (Advanced only appears when a verb
actually has any of the optional fields populated — none do yet, until
the content pipeline lands), and the Examples/Test this verb/Jisho
actions.

**Files:**
- Create: `App/FormGroupSection.swift`
- Create: `App/VerbDetailView.swift`
- Modify: `App/RootView.swift`

**Interfaces:**
- Consumes: `Verb`, `VerbForms`, `TeGroup`, `buildQuestions`,
  `QuizQuestion` (Tasks 2, 4).
- Produces: `FormGroupSection(title:, forms: [(String, String)],
  defaultExpanded:)`, `VerbDetailView(verb:, onExamples:, onQuiz:)` —
  `onExamples`/`onQuiz` are wired to `@State` flags on `RootView` that
  Tasks 14 and 15 attach `.sheet`/`.fullScreenCover` presentations to.

- [ ] **Step 1: Build the reusable grouped-forms section**

`App/FormGroupSection.swift`:

```swift
import SwiftUI

struct FormGroupSection: View {
    let title: String
    let forms: [(String, String)]
    @State private var isExpanded: Bool

    init(title: String, forms: [(String, String)], defaultExpanded: Bool) {
        self.title = title
        self.forms = forms
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: $isExpanded) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(forms, id: \.0) { label, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.top, 4)
        }
        .font(.subheadline.weight(.semibold))
    }
}
```

- [ ] **Step 2: Build `VerbDetailView`**

`App/VerbDetailView.swift`:

```swift
import SwiftUI
import VerbKit

struct VerbDetailView: View {
    let verb: Verb
    var onExamples: () -> Void
    var onQuiz: () -> Void

    private var jishoURL: URL {
        let encoded = verb.dict.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verb.dict
        return URL(string: "https://jisho.org/search/\(encoded)")!
    }

    private var hasAdvancedForms: Bool {
        let f = verb.forms
        return [f.potential, f.volitional, f.passive, f.causative, f.causativePassive, f.conditionalBa, f.conditionalTara, f.imperative, f.tai]
            .contains { $0 != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                if let notes = verb.notes {
                    notesBox(notes)
                }
                Text(verb.description)
                    .font(.body)
                formGroups
            }
            .padding()
        }
        .navigationTitle(verb.dict)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verb.label)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.tertiary, in: Capsule())
                if let teGroup = verb.teGroup {
                    Text(teGroup.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verb.dict).font(.system(size: 34, weight: .heavy))
                if let kanji = verb.kanji {
                    Text(kanji).font(.title2).foregroundStyle(.secondary)
                }
            }
            Text(verb.meaning).font(.headline).foregroundStyle(.secondary).italic()
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Examples", systemImage: "book", action: onExamples)
            Button("Test this verb", systemImage: "gamecontroller", action: onQuiz)
                .buttonStyle(.borderedProminent)
            Link(destination: jishoURL) {
                Label("Jisho", systemImage: "link")
            }
        }
        .buttonStyle(.bordered)
    }

    private func notesBox(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
            Text(notes).font(.footnote)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var formGroups: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormGroupSection(title: "Polite", forms: [
                ("ます (polite +)", verb.forms.masuPos),
                ("ません (polite −)", verb.forms.masuNeg),
                ("ました (polite past +)", verb.forms.masuPast),
                ("ませんでした (polite past −)", verb.forms.masuPastNeg),
            ], defaultExpanded: true)

            FormGroupSection(title: "Plain", forms: [
                ("short (present +)", verb.forms.shortPos),
                ("short (present −)", verb.forms.shortNeg),
                ("short (past +)", verb.forms.shortPast),
                ("short (past −)", verb.forms.shortPastNeg),
            ], defaultExpanded: true)

            FormGroupSection(title: "て-form", forms: [
                ("て-form", verb.forms.te),
            ], defaultExpanded: true)

            if hasAdvancedForms {
                FormGroupSection(
                    title: "Advanced",
                    forms: [
                        ("Potential", verb.forms.potential),
                        ("Volitional", verb.forms.volitional),
                        ("Passive", verb.forms.passive),
                        ("Causative", verb.forms.causative),
                        ("Causative-passive", verb.forms.causativePassive),
                        ("Conditional (ば)", verb.forms.conditionalBa),
                        ("Conditional (たら)", verb.forms.conditionalTara),
                        ("Imperative", verb.forms.imperative),
                        ("たい (want to)", verb.forms.tai),
                    ].compactMap { label, value in value.map { (label, $0) } },
                    defaultExpanded: false
                )
            }
        }
    }
}
```

- [ ] **Step 3: Wire it into `RootView`**

Modify `App/RootView.swift`:

```swift
import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore
    @State private var selection: Verb?
    @State private var showingExamples = false
    @State private var quizQuestions: [QuizQuestion]?

    var body: some View {
        if verbStore.hasLocalData {
            NavigationSplitView {
                VerbListView(selection: $selection)
            } detail: {
                if let selection {
                    VerbDetailView(
                        verb: selection,
                        onExamples: { showingExamples = true },
                        onQuiz: { quizQuestions = buildQuestions(verbs: [selection], count: 9) }
                    )
                } else {
                    ContentUnavailableView("Select a Verb", systemImage: "text.book.closed")
                }
            }
        } else {
            DataLoadingView(state: verbStore.firstLaunchState) {
                Task { await verbStore.retryFirstLaunch() }
            }
        }
    }
}
```

(`showingExamples`/`quizQuestions` don't drive any UI yet — Task 14 adds
a `.sheet(isPresented: $showingExamples)`, Task 15 a `.fullScreenCover`/
window keyed on `quizQuestions`.)

- [ ] **Step 4: Rebuild and verify**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`.

In Simulator: select a verb and confirm the detail pane shows its
description, notes (if any), the Polite/Plain/て-form sections expanded
by default, no "Advanced" section (none of the migrated data has those
fields populated yet), and tapping "Jisho" opens `jisho.org` for that
verb in the browser.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "$(cat <<'EOF'
Add verb detail view: grouped forms, description, actions

Polite/Plain/て-form sections expanded by default, Advanced
collapsed and only shown when a verb has optional forms populated
(none do yet — the content pipeline backfills them later, no
schema change needed when it does). Examples/quiz buttons wire to
RootView state that Tasks 14/15 attach presentations to.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Examples sheet

**Files:**
- Create: `App/ExamplesView.swift`
- Modify: `App/RootView.swift`

**Interfaces:**
- Consumes: `Verb`, `VerbExample`, `FormKey` (Task 2).
- Produces: `ExamplesView(verb:)`.

- [ ] **Step 1: Build `ExamplesView`**

`App/ExamplesView.swift`:

```swift
import SwiftUI
import VerbKit

struct ExamplesView: View {
    let verb: Verb
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(verb.examples, id: \.self) { example in
                VStack(alignment: .leading, spacing: 4) {
                    Text(formLabel(example.form))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(example.jp)
                        .font(.title3)
                    Text(example.en)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("\(verb.dict) — Examples")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formLabel(_ key: FormKey) -> String {
        switch key {
        case .masuPos: return "ます (polite +)"
        case .masuNeg: return "ません (polite −)"
        case .masuPast: return "ました (polite past +)"
        case .masuPastNeg: return "ませんでした (polite past −)"
        case .te: return "て-form"
        case .shortPos: return "short (present +)"
        case .shortNeg: return "short (present −)"
        case .shortPast: return "short (past +)"
        case .shortPastNeg: return "short (past −)"
        }
    }
}
```

- [ ] **Step 2: Wire it into `RootView`**

Modify `App/RootView.swift` — add the sheet modifier to the outer `if`
branch (attach to `NavigationSplitView`, after its `detail:` closure):

```swift
            }
            .sheet(isPresented: $showingExamples) {
                if let selection {
                    ExamplesView(verb: selection)
                }
            }
```

- [ ] **Step 3: Rebuild and verify**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`.

In Simulator: from a verb's detail screen, tap "Examples" — confirm a
sheet lists that verb's example sentences with form labels, Japanese
text, and English translation, and "Done" dismisses it.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "$(cat <<'EOF'
Add examples sheet

Lists a verb's example sentences grouped by which form each one
demonstrates. Presented from VerbDetailView's Examples button via
RootView's showingExamples state.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Quiz UI — question, results, and platform presentation

**Deviation from the spec, flagged here:** section 2 called for "a
separate resizable window on macOS." A genuinely separate `Window` scene
needs SwiftUI's value-based multi-window APIs (window IDs, `openWindow`/
`dismissWindow` environment actions, Codable/Hashable data passing) —
real added architecture for a personal-scope app. This task instead uses
a large `.sheet` with a fixed minimum size on macOS, and `.fullScreenCover`
on iOS/iPadOS — both are full-viewport takeovers, just not a literally
separate OS window on Mac. Flag if you want the real separate-window
version instead.

**Note:** this task builds the quiz with the same plain
`.regularMaterial`/`.borderedProminent` styling as the rest of the app
had at this point in the plan. Task 17 (later) retrofits it — along with
the list/detail screens — onto Liquid Glass and adds the immersive
fullscreen treatment (hidden home indicator), once the deployment target
that Liquid Glass requires has actually been raised. Building it here
first and reskinning once in Task 17 avoids a sequencing hazard: this
task runs before the deployment-target bump, so Liquid Glass APIs
wouldn't compile yet if used here directly.

**Files:**
- Create: `App/FormLabels.swift`
- Create: `App/QuizQuestionView.swift`
- Create: `App/QuizResultsView.swift`
- Create: `App/QuizView.swift`
- Modify: `App/RootView.swift`

**Interfaces:**
- Consumes: `QuizViewModel`, `QuizQuestion`, `QuizResult`, `FormKey`
  (Tasks 4, 5).
- Produces: `formLabels: [FormKey: String]`, `QuizQuestionView(viewModel:,
  question:)`, `QuizResultsView(viewModel:, onDone:)`, `QuizView(questions:
  [QuizQuestion], onDone:)`.

- [ ] **Step 1: Shared form labels**

`App/FormLabels.swift`:

```swift
import VerbKit

let formLabels: [FormKey: String] = [
    .masuPos: "ます (polite +)",
    .masuNeg: "ません (polite −)",
    .masuPast: "ました (polite past +)",
    .masuPastNeg: "ませんでした (polite past −)",
    .te: "て-form",
    .shortPos: "short (present +)",
    .shortNeg: "short (present −)",
    .shortPast: "short (past +)",
    .shortPastNeg: "short (past −)",
]
```

- [ ] **Step 2: Build the question screen**

`App/QuizQuestionView.swift`:

```swift
import SwiftUI
import VerbKit

struct QuizQuestionView: View {
    var viewModel: QuizViewModel
    let question: QuizQuestion

    private let shapeSymbols = ["triangle.fill", "diamond.fill", "circle.fill", "square.fill"]
    private let choiceColors: [Color] = [.red, .blue, .yellow, .green]

    var body: some View {
        VStack(spacing: 20) {
            header
            promptCard
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                    choiceButton(choice, index: index)
                }
            }
            if viewModel.isAnswered {
                feedback
                Button(viewModel.index + 1 >= viewModel.questions.count ? "See Results →" : "Next →") {
                    viewModel.advance()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var header: some View {
        HStack {
            Text("\(viewModel.index + 1) / \(viewModel.questions.count)")
                .font(.headline)
            Spacer()
            Text("⭐ \(viewModel.score)")
        }
    }

    private var promptCard: some View {
        VStack(spacing: 8) {
            Text(.init("What is the **\(formLabels[question.form] ?? "")** form of…"))
                .font(.caption)
                .multilineTextAlignment(.center)
            Text(question.verb.dict)
                .font(.system(size: 36, weight: .heavy))
            if let kanji = question.verb.kanji {
                Text(kanji).font(.title3).foregroundStyle(.secondary)
            }
            Text(question.verb.meaning)
                .italic()
                .foregroundStyle(.secondary)
            Text("⏱ \(viewModel.timeLeft)s")
                .font(.headline)
                .foregroundStyle(timerColor)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var timerColor: Color {
        viewModel.timeLeft > 10 ? .green : viewModel.timeLeft > 5 ? .orange : .red
    }

    private func choiceButton(_ choice: String, index: Int) -> some View {
        let isCorrect = choice == question.correct
        let isSelected = choice == viewModel.selected
        var background = choiceColors[index % choiceColors.count]
        if viewModel.isAnswered {
            if isCorrect { background = .green }
            else if isSelected { background = .red }
        }
        return Button {
            viewModel.choose(choice)
        } label: {
            HStack {
                Image(systemName: shapeSymbols[index % shapeSymbols.count])
                Text(choice)
                if viewModel.isAnswered && isCorrect { Image(systemName: "checkmark") }
                if viewModel.isAnswered && isSelected && !isCorrect { Image(systemName: "xmark") }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.borderedProminent)
        .tint(background)
        .disabled(viewModel.isAnswered)
        .opacity(viewModel.isAnswered && !isCorrect && !isSelected ? 0.35 : 1)
    }

    private var feedback: some View {
        Group {
            if viewModel.timedOut {
                Text("⏰ Time's up!")
            } else if viewModel.selected == question.correct {
                Text("🎉 Correct!")
            } else {
                Text("❌ The answer was: \(question.correct)")
            }
        }
        .font(.headline)
        .padding()
        .frame(maxWidth: .infinity)
        .background(viewModel.timedOut ? Color.orange : (viewModel.selected == question.correct ? Color.green : Color.red))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

- [ ] **Step 3: Build the results screen**

`App/QuizResultsView.swift`:

```swift
import SwiftUI
import VerbKit

struct QuizResultsView: View {
    var viewModel: QuizViewModel
    var onDone: () -> Void

    private var percentage: Int {
        guard !viewModel.questions.isEmpty else { return 0 }
        return Int((Double(viewModel.score) / Double(viewModel.questions.count) * 100).rounded())
    }

    private var emoji: String {
        switch percentage {
        case 100: return "🏆"
        case 80...: return "🌟"
        case 60...: return "👍"
        case 40...: return "📚"
        default: return "💪"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(emoji).font(.system(size: 56))
                Text("Quiz Complete!").font(.title2.weight(.bold))
                Text("\(viewModel.score)/\(viewModel.questions.count)")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(percentage >= 60 ? .green : .orange)
                Text("\(percentage)% correct").foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.offset) { _, result in
                        resultRow(result)
                        Divider()
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button("Back to Table", action: onDone)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func resultRow(_ result: QuizResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(result.ok ? "✅" : "❌")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.verb) — \(formLabels[result.form] ?? "")")
                    .font(.subheadline.weight(.semibold))
                if !result.ok {
                    Text("You chose: \(result.chosen)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Correct: \(result.correct)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
        }
        .padding(12)
    }
}
```

- [ ] **Step 4: Build `QuizView` (timer-driving container)**

`App/QuizView.swift`:

```swift
import SwiftUI
import VerbKit

struct QuizView: View {
    @State private var viewModel: QuizViewModel
    var onDone: () -> Void

    init(questions: [QuizQuestion], onDone: @escaping () -> Void) {
        _viewModel = State(initialValue: QuizViewModel(questions: questions))
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if viewModel.finished {
                QuizResultsView(viewModel: viewModel, onDone: onDone)
            } else if let question = viewModel.currentQuestion {
                QuizQuestionView(viewModel: viewModel, question: question)
            }
        }
        // Restarts the countdown loop each time the question index
        // changes; SwiftUI cancels the previous instance automatically.
        .task(id: viewModel.index) {
            while !viewModel.isAnswered && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                viewModel.tickTimer()
            }
        }
    }
}
```

- [ ] **Step 5: Wire platform-specific presentation into `RootView`**

Modify `App/RootView.swift` — add after the `.sheet(isPresented:
$showingExamples)` modifier from Task 14:

```swift
            #if os(iOS)
            .fullScreenCover(isPresented: quizPresentationBinding) {
                if let quizQuestions {
                    QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
                }
            }
            #else
            .sheet(isPresented: quizPresentationBinding) {
                if let quizQuestions {
                    QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
                        .frame(minWidth: 560, minHeight: 640)
                }
            }
            #endif
```

And add this computed property inside `RootView`:

```swift
    private var quizPresentationBinding: Binding<Bool> {
        Binding(
            get: { quizQuestions != nil },
            set: { isPresented in if !isPresented { quizQuestions = nil } }
        )
    }
```

- [ ] **Step 6: Rebuild and verify**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" build 2>&1 | tail -15
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **` for both.

In Simulator: from a verb's detail screen, tap "Test this verb" — confirm
the quiz takes over full-screen, the countdown ticks down every second,
selecting an answer highlights correct/incorrect and shows feedback,
"Next →" advances through all questions, letting the timer hit 0 shows
"Time's up!" without crashing, and the final screen shows the score,
per-question breakdown, and "Back to Table" returns to the detail view.

- [ ] **Step 7: Commit**

```bash
git add App
git commit -m "$(cat <<'EOF'
Add quiz UI: question screen, results, and platform presentation

QuizView drives QuizViewModel's timer via a self-cancelling .task
loop keyed on the question index. Kahoot-style 4-choice question
screen and a results breakdown, matching the web app. Presented as
fullScreenCover on iOS/iPadOS; a large fixed-size sheet on macOS in
place of a genuinely separate Window scene (documented deviation).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Settings — appearance & quiz count, persisted via App Group

This also fixes a gap from Task 13: the web app has **two** quiz entry
points — "Test this verb" (single verb, wired in Task 13) and "Random
Quiz" (all verbs, using the configured question count) in the list
header. This task adds the missing one, since it needs the same
persisted question-count preference Settings introduces.

**Files:**
- Create: `App/UserDefaults+AppGroup.swift`
- Create: `App/SettingsView.swift`
- Modify: `App/VerbListView.swift` (full replacement — adds the
  Random Quiz / Settings toolbar buttons)
- Modify: `App/RootView.swift` (full replacement — wires Settings,
  applies appearance, fixes the single-verb quiz count, adds Random
  Quiz)
- Modify: `App/JPVerbConjugationApp.swift` (adds the macOS `Settings`
  scene)

**Interfaces:**
- Consumes: `buildQuestions`, `Verb`, `VerbType` (Tasks 2, 4).
- Produces: `UserDefaults.appGroup`, `AppearanceMode` (`.system`/
  `.light`/`.dark`, with `.colorScheme: ColorScheme?`), `SettingsView`.
  The `"appearanceMode"`/`"quizQuestionCount"` `@AppStorage` keys, both
  backed by `UserDefaults.appGroup`, are the persisted preferences the
  spec calls for (App Group-shared so a future widget can read them).

- [ ] **Step 1: Shared App Group UserDefaults**

`App/UserDefaults+AppGroup.swift`:

```swift
import Foundation

extension UserDefaults {
    static let appGroup = UserDefaults(suiteName: "group.dev.martinloeseth.jpverbconjugation") ?? .standard
}
```

- [ ] **Step 2: Build `SettingsView`**

`App/SettingsView.swift`:

```swift
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Hashable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage("appearanceMode", store: .appGroup) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private let questionCountOptions = [5, 10, 15, 20, 30]

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: appearanceMode) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("Quiz") {
                Picker("Number of questions", selection: $quizQuestionCount) {
                    ForEach(questionCountOptions, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .frame(minWidth: 320, minHeight: 240)
    }
}
```

- [ ] **Step 3: Add the toolbar buttons — replace `App/VerbListView.swift` entirely**

```swift
import SwiftUI
import VerbKit

private let githubSuggestVerbURL = URL(string: "https://github.com/martinloesethjensen/jp-verb-conjugation-app/issues/new?template=add-verb.yml")!

struct VerbListView: View {
    @Environment(VerbStore.self) private var verbStore
    @Binding var selection: Verb?
    var onRandomQuiz: () -> Void
    var onSettings: () -> Void
    @State private var search = ""
    @State private var typeFilter: VerbType?
    @State private var showGuide = false

    private var filtered: [Verb] {
        verbStore.verbs.filter { matchesType($0, filter: typeFilter) && matchesSearch($0, query: search) }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Picker("Type", selection: $typeFilter) {
                    Text("All").tag(VerbType?.none)
                    Text("Irregular").tag(VerbType?.some(.irregular))
                    Text("Ru-verbs").tag(VerbType?.some(.ru))
                    Text("U-verbs").tag(VerbType?.some(.u))
                }
                .pickerStyle(.segmented)
                .listRowSeparator(.hidden)

                DisclosureGroup("Verb type guide", isExpanded: $showGuide) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("**Ru-verb (一段):** ends in -eru or -iru. Drop る and add the ending. Exceptions: はいる, かえる, きる look like ru-verbs but are u-verbs.")
                        Text("**U-verb (五段):** ends in any -u sound. If not -eru/-iru, it's a u-verb.")
                        Text("**Irregular:** only する and くる (and compounds like べんきょうする).")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                TeFormLegend()
            }

            Section {
                ForEach(filtered) { verb in
                    VerbRow(verb: verb)
                }
            } footer: {
                Link("Suggest a verb", destination: githubSuggestVerbURL)
                    .font(.caption)
            }
        }
        .searchable(text: $search, prompt: "Search hiragana, kanji, or English…")
        .navigationTitle("動詞活用表")
        .overlay {
            if !search.isEmpty && filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Random Quiz", systemImage: "gamecontroller", action: onRandomQuiz)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Settings", systemImage: "gearshape", action: onSettings)
            }
        }
    }
}
```

- [ ] **Step 4: Wire everything together — replace `App/RootView.swift` entirely**

```swift
import SwiftUI
import VerbKit

struct RootView: View {
    @Environment(VerbStore.self) private var verbStore
    @AppStorage("appearanceMode", store: .appGroup) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @AppStorage("quizQuestionCount", store: .appGroup) private var quizQuestionCount = 10
    @State private var selection: Verb?
    @State private var showingExamples = false
    @State private var showingSettings = false
    @State private var quizQuestions: [QuizQuestion]?

    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceModeRaw) ?? .system
    }

    var body: some View {
        Group {
            if verbStore.hasLocalData {
                NavigationSplitView {
                    VerbListView(
                        selection: $selection,
                        onRandomQuiz: { quizQuestions = buildQuestions(verbs: verbStore.verbs, count: quizQuestionCount) },
                        onSettings: { showingSettings = true }
                    )
                } detail: {
                    if let selection {
                        VerbDetailView(
                            verb: selection,
                            onExamples: { showingExamples = true },
                            onQuiz: { quizQuestions = buildQuestions(verbs: [selection], count: min(quizQuestionCount, 9)) }
                        )
                    } else {
                        ContentUnavailableView("Select a Verb", systemImage: "text.book.closed")
                    }
                }
                .sheet(isPresented: $showingExamples) {
                    if let selection {
                        ExamplesView(verb: selection)
                    }
                }
                .sheet(isPresented: $showingSettings) {
                    NavigationStack {
                        SettingsView()
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showingSettings = false }
                                }
                            }
                    }
                }
                #if os(iOS)
                .fullScreenCover(isPresented: quizPresentationBinding) {
                    if let quizQuestions {
                        QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
                    }
                }
                #else
                .sheet(isPresented: quizPresentationBinding) {
                    if let quizQuestions {
                        QuizView(questions: quizQuestions, onDone: { self.quizQuestions = nil })
                            .frame(minWidth: 560, minHeight: 640)
                    }
                }
                #endif
            } else {
                DataLoadingView(state: verbStore.firstLaunchState) {
                    Task { await verbStore.retryFirstLaunch() }
                }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
    }

    private var quizPresentationBinding: Binding<Bool> {
        Binding(
            get: { quizQuestions != nil },
            set: { isPresented in if !isPresented { quizQuestions = nil } }
        )
    }
}
```

- [ ] **Step 5: Register the macOS Settings scene**

Modify `App/JPVerbConjugationApp.swift`'s `body`, adding the `Settings`
scene after `WindowGroup`:

```swift
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(verbStore)
                .task {
                    networkMonitor.start()
                    await verbStore.start()
                }
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
```

- [ ] **Step 6: Rebuild and verify**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" build 2>&1 | tail -15
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **` for both.

In Simulator: tap "Random Quiz" in the list toolbar and confirm it quizzes
across all verbs using the configured question count; tap "Settings",
change the appearance to Dark, confirm the whole app switches
immediately; change the question count, quit and relaunch the app (⌘Q
then relaunch, or stop/restart in Simulator), and confirm both settings
persisted. On macOS specifically, confirm ⌘, opens the same Settings form
as a native Preferences window.

- [ ] **Step 7: Commit**

```bash
git add App
git commit -m "$(cat <<'EOF'
Add settings: persisted appearance and quiz question count

Tri-state appearance (System/Light/Dark) and quiz question count,
both @AppStorage-backed by the shared App Group UserDefaults suite
so a future widget can read them. Also adds the "Random Quiz"
(all-verbs) entry point that was missing since Task 13 only wired
the per-verb "Test this verb" flow — both now use the same
persisted question-count preference.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 17: Visual polish — color-coding and Liquid Glass across existing screens

Added mid-implementation per spec section 10 (user feedback after Task
14 was already built, Tasks 15-16 not yet dispatched): the app should
feel more colorful — echoing the original web app's per-verb-type and
per-て-form-group color palette, which the native port simplified away to
plain gray capsules — and its custom-drawn surfaces (as opposed to
standard system chrome, which already renders with Liquid Glass for
free) should adopt `.glassEffect` so they read as part of the same
design language, with the quiz specifically also getting a true
immersive fullscreen treatment. This task raises the deployment target
(required for the Liquid Glass APIs), retrofits `VerbRow`,
`TeFormLegend`, `FormGroupSection`, `VerbDetailView`, and the quiz
screens (`QuizQuestionView`/`QuizResultsView`/`QuizView`, built plain in
Task 15 specifically to avoid using Liquid Glass APIs before this task
raises the deployment target that makes them available) — Task 16
(settings) is a plain system `Form` with no custom-drawn surfaces to
retrofit, nothing to do there.

**Files:**
- Create: `App/VerbColors.swift`
- Modify: `App/VerbRow.swift` (full replacement)
- Modify: `App/TeFormLegend.swift` (full replacement)
- Modify: `App/FormGroupSection.swift` (full replacement)
- Modify: `App/VerbDetailView.swift` (full replacement)
- Modify: `App/QuizQuestionView.swift`, `App/QuizResultsView.swift`,
  `App/QuizView.swift` (targeted edits, not full replacement)
- Modify: `project.yml`, `Packages/VerbKit/Package.swift` (deployment
  target)

**Interfaces:**
- Consumes: `VerbType`, `TeGroup` (Task 2).
- Produces: `VerbType.accentColor: Color`, `TeGroup.accentColor: Color` —
  used by all four modified views, and available to any future screen
  that wants the same palette.

- [ ] **Step 1: Raise the deployment target to iOS 26.0 / macOS 26.0**

Liquid Glass APIs (`.glassEffect()`, `.buttonStyle(.glass)`,
`.buttonStyle(.glassProminent)`) require iOS 26/macOS 26. Two independent
changes are needed (verified directly against this toolchain, not
assumed):

1. `project.yml`'s `targets.JPVerbConjugation.deploymentTarget` — from
   `iOS: "17.0"` / `macOS: "14.0"` to `iOS: "26.0"` / `macOS: "26.0"`.
   This governs the App target (built via Xcode/XcodeGen, not SwiftPM) —
   `SWIFT_VERSION: "5.0"` stays unchanged, this is purely an
   API-availability floor, not a language-mode change.
2. `Packages/VerbKit/Package.swift` needs THREE coordinated changes, not
   just the platforms list — the `.v26` platform case requires
   `swift-tools-version:6.2` (confirmed: `.v26` fails to compile under
   the current `5.10` with "'v26' was introduced in PackageDescription
   6.2"), and bumping tools-version to 6.0+ silently switches SwiftPM
   targets to Swift 6's strict-concurrency language mode by default
   unless pinned back — which risks turning the `@MainActor`-adjacent
   pattern already flagged as a deferred Minor finding in Task 9's
   review into a real compile error. Confirmed via a standalone scratch
   package that all three together compile clean:
   - Header: `// swift-tools-version:5.10` → `// swift-tools-version:6.2`
   - `platforms: [.iOS(.v17), .macOS(.v14)]` → `platforms: [.iOS(.v26), .macOS(.v26)]`
   - Add `swiftLanguageModes: [.v5]` as a new top-level `Package(...)`
     argument (alongside `name`/`platforms`/`products`/`targets`), to
     keep VerbKit compiling in Swift 5 language mode despite the
     tools-version bump — do not skip this, it's what prevents the
     strict-concurrency risk above.

```bash
./scripts/generate-project.sh
cd Packages/VerbKit && swift build 2>&1 | tail -10 && cd ../..
```

Expected: package still builds clean after the platform bump (confirms
no accidental syntax issue in the edit, before moving on to real
Liquid Glass code). If you see a strict-concurrency-flavored error here
that wasn't present before, `swiftLanguageModes: [.v5]` is missing or
misplaced — this exact combination was verified to work.

- [ ] **Step 2: Define the color palette**

`App/VerbColors.swift`:

```swift
import SwiftUI
import VerbKit

extension VerbType {
    /// Echoes the original web app's per-type palette (getTypeColors).
    var accentColor: Color {
        switch self {
        case .irregular: return Color(red: 0.973, green: 0.443, blue: 0.400)
        case .ru: return Color(red: 0.486, green: 0.831, blue: 0.992)
        case .u: return Color(red: 0.992, green: 0.792, blue: 0.243)
        }
    }
}

extension TeGroup {
    /// Echoes the original web app's per-て-form-group palette (TE_GROUPS).
    var accentColor: Color {
        switch self {
        case .tte: return Color(red: 0.976, green: 0.451, blue: 0.086)
        case .nde: return Color(red: 0.176, green: 0.831, blue: 0.749)
        case .ite: return Color(red: 0.655, green: 0.545, blue: 0.980)
        case .ide: return Color(red: 0.506, green: 0.549, blue: 0.973)
        case .shite: return Color(red: 0.984, green: 0.447, blue: 0.522)
        }
    }
}
```

- [ ] **Step 3: Color and glass the list row — replace `App/VerbRow.swift` entirely**

```swift
import SwiftUI
import VerbKit

struct VerbRow: View {
    let verb: Verb

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verb.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(verb.type.accentColor)
                .glassEffect(.regular.tint(verb.type.accentColor), in: Capsule())

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verb.dict)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(verb.teGroup?.accentColor ?? verb.type.accentColor)
                    if let kanji = verb.kanji {
                        Text(kanji)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(verb.meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 4: Color and glass the て-form legend chips — replace `App/TeFormLegend.swift` entirely**

```swift
import SwiftUI
import VerbKit

struct TeFormLegend: View {
    private let rules: [(TeGroup, String)] = [
        (.tte, "う/つ/る → って"),
        (.nde, "む/ぶ/ぬ → んで"),
        (.ite, "く → いて"),
        (.ide, "ぐ → いで"),
        (.shite, "す → して"),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(rules, id: \.0) { group, rule in
                    Text(rule)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(group.accentColor)
                        .glassEffect(.regular.tint(group.accentColor), in: Capsule())
                }
            }
        }
        .listRowSeparator(.hidden)
    }
}
```

- [ ] **Step 5: Glass the form-group tiles — replace `App/FormGroupSection.swift` entirely**

```swift
import SwiftUI

struct FormGroupSection: View {
    let title: String
    let forms: [(String, String)]
    @State private var isExpanded: Bool

    init(title: String, forms: [(String, String)], defaultExpanded: Bool) {
        self.title = title
        self.forms = forms
        _isExpanded = State(initialValue: defaultExpanded)
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: $isExpanded) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(forms, id: \.0) { label, value in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.top, 4)
        }
        .font(.subheadline.weight(.semibold))
    }
}
```

- [ ] **Step 6: Color and glass the detail header/actions/notes — replace `App/VerbDetailView.swift` entirely**

```swift
import SwiftUI
import VerbKit

struct VerbDetailView: View {
    let verb: Verb
    var onExamples: () -> Void
    var onQuiz: () -> Void

    private var accent: Color {
        verb.teGroup?.accentColor ?? verb.type.accentColor
    }

    private var jishoURL: URL {
        let encoded = verb.dict.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verb.dict
        return URL(string: "https://jisho.org/search/\(encoded)")!
    }

    private var hasAdvancedForms: Bool {
        let f = verb.forms
        return [f.potential, f.volitional, f.passive, f.causative, f.causativePassive, f.conditionalBa, f.conditionalTara, f.imperative, f.tai]
            .contains { $0 != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                if let notes = verb.notes {
                    notesBox(notes)
                }
                Text(verb.description)
                    .font(.body)
                formGroups
            }
            .padding()
        }
        .navigationTitle(verb.dict)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verb.label)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .foregroundStyle(verb.type.accentColor)
                    .glassEffect(.regular.tint(verb.type.accentColor), in: Capsule())
                if let teGroup = verb.teGroup {
                    Text(teGroup.rawValue)
                        .font(.caption)
                        .foregroundStyle(teGroup.accentColor)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verb.dict).font(.system(size: 34, weight: .heavy)).foregroundStyle(accent)
                if let kanji = verb.kanji {
                    Text(kanji).font(.title2).foregroundStyle(.secondary)
                }
            }
            Text(verb.meaning).font(.headline).foregroundStyle(.secondary).italic()
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Examples", systemImage: "book", action: onExamples)
            Button("Test this verb", systemImage: "gamecontroller", action: onQuiz)
                .buttonStyle(.glassProminent)
                .tint(accent)
            Link(destination: jishoURL) {
                Label("Jisho", systemImage: "link")
            }
        }
        .buttonStyle(.glass)
    }

    private func notesBox(_ notes: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
            Text(notes).font(.footnote)
        }
        .padding(12)
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    private var formGroups: some View {
        VStack(alignment: .leading, spacing: 16) {
            FormGroupSection(title: "Polite", forms: [
                ("ます (polite +)", verb.forms.masuPos),
                ("ません (polite −)", verb.forms.masuNeg),
                ("ました (polite past +)", verb.forms.masuPast),
                ("ませんでした (polite past −)", verb.forms.masuPastNeg),
            ], defaultExpanded: true)

            FormGroupSection(title: "Plain", forms: [
                ("short (present +)", verb.forms.shortPos),
                ("short (present −)", verb.forms.shortNeg),
                ("short (past +)", verb.forms.shortPast),
                ("short (past −)", verb.forms.shortPastNeg),
            ], defaultExpanded: true)

            FormGroupSection(title: "て-form", forms: [
                ("て-form", verb.forms.te),
            ], defaultExpanded: true)

            if hasAdvancedForms {
                FormGroupSection(
                    title: "Advanced",
                    forms: [
                        ("Potential", verb.forms.potential),
                        ("Volitional", verb.forms.volitional),
                        ("Passive", verb.forms.passive),
                        ("Causative", verb.forms.causative),
                        ("Causative-passive", verb.forms.causativePassive),
                        ("Conditional (ば)", verb.forms.conditionalBa),
                        ("Conditional (たら)", verb.forms.conditionalTara),
                        ("Imperative", verb.forms.imperative),
                        ("たい (want to)", verb.forms.tai),
                    ].compactMap { label, value in value.map { (label, $0) } },
                    defaultExpanded: false
                )
            }
        }
    }
}
```

- [ ] **Step 7: Glass and immersive-fullscreen the quiz — modify `App/QuizQuestionView.swift`, `App/QuizResultsView.swift`, `App/QuizView.swift`**

Three targeted edits (not full-file replacements — these files are
otherwise unchanged from Task 15):

In `QuizQuestionView.swift`:
- `promptCard`'s `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))` → `.glassEffect(in: RoundedRectangle(cornerRadius: 20))`
- The "Next →"/"See Results →" button's `.buttonStyle(.borderedProminent)` → `.buttonStyle(.glassProminent)`
- `choiceButton`'s `.buttonStyle(.borderedProminent)` → `.buttonStyle(.glassProminent)` (keep the existing `.tint(background)` right after it)
- `feedback`'s body: replace
  ```swift
  .background(viewModel.timedOut ? Color.orange : (viewModel.selected == question.correct ? Color.green : Color.red))
  .foregroundStyle(.white)
  .clipShape(RoundedRectangle(cornerRadius: 12))
  ```
  with
  ```swift
  .foregroundStyle(.white)
  .glassEffect(
      .regular.tint(viewModel.timedOut ? .orange : (viewModel.selected == question.correct ? .green : .red)),
      in: RoundedRectangle(cornerRadius: 12)
  )
  ```

In `QuizResultsView.swift`:
- The results list's `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))` → `.glassEffect(in: RoundedRectangle(cornerRadius: 16))`
- "Back to Table"'s `.buttonStyle(.borderedProminent)` → `.buttonStyle(.glassProminent)`

In `QuizView.swift`, add to the end of the modifier chain on `body` (after
the existing `.task(id: viewModel.index) { ... }` block):
```swift
        // Immersive fullscreen takeover per spec section 10 — hides the
        // home indicator for the duration of the quiz.
        .persistentSystemOverlays(.hidden)
```

- [ ] **Step 8: Rebuild and verify**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" build 2>&1 | tail -15
```

Expected: `** BUILD SUCCEEDED **`. (macOS build is a pre-accepted, tracked
gap in this environment per Task 11 — skip it, iOS Simulator only.)

In Simulator: confirm each verb type (Irregular/Ru/U) shows a distinctly
colored type badge in both the list and detail screens, confirm the
て-form legend chips are each colored differently, confirm a verb's
dictionary-form heading in the detail view picks up its て-group's color
(or its type's color if it has no て-group, e.g. irregular verbs), confirm
the notes box / form-group tiles / action buttons read as glassy material
rather than flat gray fills, and confirm the quiz's prompt card/choice
buttons/feedback banner/results list are also glassy — with the home
indicator hidden while the quiz is on screen. Compare against
pre-Task-17 screenshots if you want a clear before/after.

- [ ] **Step 9: Commit**

```bash
git add App project.yml Packages/VerbKit/Package.swift
git commit -m "$(cat <<'EOF'
Add color-coding and Liquid Glass to existing screens

Restores the original web app's per-verb-type and per-て-form-group
color palette (simplified away during the initial port) via
VerbType.accentColor/TeGroup.accentColor, and moves custom-drawn
surfaces (badges, notes box, form tiles, action buttons, quiz UI)
from flat gray/.quaternary/.regularMaterial fills onto .glassEffect,
matching the Liquid Glass material standard SwiftUI chrome already
renders with for free. The quiz also gets a true immersive
fullscreen treatment (hidden home indicator). Also raises the
deployment target to iOS 26.0/macOS 26.0 (from 17.0/14.0), required
by the Liquid Glass APIs.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 18: Full verification pass

No new code — this confirms the whole app (all 17 prior tasks) actually
works together, including the offline/first-launch scenario that's hard
to exercise until now (it needs a truly fresh install). **Scope note:**
this session's tooling can drive the iOS Simulator interactively
(attach/tap/screenshot), but has no equivalent for driving a macOS app's
UI — macOS verification here is limited to build success, clean launch,
and console-log inspection; a full interactive click-through on macOS
needs the person running this plan to do it themselves on their Mac.

**Files:** none (verification only).

- [ ] **Step 1: Full clean rebuild**

```bash
rm -rf JPVerbConjugation.xcodeproj build DerivedData
cd Packages/VerbKit && rm -rf .build && swift test 2>&1 | tail -20
cd ../..
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" clean build 2>&1 | tail -20
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" clean build 2>&1 | tail -20
```

Expected: every `VerbKit` test passes; both `** BUILD SUCCEEDED **`.

- [ ] **Step 2: Fresh-install offline/first-launch scenario in Simulator**

```bash
xcrun simctl list devices available | grep iPhone | head -5
```

Pick a booted (or bootable) iPhone simulator's UDID for the following.

```bash
xcrun simctl uninstall <UDID> dev.martinloeseth.jpverbconjugation
xcrun simctl shutdown <UDID> || true
```

Using the iOS Simulator tool: boot that simulator, open its **Settings**
app, navigate to Wi-Fi, and turn it off (this is the most reliable way to
simulate offline in Simulator — `NWPathMonitor` inside the simulator
reflects it). Then install and launch the built `.app`, attach the live
panel, and screenshot.

Expected: the "No Internet Connection" screen (§ Task 11) appears, not a
crash or an infinite spinner.

Turn Wi-Fi back on in the Settings app. Expected: within a few seconds,
the app automatically transitions past the loading screen into the verb
list — this confirms `NetworkMonitor`'s reconnect callback (Task 9)
actually works end-to-end, not just in the mocked unit tests. Screenshot
to confirm.

If Task 10's push to GitHub was deferred, this step instead confirms the
"Can't Reach the Server" screen (offline first, then online-but-fetch-
fails) — still a valid pass; note that a real successful fetch is
unverified until the data is actually pushed.

- [ ] **Step 3: Full interactive walkthrough in Simulator**

With the app now past first launch, using the iOS Simulator tool's
`inspect`/`tap`/`screenshot` actions, verify each of the following in
turn (screenshot after each for the record):

1. Search field filters the list by dict/kanji/meaning/any conjugated
   form.
2. Type filter segmented control (All/Irregular/Ru-verbs/U-verbs) narrows
   the list correctly.
3. "Verb type guide" expands/collapses.
4. Selecting a verb shows its detail: description, notes (if present),
   Polite/Plain/て-form sections expanded, no Advanced section (no
   migrated verb has those fields populated yet).
5. "Examples" sheet lists that verb's example sentences; "Done" dismisses
   it.
6. "Jisho" opens `jisho.org` for that verb.
7. "Test this verb" quiz: countdown ticks, answering shows correct/
   incorrect feedback, "Next →" advances, final results screen shows
   score and per-question breakdown, "Back to Table" returns.
8. Letting the timer run out on a question shows "⏰ Time's up!" without
   crashing.
9. "Random Quiz" from the list toolbar quizzes across all verbs.
10. Settings: switching appearance to Dark changes the whole app
    immediately; changing the question count and terminating + relaunching
    the app (via the Simulator tool, not just backgrounding) confirms both
    persisted.
11. On a subsequent relaunch (data already cached), the app opens directly
    to the verb list with no loading screen — confirms the background
    silent-resync path (Task 9) instead of the first-launch path.

- [ ] **Step 4: macOS build/launch check**

```bash
open "$(xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -showBuildSettings 2>/dev/null | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR/{print $2; exit}')/JP Verb Conjugation.app"
sleep 3
log show --predicate 'process == "JP Verb Conjugation"' --last 1m 2>&1 | tail -40
```

Expected: the app launches without an immediate crash in the log; the
Dock shows it running. A full interactive click-through (search, quiz,
settings, ⌘, for Preferences) is for the person running this plan to do
themselves on their Mac — note in the final report that this was not
independently driven by this session's tooling.

- [ ] **Step 5: Report results**

Summarize, in plain terms: which of Steps 1-4 passed, any screenshots
taken, and any deviations from the spec noticed along the way (the two
already flagged — the two-target XcodeGen structure instead of one
multiplatform target, and the macOS quiz sheet instead of a separate
Window scene — plus the mid-implementation visual-direction addition in
Task 17, plus anything new). This closes out Plan 1; quiz history,
widgets/Shortcuts, and the content pipeline are separate plans per the
brainstorming decomposition.
