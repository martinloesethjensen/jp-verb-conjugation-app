# Home Screen Widgets and Romaji Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Search that understands romaji, and a configurable Home Screen / Lock Screen widget showing a verb, with a tap-through to the verb in the app.

**Architecture:** Pure, tested logic lives in VerbKit (`Romaji`, search fallbacks, `VerbPick`, `Route` URL parsing). The app gains a `verbtable://` URL scheme handled through the existing `Route` navigation and reloads widget timelines after a sync. A new `VerbTableWidgets` extension reads the App Group SwiftData store and renders three widget families from an App Intents configuration.

**Tech Stack:** Swift 5 mode, SwiftUI, WidgetKit, App Intents, SwiftData, XcodeGen, XCTest (match `VerbSearchTests.swift`).

**Spec:** `docs/superpowers/specs/2026-10-01-widgets-romaji-search-design.md`

## Global Constraints

- iOS 26 / macOS 26, Swift 5 language mode. Package tests: `swift test --package-path Packages/VerbKit` (258 tests pass today; all must stay green).
- Tests are XCTest (`import XCTest`, `@testable import VerbKit`), one `final class …Tests: XCTestCase` per file.
- Romaji: Hepburn and Nihon-shiki spellings; long vowels `ou`/`oo`/`ō` (macron `ō` = おう, `ā`/`ī`/`ū`/`ē` double the vowel); doubled consonants → っ; `n`, `nn` (before a non-vowel) and `n'` → ん; small kana via `x`/`l` prefix; case-insensitive; partial endings are dropped, not errors; text with no Latin letters is left untouched (converter returns nil). Katakana is out of scope.
- `matchesSearch` and `matchesGrammarSearch` keep every existing behaviour; romaji is a fallback tried in addition.
- Widget: one widget `VerbTableWidget`; modes Verb of the day (default), Random verb, Pick a verb; families `.systemSmall`, `.systemMedium`, `.accessoryRectangular`, `.accessoryInline`. Verb of the day changes at local midnight; Random changes every 3 hours; Pick never changes and falls back to the verb of the day if the verb no longer exists. Tap opens `verbtable://verb/<percent-encoded id>`.
- Empty store: widget text is exactly "Open Verb Table to load verbs".
- The widget never writes the store. App Group id `group.dev.martinloeseth.jpverbconjugation` (already in `App/JPVerbConjugation.entitlements`).
- Xcode schemes are `JPVerbConjugation_iOS` and `JPVerbConjugation_macOS`. Run `xcodegen generate` after adding files or changing `project.yml`. iOS build: `xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'id=4DB21AA8-1057-4014-A2C0-6D4968330CA5' build`. macOS build: add `-scheme JPVerbConjugation_macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- The Write/Edit tools are blocked for paths in the repo checkout in this environment; create and edit files with Bash.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

---

### Task 1: Romaji converter

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Search/Romaji.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/RomajiTests.swift`

**Interfaces:**
- Produces: `public enum Romaji { public static func toHiragana(_ text: String) -> String? }` — nil when the text has no Latin letter or nothing converts; otherwise the text with its romaji converted and non-Latin characters (kana, kanji, spaces) passed through.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import VerbKit

final class RomajiTests: XCTestCase {
    private func kana(_ text: String) -> String? { Romaji.toHiragana(text) }

    func testBasicWords() {
        XCTAssertEqual(kana("taberu"), "たべる")
        XCTAssertEqual(kana("tabemashita"), "たべました")
        XCTAssertEqual(kana("nomu"), "のむ")
        XCTAssertEqual(kana("ikimasu"), "いきます")
    }

    func testHepburnAndNihonShikiVariants() {
        XCTAssertEqual(kana("shi"), "し")
        XCTAssertEqual(kana("si"), "し")
        XCTAssertEqual(kana("chi"), "ち")
        XCTAssertEqual(kana("ti"), "ち")
        XCTAssertEqual(kana("tsu"), "つ")
        XCTAssertEqual(kana("tu"), "つ")
        XCTAssertEqual(kana("fu"), "ふ")
        XCTAssertEqual(kana("hu"), "ふ")
        XCTAssertEqual(kana("ja"), "じゃ")
        XCTAssertEqual(kana("zya"), "じゃ")
        XCTAssertEqual(kana("jya"), "じゃ")
        XCTAssertEqual(kana("sha"), "しゃ")
        XCTAssertEqual(kana("sya"), "しゃ")
        XCTAssertEqual(kana("cho"), "ちょ")
        XCTAssertEqual(kana("tyo"), "ちょ")
        XCTAssertEqual(kana("kyu"), "きゅ")
        XCTAssertEqual(kana("wo"), "を")
    }

    func testLongVowels() {
        XCTAssertEqual(kana("ou"), "おう")
        XCTAssertEqual(kana("oo"), "おお")
        XCTAssertEqual(kana("ō"), "おう")
        XCTAssertEqual(kana("kyō"), "きょう")
        XCTAssertEqual(kana("aa"), "ああ")
        XCTAssertEqual(kana("ī"), "いい")
    }

    func testDoubledConsonants() {
        XCTAssertEqual(kana("kka"), "っか")
        XCTAssertEqual(kana("kitte"), "きって")
        XCTAssertEqual(kana("zasshi"), "ざっし")
        XCTAssertEqual(kana("matchi"), "まっち")
        XCTAssertEqual(kana("ippai"), "いっぱい")
    }

    func testNRules() {
        XCTAssertEqual(kana("kan"), "かん")
        XCTAssertEqual(kana("kanji"), "かんじ")
        XCTAssertEqual(kana("kanna"), "かんな")
        XCTAssertEqual(kana("konnichiwa"), "こんにちわ")
        XCTAssertEqual(kana("kin'en"), "きんえん")
        XCTAssertEqual(kana("n'a"), "んあ")
        XCTAssertEqual(kana("na"), "な")
        XCTAssertEqual(kana("nya"), "にゃ")
        XCTAssertEqual(kana("shinbun"), "しんぶん")
        XCTAssertEqual(kana("annai"), "あんない")
        XCTAssertEqual(kana("onna"), "おんな")
    }

    func testSmallKana() {
        XCTAssertEqual(kana("xtu"), "っ")
        XCTAssertEqual(kana("ltu"), "っ")
        XCTAssertEqual(kana("xa"), "ぁ")
        XCTAssertEqual(kana("xya"), "ゃ")
    }

    func testCaseAndWhitespace() {
        XCTAssertEqual(kana("TaBeRu"), "たべる")
        XCTAssertEqual(kana("tabe ru"), "たべ る")
    }

    func testPartialEndingIsDropped() {
        XCTAssertEqual(kana("tab"), "た")
        XCTAssertEqual(kana("tabesh"), "たべ")
        XCTAssertEqual(kana("tabets"), "たべ")
        XCTAssertEqual(kana("tabeky"), "たべ")
    }

    func testMixedKanaAndLatinPassesKanaThrough() {
        XCTAssertEqual(kana("食beru"), "食べる")
        XCTAssertEqual(kana("たべru"), "たべる")
    }

    func testNilWhenNothingToConvert() {
        XCTAssertNil(kana(""))
        XCTAssertNil(kana("   "))
        XCTAssertNil(kana("たべる"))
        XCTAssertNil(kana("食べる"))
        XCTAssertNil(kana("k"))
        XCTAssertNil(kana("sh"))
    }

    func testNilForUnconvertibleLetters() {
        XCTAssertNil(kana("qux"))
        XCTAssertNil(kana("tabeqru"))
    }
}
```

- [ ] **Step 2: Run to confirm failure.** `swift test --package-path Packages/VerbKit --filter RomajiTests` — expect FAIL (`Romaji` undefined).

- [ ] **Step 3: Implement `Romaji.swift`**

```swift
import Foundation

/// Converts typed romaji to hiragana so Latin-letter queries can find Japanese text.
/// Accepts Hepburn and Nihon-shiki spellings. Text that is not romaji (kana, kanji,
/// spaces) passes through unchanged. A half-typed ending ("tab", "tabesh") is dropped
/// rather than rejected, so results narrow as the user types.
public enum Romaji {
    /// nil when the text has no Latin letter or nothing converts.
    public static func toHiragana(_ text: String) -> String? {
        let chars = Array(normalized(text))
        var output = ""
        var sawLatin = false
        var convertedAny = false
        var i = 0

        while i < chars.count {
            let c = chars[i]
            guard isLatinLetter(c) else {
                output.append(c)
                i += 1
                continue
            }
            sawLatin = true
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            if c == "n" {
                if next == nil {
                    output += "ん"; convertedAny = true; i += 1; continue
                }
                if next == "'" {
                    output += "ん"; convertedAny = true; i += 2; continue
                }
                if next == "n" {
                    let after: Character? = i + 2 < chars.count ? chars[i + 2] : nil
                    output += "ん"; convertedAny = true
                    if let after, isVowelOrY(after) { i += 1 } else { i += 2 }
                    continue
                }
                if let next, !isVowelOrY(next) {
                    output += "ん"; convertedAny = true; i += 1; continue
                }
            }

            if let next, next == c, !"aiueon".contains(c) {
                output += "っ"; convertedAny = true; i += 1; continue
            }
            if c == "t", i + 2 < chars.count, chars[i + 1] == "c", chars[i + 2] == "h" {
                output += "っ"; convertedAny = true; i += 1; continue
            }

            var matched = false
            var length = min(maxKeyLength, chars.count - i)
            while length >= 1 {
                if let kana = table[String(chars[i..<i + length])] {
                    output += kana; convertedAny = true; i += length; matched = true
                    break
                }
                length -= 1
            }
            if matched { continue }

            let rest = String(chars[i...])
            if table.keys.contains(where: { $0.hasPrefix(rest) }) { break }   // half-typed ending
            return nil
        }
        return sawLatin && convertedAny ? output : nil
    }

    private static func normalized(_ text: String) -> String {
        var result = text.lowercased()
        for (macron, plain) in [("ā", "aa"), ("ī", "ii"), ("ū", "uu"), ("ē", "ee"), ("ō", "ou")] {
            result = result.replacingOccurrences(of: macron, with: plain)
        }
        return result
    }

    private static func isLatinLetter(_ c: Character) -> Bool {
        c.isASCII && c.isLetter
    }

    private static func isVowelOrY(_ c: Character) -> Bool {
        "aiueoy".contains(c)
    }

    private static let maxKeyLength = 4

    /// romaji:kana pairs; one table for every accepted spelling.
    private static let table: [String: String] = {
        let spec = """
        a:あ i:い u:う e:え o:お
        ka:か ki:き ku:く ke:け ko:こ kya:きゃ kyu:きゅ kyo:きょ
        ga:が gi:ぎ gu:ぐ ge:げ go:ご gya:ぎゃ gyu:ぎゅ gyo:ぎょ
        sa:さ shi:し si:し su:す se:せ so:そ sha:しゃ shu:しゅ sho:しょ she:しぇ sya:しゃ syu:しゅ syo:しょ
        za:ざ ji:じ zi:じ zu:ず ze:ぜ zo:ぞ ja:じゃ ju:じゅ jo:じょ je:じぇ
        jya:じゃ jyu:じゅ jyo:じょ zya:じゃ zyu:じゅ zyo:じょ
        ta:た chi:ち ti:ち tsu:つ tu:つ te:て to:と cha:ちゃ chu:ちゅ cho:ちょ che:ちぇ
        tya:ちゃ tyu:ちゅ tyo:ちょ cya:ちゃ cyu:ちゅ cyo:ちょ
        da:だ di:ぢ du:づ dzu:づ de:で do:ど dya:ぢゃ dyu:ぢゅ dyo:ぢょ
        na:な ni:に nu:ぬ ne:ね no:の nya:にゃ nyu:にゅ nyo:にょ
        ha:は hi:ひ fu:ふ hu:ふ he:へ ho:ほ hya:ひゃ hyu:ひゅ hyo:ひょ fa:ふぁ fi:ふぃ fe:ふぇ fo:ふぉ
        ba:ば bi:び bu:ぶ be:べ bo:ぼ bya:びゃ byu:びゅ byo:びょ
        pa:ぱ pi:ぴ pu:ぷ pe:ぺ po:ぽ pya:ぴゃ pyu:ぴゅ pyo:ぴょ
        ma:ま mi:み mu:む me:め mo:も mya:みゃ myu:みゅ myo:みょ
        ya:や yu:ゆ yo:よ
        ra:ら ri:り ru:る re:れ ro:ろ rya:りゃ ryu:りゅ ryo:りょ
        wa:わ wo:を
        xa:ぁ xi:ぃ xu:ぅ xe:ぇ xo:ぉ la:ぁ li:ぃ lu:ぅ le:ぇ lo:ぉ
        xya:ゃ xyu:ゅ xyo:ょ lya:ゃ lyu:ゅ lyo:ょ
        xtu:っ ltu:っ xtsu:っ ltsu:っ
        """
        var result: [String: String] = [:]
        for pair in spec.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let parts = pair.split(separator: ":")
            result[String(parts[0])] = String(parts[1])
        }
        return result
    }()
}
```

- [ ] **Step 4: Run** `swift test --package-path Packages/VerbKit --filter RomajiTests` — expect PASS. Fix any test or table mistake you find (the tests are the spec); then run the whole package suite — all green.

- [ ] **Step 5: Commit** `git add Packages/VerbKit && git commit -m "Add the romaji to hiragana converter"`.

---

### Task 2: Romaji fallback in verb and grammar search

**Files:**
- Modify: `Packages/VerbKit/Sources/VerbKit/Search/VerbSearch.swift`, `Packages/VerbKit/Sources/VerbKit/Search/GrammarSearch.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/VerbSearchTests.swift` (append), `Packages/VerbKit/Tests/VerbKitTests/GrammarSearchTests.swift` (append), `Packages/VerbKit/Tests/VerbKitTests/RealRomajiSearchTests.swift` (create)

**Interfaces:**
- Consumes: `Romaji.toHiragana(_:)`.
- Produces: unchanged signatures `matchesSearch(_:query:)` and `matchesGrammarSearch(_:query:)`.

- [ ] **Step 1: Write the failing tests.** Append to `VerbSearchTests` (inside the class; it has the `taberu` fixture):

```swift
    func testMatchesRomajiDictionaryForm() {
        XCTAssertTrue(matchesSearch(taberu, query: "taberu"))
        XCTAssertTrue(matchesSearch(taberu, query: "TABERU"))
    }

    func testMatchesRomajiConjugatedForm() {
        XCTAssertTrue(matchesSearch(taberu, query: "tabemashita"))
        XCTAssertTrue(matchesSearch(taberu, query: "tabenakatta"))
    }

    func testMatchesPartialRomaji() {
        XCTAssertTrue(matchesSearch(taberu, query: "tab"))
        XCTAssertTrue(matchesSearch(taberu, query: "tabesh") == false)
    }

    func testRomajiNoMatch() {
        XCTAssertFalse(matchesSearch(taberu, query: "nomu"))
    }

    func testEnglishMeaningStillMatchesOnRawText() {
        XCTAssertTrue(matchesSearch(taberu, query: "eat"))
    }
```

(`"tabesh"` converts to たべ, which is a substring of たべる, so it matches; fix the assertion to `XCTAssertTrue(matchesSearch(taberu, query: "tabesh"))` — partial endings are dropped, so the match narrows to たべ.)

Append to `GrammarSearchTests`:

```swift
    func testMatchesRomajiTitle() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "ndesu"))
    }

    func testMatchesRomajiJapaneseExample() {
        XCTAssertTrue(matchesGrammarSearch(nDesu, query: "atama ga itai"))
    }

    func testRomajiNoMatchInGrammar() {
        XCTAssertFalse(matchesGrammarSearch(nDesu, query: "hazu"))
    }
```

Create `RealRomajiSearchTests.swift`:

```swift
import XCTest
@testable import VerbKit

final class RealRomajiSearchTests: XCTestCase {
    /// Dictionary form and polite form of each of the 25 verbs in data/verbs.json, in romaji.
    private let romaji: [String: (dict: String, polite: String)] = [
        "する": ("suru", "shimasu"), "くる": ("kuru", "kimasu"), "たべる": ("taberu", "tabemasu"),
        "みる": ("miru", "mimasu"), "ねる": ("neru", "nemasu"), "おきる": ("okiru", "okimasu"),
        "みせる": ("miseru", "misemasu"), "かりる": ("kariru", "karimasu"), "かう": ("kau", "kaimasu"),
        "あう": ("au", "aimasu"), "まつ": ("matsu", "machimasu"), "とる": ("toru", "torimasu"),
        "ある": ("aru", "arimasu"), "もつ": ("motsu", "mochimasu"), "よむ": ("yomu", "yomimasu"),
        "のむ": ("nomu", "nomimasu"), "あそぶ": ("asobu", "asobimasu"), "しぬ": ("shinu", "shinimasu"),
        "かく": ("kaku", "kakimasu"), "きく": ("kiku", "kikimasu"), "いく": ("iku", "ikimasu"),
        "いそぐ": ("isogu", "isogimasu"), "およぐ": ("oyogu", "oyogimasu"),
        "はなす": ("hanasu", "hanashimasu"), "かえす": ("kaesu", "kaeshimasu"),
    ]

    func testEveryRealVerbIsFoundByRomaji() throws {
        let verbs = try RealVerbs.load()
        XCTAssertEqual(verbs.count, romaji.count)
        for verb in verbs {
            let spelling = try XCTUnwrap(romaji[verb.dict], "no romaji for \(verb.dict)")
            XCTAssertTrue(matchesSearch(verb, query: spelling.dict), "\(spelling.dict) should find \(verb.dict)")
            XCTAssertTrue(matchesSearch(verb, query: spelling.polite), "\(spelling.polite) should find \(verb.dict)")
        }
    }
}
```

- [ ] **Step 2: Run** `swift test --package-path Packages/VerbKit --filter "VerbSearchTests|GrammarSearchTests|RealRomajiSearchTests"` — expect the new tests to FAIL.

- [ ] **Step 3: Implement.** In `VerbSearch.swift`, before the final `return false` of `matchesSearch`, add:

```swift
    if let kana = Romaji.toHiragana(trimmed) {
        if verb.dict.contains(kana) { return true }
        for key in FormKey.allCases where verb.forms[key].contains(kana) {
            return true
        }
    }
```

In `GrammarSearch.swift`, before the final `return false`:

```swift
    if let kana = Romaji.toHiragana(trimmed) {
        if point.title.contains(kana) { return true }
        for usage in point.usages {
            for example in usage.examples where example.jp.contains(kana) {
                return true
            }
        }
    }
```

Update the doc comment of `matchesGrammarSearch` to mention romaji.

- [ ] **Step 4: Run** the filtered tests (PASS), then the whole package suite (all green). If `atama ga itai` fails because the converter keeps the spaces ("あたま が いたい" does not appear in the Japanese text), strip whitespace from the converted text for the grammar check only: `let kana = converted.filter { !$0.isWhitespace }`, and mirror that in `matchesSearch`; keep the test.

- [ ] **Step 5: Commit** `git add Packages/VerbKit && git commit -m "Search verbs and grammar by romaji"`.

---

### Task 3: VerbPick and Route URLs

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Widget/VerbPick.swift`, `Packages/VerbKit/Sources/VerbKit/Navigation/Route+URL.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/VerbPickTests.swift`, `Packages/VerbKit/Tests/VerbKitTests/RouteURLTests.swift`

**Interfaces:**
- Produces:
  - `public enum VerbPick { static func verbOfTheDay(verbs: [Verb], on date: Date, calendar: Calendar = .current) -> Verb?; static func randomVerb(verbs: [Verb], using generator: inout some RandomNumberGenerator) -> Verb? }`
  - `Route.urlScheme: String` (`"verbtable"`), `Route.url: URL`, `Route.init?(url: URL)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import VerbKit

final class VerbPickTests: XCTestCase {
    private func verb(_ dict: String) -> Verb {
        Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: nil, meaning: "m", description: "d",
            forms: VerbForms(
                masuPos: "a", masuNeg: "b", masuPast: "c", masuPastNeg: "d",
                te: "e", shortPos: "f", shortNeg: "g", shortPast: "h", shortPastNeg: "i"
            ),
            examples: []
        )
    }

    private var verbs: [Verb] { ["a", "b", "c"].map(verb) }

    private func date(_ day: Int) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = day; components.hour = 15
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private let calendar = Calendar(identifier: .gregorian)

    func testSameDayGivesSameVerb() {
        var morning = DateComponents(); morning.year = 2026; morning.month = 10; morning.day = 5; morning.hour = 1
        var night = morning; night.hour = 23
        let a = VerbPick.verbOfTheDay(verbs: verbs, on: calendar.date(from: morning)!, calendar: calendar)
        let b = VerbPick.verbOfTheDay(verbs: verbs, on: calendar.date(from: night)!, calendar: calendar)
        XCTAssertEqual(a, b)
    }

    func testNextDayGivesNextVerbAndWraps() throws {
        let first = try XCTUnwrap(VerbPick.verbOfTheDay(verbs: verbs, on: date(1), calendar: calendar))
        let second = try XCTUnwrap(VerbPick.verbOfTheDay(verbs: verbs, on: date(2), calendar: calendar))
        let third = try XCTUnwrap(VerbPick.verbOfTheDay(verbs: verbs, on: date(3), calendar: calendar))
        let fourth = try XCTUnwrap(VerbPick.verbOfTheDay(verbs: verbs, on: date(4), calendar: calendar))
        XCTAssertEqual(Set([first.dict, second.dict, third.dict]).count, 3)
        XCTAssertEqual(fourth, first)
    }

    func testEmptyListGivesNil() {
        XCTAssertNil(VerbPick.verbOfTheDay(verbs: [], on: date(1), calendar: calendar))
        var generator = SystemRandomNumberGenerator()
        XCTAssertNil(VerbPick.randomVerb(verbs: [], using: &generator))
    }

    func testSingleVerbIsAlwaysChosen() {
        let only = [verb("x")]
        XCTAssertEqual(VerbPick.verbOfTheDay(verbs: only, on: date(9), calendar: calendar), only[0])
        var generator = SystemRandomNumberGenerator()
        XCTAssertEqual(VerbPick.randomVerb(verbs: only, using: &generator), only[0])
    }

    func testRandomVerbComesFromTheList() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let picked = VerbPick.randomVerb(verbs: verbs, using: &generator)
            XCTAssertNotNil(picked.flatMap { verbs.contains($0) ? $0 : nil })
        }
    }
}
```

```swift
import XCTest
@testable import VerbKit

final class RouteURLTests: XCTestCase {
    func testVerbRoundTrip() {
        let route = Route.verb("たべる")
        XCTAssertEqual(Route(url: route.url), route)
        XCTAssertEqual(route.url.scheme, "verbtable")
        XCTAssertEqual(route.url.host, "verb")
    }

    func testGrammarRoundTrip() {
        let route = Route.grammar("n-desu")
        XCTAssertEqual(Route(url: route.url), route)
    }

    func testIdWithSpaceAndSlashRoundTrips() {
        for id in ["to eat", "a/b", "100%"] {
            XCTAssertEqual(Route(url: Route.verb(id).url), .verb(id))
        }
    }

    func testParsesPercentEncodedLink() throws {
        let url = try XCTUnwrap(URL(string: "verbtable://verb/%E3%81%9F%E3%81%B9%E3%82%8B"))
        XCTAssertEqual(Route(url: url), .verb("たべる"))
    }

    func testRejectsOtherLinks() throws {
        for text in ["https://verb/たべる", "verbtable://other/x", "verbtable://verb", "verbtable://verb/", "verbtable:///x"] {
            let url = try XCTUnwrap(URL(string: text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text))
            XCTAssertNil(Route(url: url), text)
        }
    }
}
```

- [ ] **Step 2: Run** `swift test --package-path Packages/VerbKit --filter "VerbPickTests|RouteURLTests"` — expect FAIL.

- [ ] **Step 3: Implement**

```swift
// VerbPick.swift
import Foundation

/// Which verb a widget shows. Pure so it can be tested without WidgetKit.
public enum VerbPick {
    /// The same verb all day and on every device: the day's ordinal number in the era
    /// modulo the verb count, over the stored verb order.
    public static func verbOfTheDay(verbs: [Verb], on date: Date, calendar: Calendar = .current) -> Verb? {
        guard !verbs.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 1
        return verbs[(day - 1 + verbs.count) % verbs.count]
    }

    public static func randomVerb(verbs: [Verb], using generator: inout some RandomNumberGenerator) -> Verb? {
        verbs.randomElement(using: &generator)
    }
}
```

```swift
// Route+URL.swift
import Foundation

public extension Route {
    /// The custom URL scheme the app registers; widgets use it to open a verb.
    static let urlScheme = "verbtable"

    /// `verbtable://verb/<id>` or `verbtable://grammar/<id>`, with the id percent-encoded.
    var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        switch self {
        case let .verb(id):
            components.host = "verb"
            components.percentEncodedPath = "/" + Self.encode(id)
        case let .grammar(id):
            components.host = "grammar"
            components.percentEncodedPath = "/" + Self.encode(id)
        }
        return components.url!
    }

    /// nil for anything that is not one of this app's links.
    init?(url: URL) {
        guard url.scheme == Self.urlScheme, let host = url.host else { return nil }
        let path = url.path   // already percent-decoded
        guard path.hasPrefix("/"), path.count > 1 else { return nil }
        let id = String(path.dropFirst())
        switch host {
        case "verb": self = .verb(id)
        case "grammar": self = .grammar(id)
        default: return nil
        }
    }

    private static func encode(_ id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }
}
```

(The path `a/b` is encoded as `a%2Fb`; `URL.path` decodes `%2F` back to `/`. If a test shows otherwise on this SDK, parse `url.absoluteString` by hand instead and keep the tests.)

- [ ] **Step 4: Run** the filtered tests (PASS), then the whole suite (green). In `RouteURLTests.testRejectsOtherLinks`, fix any test URL that is invalid on construction rather than weakening the rejection assertions.

- [ ] **Step 5: Commit** `git add Packages/VerbKit && git commit -m "Add VerbPick and verbtable:// route URLs"`.

---

### Task 4: App support — URL scheme, deep-link handling, widget reload

**Files:**
- Modify: `project.yml` (URL scheme only), `App/RootView.swift`, `App/MainTabView.swift`, `App/JPVerbConjugationApp.swift`

**Interfaces:**
- Consumes: `Route(url:)`, existing `MainTabView.open(_:)`.
- Produces: the app opens `verbtable://…` links; `WidgetCenter.shared.reloadAllTimelines()` runs after the verb store starts (the widget target itself comes in Task 5).

- [ ] **Step 1: URL scheme.** In `project.yml`, under the app target's `info.properties`, add:

```yaml
        CFBundleURLTypes:
          - CFBundleURLName: dev.martinloeseth.jpverbconjugation
            CFBundleURLSchemes:
              - verbtable
```

- [ ] **Step 2: Incoming route.** `RootView`: add `@State private var incomingRoute: Route?`; pass it to `MainTabView(verbSelection: $selection, incomingRoute: $incomingRoute) { verbsTab }`; and add on the outer `Group`:

```swift
        .onOpenURL { url in
            if let route = Route(url: url) { incomingRoute = route }
        }
```

`MainTabView`: add `@Binding var incomingRoute: Route?` (and the init parameter `incomingRoute: Binding<Route?>`), and after `.environment(\.openRoute, …)` add:

```swift
        .onChange(of: incomingRoute, initial: true) { _, route in
            guard let route else { return }
            open(route)
            incomingRoute = nil
        }
```

(`initial: true` covers a cold launch from a widget tap: the link arrives before the tabs exist, and the route is waiting when they appear. If the verb data has not loaded yet, `open` does nothing, so also keep the route until the store has data: `guard let route, verbStore.hasLocalData else { return }` and add `.onChange(of: verbStore.verbs.count) { … }` that retries — implement the retry only if `hasLocalData` is not already true when `MainTabView` first appears; `RootView` only shows `MainTabView` when `hasLocalData` is true, so the simple form above is enough. Say in the report which you verified.)

- [ ] **Step 3: Reload after sync.** `JPVerbConjugationApp`: `import WidgetKit`; after `await verbStore.start()` in the first `.task` add `WidgetCenter.shared.reloadAllTimelines()`.

- [ ] **Step 4: Build.** `xcodegen generate`, then the iOS build, then the macOS build (Global Constraints). Expect success. Then verify the link on the simulator: build and install the app, `xcrun simctl openurl 4DB21AA8-1057-4014-A2C0-6D4968330CA5 'verbtable://verb/%E3%81%9F%E3%81%B9%E3%82%8B'` and confirm (screenshot) the たべる verb page opens; repeat once with the app fully terminated first (cold start), and once with an unknown id (nothing happens, no crash).

- [ ] **Step 5: Commit** `git add project.yml App && git commit -m "Open verbtable:// links in the app and reload widgets after sync"`.

---

### Task 5: The widget extension

**Files:**
- Create: `Widgets/VerbTableWidgets.swift` (bundle, `@main`), `Widgets/VerbWidget.swift` (widget, provider, entry), `Widgets/VerbWidgetIntent.swift` (intent, mode enum, verb entity), `Widgets/VerbWidgetViews.swift`, `Widgets/VerbTableWidgets.entitlements`, `Widgets/Info.plist` is generated by XcodeGen (do not hand-write it)
- Modify: `project.yml`

**Interfaces:**
- Consumes: `VerbPick`, `Route.url`, `VerbModelContainer.make()`, `SwiftDataVerbPersisting.loadAllVerbs()`, `Verb`, `VerbForms`, `Verb.jishoQuery`, and `App/VerbColors.swift` (shared into the extension target for `VerbType.accentColor` and `accentPill`).
- Produces: the `VerbTableWidget` widget (kind `"VerbTableWidget"`).

- [ ] **Step 1: Target in `project.yml`.** Add a second target (adapt to what XcodeGen accepts; run `xcodegen generate` to check):

```yaml
  VerbTableWidgets:
    type: app-extension
    platform: [iOS, macOS]
    deploymentTarget:
      iOS: "26.0"
      macOS: "26.0"
    sources:
      - path: Widgets
      - path: App/VerbColors.swift
    dependencies:
      - package: VerbKit
      - sdk: SwiftUI.framework
      - sdk: WidgetKit.framework
    info:
      path: Widgets/Info.plist
      properties:
        CFBundleDisplayName: "Verb Table"
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.martinloeseth.jpverbconjugation.widgets
        PRODUCT_NAME: "VerbTableWidgets"
        SWIFT_VERSION: "5.0"
        CODE_SIGN_STYLE: Automatic
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_ENTITLEMENTS: Widgets/VerbTableWidgets.entitlements
        DEVELOPMENT_TEAM: "PUMQYPZ9HK"
```

and add to the app target's `dependencies`: `- target: VerbTableWidgets` with `embed: true`. Copy the App Group entitlement from `App/JPVerbConjugation.entitlements` into `Widgets/VerbTableWidgets.entitlements`. The app and the widget must keep the same `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (add a comment in `project.yml` noting both change together). If XcodeGen cannot embed a multi-platform extension this way, use the documented alternative (`dependencies: - target: VerbTableWidgets_${platform}` style or per-platform entries) and describe it in the report.

- [ ] **Step 2: Intent and entity** (`VerbWidgetIntent.swift`; API sketches, adjust to compile on the iOS 26 SDK):

```swift
import AppIntents
import VerbKit
import WidgetKit

enum VerbWidgetMode: String, AppEnum {
    case verbOfTheDay, random, pick

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
    static var caseDisplayRepresentations: [VerbWidgetMode: DisplayRepresentation] = [
        .verbOfTheDay: "Verb of the day",
        .random: "Random verb",
        .pick: "Pick a verb",
    ]
}

struct VerbChoice: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Verb"
    static var defaultQuery = VerbChoiceQuery()

    var id: String   // Verb.id (the dictionary form)
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct VerbChoiceQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [VerbChoice] {
        let all = await VerbLoader.verbs()
        return all.filter { identifiers.contains($0.id) }.map(VerbChoice.init)
    }
    func suggestedEntities() async throws -> [VerbChoice] {
        await VerbLoader.verbs().map(VerbChoice.init)
    }
    func entities(matching string: String) async throws -> [VerbChoice] {
        await VerbLoader.verbs().filter { matchesSearch($0, query: string) }.map(VerbChoice.init)
    }
}

extension VerbChoice {
    init(_ verb: Verb) {
        self.init(id: verb.id, title: verb.kanji.map { "\(verb.dict) (\($0))" } ?? verb.dict)
    }
}

struct VerbWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Verb"
    static var description = IntentDescription("Choose which verb the widget shows.")

    @Parameter(title: "Show", default: .verbOfTheDay)
    var mode: VerbWidgetMode

    @Parameter(title: "Verb")
    var verb: VerbChoice?

    static var parameterSummary: some ParameterSummary {
        When(\.$mode, .equalTo, VerbWidgetMode.pick) {
            Summary("\(\.$mode) \(\.$verb)")
        } otherwise: {
            Summary("\(\.$mode)")
        }
    }
}
```

(`matchesSearch` gives the picker romaji search for free.)

- [ ] **Step 3: Provider and entry** (`VerbWidget.swift`):

```swift
import SwiftData
import SwiftUI
import VerbKit
import WidgetKit

/// Reads the shared store; the widget never writes it.
@MainActor
enum VerbLoader {
    static func verbs() -> [Verb] {
        guard let container = try? VerbModelContainer.make() else { return [] }
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(container))
        return (try? persisting.loadAllVerbs()) ?? []
    }
}

struct VerbEntry: TimelineEntry {
    let date: Date
    /// nil while the app has not downloaded any verbs yet.
    let verb: Verb?
}

struct VerbProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VerbEntry {
        VerbEntry(date: .now, verb: nil)
    }

    func snapshot(for configuration: VerbWidgetIntent, in context: Context) async -> VerbEntry {
        VerbEntry(date: .now, verb: await choose(for: configuration, at: .now))
    }

    func timeline(for configuration: VerbWidgetIntent, in context: Context) async -> Timeline<VerbEntry> {
        let now = Date()
        let entry = VerbEntry(date: now, verb: await choose(for: configuration, at: now))
        let calendar = Calendar.current
        switch configuration.mode {
        case .verbOfTheDay:
            let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
            return Timeline(entries: [entry], policy: .after(midnight))
        case .random:
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(3 * 3600)))
        case .pick:
            return Timeline(entries: [entry], policy: .never)
        }
    }

    @MainActor
    private func choose(for configuration: VerbWidgetIntent, at date: Date) -> Verb? {
        let verbs = VerbLoader.verbs()
        switch configuration.mode {
        case .verbOfTheDay:
            return VerbPick.verbOfTheDay(verbs: verbs, on: date)
        case .random:
            var generator = SystemRandomNumberGenerator()
            return VerbPick.randomVerb(verbs: verbs, using: &generator)
        case .pick:
            if let id = configuration.verb?.id, let verb = verbs.first(where: { $0.id == id }) {
                return verb
            }
            return VerbPick.verbOfTheDay(verbs: verbs, on: date)
        }
    }
}

struct VerbTableWidget: Widget {
    let kind = "VerbTableWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: VerbWidgetIntent.self, provider: VerbProvider()) { entry in
            VerbWidgetView(entry: entry)
        }
        .configurationDisplayName("Verb Table")
        .description("A verb and its key forms, from your Home or Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
```

```swift
// VerbTableWidgets.swift
import SwiftUI
import WidgetKit

@main
struct VerbTableWidgets: WidgetBundle {
    var body: some Widget {
        VerbTableWidget()
    }
}
```

- [ ] **Step 4: Views** (`VerbWidgetViews.swift`). `VerbWidgetView` reads `@Environment(\.widgetFamily)` and switches:
  - **No verb** (`entry.verb == nil`): `Text("Open Verb Table to load verbs")`, `.font(.caption)`, multiline, centred, in every family (inline: the same text in one line).
  - **`.systemSmall`:** the headline (`verb.kanji ?? verb.dict`, `.title`, heavy, accent colour from `(verb.teGroup?.accentColor ?? verb.type.accentColor)`), the reading (`verb.dict`) when a kanji headline is shown, `verb.meaning` (`.caption`, secondary, 2 lines), and the polite form `verb.forms.masuPos` (`.callout`).
  - **`.systemMedium`:** the small layout on the left; on the right a 2×2 grid of labelled forms: て-form `forms.te`, past `forms.shortPast`, negative `forms.shortNeg`, potential `forms.potential` (omit the cell when nil, e.g. ある).
  - **`.accessoryRectangular`:** three lines — `verb.kanji ?? verb.dict` (headline), `verb.meaning`, `verb.forms.masuPos`.
  - **`.accessoryInline`:** one line `"\(verb.dict) · \(verb.meaning)"`.
  - Every non-empty layout carries `.widgetURL(Route.verb(verb.id).url)` and, for the Home Screen families, `.containerBackground(for: .widget) { … }` using a dark navy-to-black gradient consistent with the app icon (`Color(red: 0.043, green: 0.063, blue: 0.149)`), with white text; accessory families use `.containerBackground(.clear, for: .widget)`.
  - Add `#Preview(as: .systemSmall)`, `.systemMedium`, `.accessoryRectangular` using sample verbs built in the preview file.

- [ ] **Step 5: Build** `xcodegen generate`, iOS build, macOS build (Global Constraints). Both must succeed. Fix API mismatches in the intent and provider sketches minimally and describe them in the report.

- [ ] **Step 6: Verify on the simulator** (iPhone 17 Pro, id above). Install the app (so the store has data: launch it once and let verbs load), go to the Home Screen, add the Verb Table widget in small and medium via the widget gallery (long-press the Home Screen, +), check: verb of the day shows, the edit screen offers the three modes and shows the verb picker only for Pick a verb, Pick a verb changes the widget, tapping the widget opens that verb in the app. Also check the Lock Screen is not required on the simulator. If adding a widget through the UI is not feasible, say exactly what you could not check. Screenshots lag taps by a second or two.

- [ ] **Step 7: Commit** `git add project.yml Widgets && git commit -m "Add the Verb Table widget"`.
