# Text Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A long-press (right-click) menu on forms (Copy, Open in Jisho) and on example sentences (Copy, Open in Jisho, and a Translate submenu with Apple Translate, DeepL and Google Translate), acting on each item's exact Japanese text.

**Architecture:** A pure `TextLookupURL` in `VerbKit` builds the Jisho, DeepL and Google links from a string. One app view modifier, `.textActions(_:translate:)`, attaches a `contextMenu` (Copy through a small `Clipboard` helper, `openURL` for the web links, and `.translationPresentation` for Apple Translate). It is attached to `FormCell` (so every table on every page gets it), to `ExampleRow` and to the Examples sheet rows. No data, script or model change.

**Tech Stack:** Swift 5 language mode on Xcode 27 (SwiftPM tools 6.2), SwiftUI with Liquid Glass, the system Translation framework, XCTest; XcodeGen 2.46.

**Spec:** [docs/superpowers/specs/2026-10-01-text-actions-design.md](../specs/2026-10-01-text-actions-design.md), which builds on the verb page redesign, the lesson example rows, the furigana design and the [native rewrite spec](../specs/2026-09-23-native-apple-rewrite-design.md) (read its section 10, the visual design direction).

**Verified against:** `main` at `eb3f534` plus the spec commits on `feature/text-actions`. Every task below was executed on a scratch branch (one commit per task) with all tests passing, both app targets building, and the app run in the iOS Simulator on iPhone: the menu on a form cell, **Open in Jisho** opening Safari on the right word (たべます), the menu on a lesson example sentence with its Translate submenu (Apple Translate, DeepL, Google Translate), and Apple's translation sheet opening (with its own consent screen). **Not exercised: Copy then paste, the DeepL and Google pages, the Examples sheet, and iPad and macOS.** The test count per task comes from those runs. **If `main` has moved, run Task 0 Step 2 first.**

## Global Constraints

- Deployment target: **iOS 26 / macOS 26**, Swift language mode 5. Do not lower it.
- **Patch existing files; never replace them wholesale.** Modified files are given as diffs against `eb3f534`; new files are given in full. Apply diffs with `git apply --3way`, or make the equivalent edit by hand if the surrounding code has moved.
- App-only change: `data/`, `scripts/`, the lessons, the quiz and the model are **not** touched.
- **Actions act on whole items, never partial selection** (spec §1): a form uses the whole form string (たべられます, not the highlighted ending) and a sentence uses `example.jp`, always without furigana.
- **Menu content (spec §1):** forms get **Copy** and **Open in Jisho**; example sentences get **Copy**, **Open in Jisho** and a **Translate** submenu with **Apple Translate**, **DeepL** and **Google Translate** (Japanese to English). Nothing leaves the app until an item is chosen; the app itself sends nothing. Apple's sheet shows its own consent screen.
- **URL format (spec §2), pinned by tests:** Jisho `https://jisho.org/search/<text>`; DeepL `https://www.deepl.com/translator#ja/en/<text>`; Google `https://translate.google.com/?sl=ja&tl=en&text=<text>&op=translate`. The text is trimmed, then percent-encoded as UTF-8 with only the RFC 3986 unreserved characters (`A-Z a-z 0-9 - . _ ~`) left as they are. Blank text has no URL.
- A tap on a lesson example row still reveals the English; the context menu must not break that. Visual direction (rewrite spec §10): standard menus and controls, **no accessibility-specific modifiers**.
- Out of scope: selecting part of a sentence, menus on lesson headings, the verb header or English paragraphs, a preferred-service setting, translating English to Japanese, lookup history (spec, "Not in this sub-project").
- Any `git push` to the GitHub remote requires explicit user confirmation at execution time. Do not push without asking first.

---

## Task 0: Baseline

**Files:** none.

- [ ] **Step 1: Start from the spec branch and record the baseline**

```bash
git worktree add -b feature/text-actions-impl .claude/worktrees/text-actions-impl feature/text-actions
cd .claude/worktrees/text-actions-impl
git log -1 --format=%h
(cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1)
python3 scripts/update_data.py --check
```

Expected: a short hash, `Executed 207 tests, with 0 failures`, and `data is up to date`. Every count below is relative to these. (If `feature/text-actions` has already been merged or deleted, branch from `main` instead.) Run these from the main repository root so the worktree is not nested inside another one.

- [ ] **Step 2: If `main` is newer than `eb3f534`, see what it touched**

```bash
git diff --name-only eb3f534 main -- . ':!docs' ':!*.png' | cat
```

Expected: nothing. If files appear and any is one this plan modifies (`FormCell.swift`, `ExampleRow.swift`, `ExamplesView.swift`, `VerbDetailView.swift`), read that diff before applying the matching diff below and adapt instead of overwriting.

---

## Task 1: `TextLookupURL`

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Lookup/TextLookupURL.swift`
- Test: `Packages/VerbKit/Tests/VerbKitTests/TextLookupURLTests.swift`

**Interfaces:**
- Produces: `TextLookupURL.jisho(_:)`, `.deepL(_:)` and `.google(_:)`, each `(String) -> URL?` (`nil` for blank text). Used by Task 2.

- [ ] **Step 1: Write the failing test**

`Packages/VerbKit/Tests/VerbKitTests/TextLookupURLTests.swift`. It pins the exact URL of each service, the encoding of kanji, kana and Japanese punctuation, the escaping of characters that could change a URL's shape (`/ ? # % & space =`), a round trip through `URLComponents` and back, blank input, and trimming:

```swift
import XCTest
@testable import VerbKit

final class TextLookupURLTests: XCTestCase {
    private let taberu = "%E9%A3%9F%E3%81%B9%E3%82%8B" // 食べる

    func testJishoSearchesTheEncodedText() {
        XCTAssertEqual(TextLookupURL.jisho("食べる")?.absoluteString, "https://jisho.org/search/" + taberu)
    }

    func testDeepLPutsTheEncodedTextInTheFragment() {
        XCTAssertEqual(
            TextLookupURL.deepL("食べる")?.absoluteString,
            "https://www.deepl.com/translator#ja/en/" + taberu
        )
    }

    func testGoogleUsesTheQueryString() {
        XCTAssertEqual(
            TextLookupURL.google("食べる")?.absoluteString,
            "https://translate.google.com/?sl=ja&tl=en&text=" + taberu + "&op=translate"
        )
    }

    func testKanaAndJapanesePunctuationAreEncoded() {
        let url = TextLookupURL.jisho("どうしたんですか。")
        XCTAssertEqual(
            url?.absoluteString,
            "https://jisho.org/search/%E3%81%A9%E3%81%86%E3%81%97%E3%81%9F%E3%82%93%E3%81%A7%E3%81%99%E3%81%8B%E3%80%82"
        )
    }

    func testCharactersThatCouldChangeTheShapeOfTheURLAreEscaped() {
        let text = "a/b?c#d%e&f g=h"
        for url in [TextLookupURL.jisho(text), TextLookupURL.deepL(text), TextLookupURL.google(text)] {
            let string = url?.absoluteString ?? ""
            XCTAssertTrue(string.contains("a%2Fb%3Fc%23d%25e%26f%20g%3Dh"), string)
        }
    }

    func testUnreservedAsciiIsLeftAlone() {
        XCTAssertEqual(TextLookupURL.jisho("Ab-1._~")?.absoluteString, "https://jisho.org/search/Ab-1._~")
    }

    func testTheTextRoundTripsThroughTheURL() throws {
        let sentence = "この曲は無料で聞けます。 / 100%？"
        let google = try XCTUnwrap(TextLookupURL.google(sentence))
        let components = try XCTUnwrap(URLComponents(url: google, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "text" }?.value, sentence)
        let jisho = try XCTUnwrap(TextLookupURL.jisho(sentence))
        let prefix = "https://jisho.org/search/"
        XCTAssertEqual(String(jisho.absoluteString.dropFirst(prefix.count)).removingPercentEncoding, sentence)
    }

    func testBlankTextHasNoURL() {
        for text in ["", "   ", "\n\t "] {
            XCTAssertNil(TextLookupURL.jisho(text))
            XCTAssertNil(TextLookupURL.deepL(text))
            XCTAssertNil(TextLookupURL.google(text))
        }
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(TextLookupURL.jisho("  食べる \n")?.absoluteString, "https://jisho.org/search/" + taberu)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd Packages/VerbKit && swift test --filter TextLookupURLTests 2>&1 | grep -E "error:" | head -2
```

Expected: `cannot find 'TextLookupURL' in scope`.

- [ ] **Step 3: Implement**

`Packages/VerbKit/Sources/VerbKit/Lookup/TextLookupURL.swift`:

```swift
import Foundation

/// Web links for looking up or translating a piece of Japanese text. Every function
/// returns `nil` for blank text. The text is percent-encoded as UTF-8 with only
/// the RFC 3986 unreserved characters left as they are, so `/`, `?`, `#`, `&`, `%`
/// and spaces inside it can never change the shape of the URL.
public enum TextLookupURL {
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func encoded(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.addingPercentEncoding(withAllowedCharacters: unreserved)
    }

    /// A Jisho search for `text`.
    public static func jisho(_ text: String) -> URL? {
        encoded(text).flatMap { URL(string: "https://jisho.org/search/" + $0) }
    }

    /// DeepL's translator, Japanese to English. The text rides in the fragment.
    public static func deepL(_ text: String) -> URL? {
        encoded(text).flatMap { URL(string: "https://www.deepl.com/translator#ja/en/" + $0) }
    }

    /// Google Translate, Japanese to English.
    public static func google(_ text: String) -> URL? {
        encoded(text).flatMap {
            URL(string: "https://translate.google.com/?sl=ja&tl=en&text=" + $0 + "&op=translate")
        }
    }
}
```

- [ ] **Step 4: Run the whole suite to verify it passes**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
```

Expected: `Executed 216 tests, with 0 failures` (207 baseline plus 9 new).

- [ ] **Step 5: Commit**

```bash
git add Packages/VerbKit
git commit -m "$(cat <<'EOF'
Add TextLookupURL: Jisho, DeepL and Google links for a piece of text

The text is trimmed and percent-encoded with only the unreserved characters
left alone, so a slash, question mark, hash or percent sign in a sentence can
never change the shape of the URL. Blank text has no URL.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: The menu, on every form

**Files:**
- Create: `App/Clipboard.swift`, `App/TextActions.swift`
- Modify: `App/FormCell.swift`, `App/VerbDetailView.swift`

**Interfaces:**
- Consumes: `TextLookupURL` (Task 1).
- Produces: `Clipboard.copy(_:)`; `View.textActions(_ text: String, translate: Bool = false)` (a `contextMenu` with Copy, Open in Jisho and, when `translate` is true, a Translate submenu with Apple Translate, DeepL and Google Translate). `FormCell` uses it, so every form in every table gets Copy and Open in Jisho. The verb page's Jisho button now builds its URL with `TextLookupURL.jisho`. Used by Task 3.

- [ ] **Step 1: Create the clipboard helper and the modifier**

`App/Clipboard.swift`, over `UIPasteboard` on iOS and `NSPasteboard` on macOS:

```swift
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Puts a string on the system clipboard.
enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
```

`App/TextActions.swift`. The `@State` that drives `.translationPresentation` lives in the modifier, so the sheet attaches outside the menu; DeepL and Google go through `openURL`:

```swift
import SwiftUI
import Translation
import VerbKit

/// A long-press (right-click) menu that acts on one piece of Japanese text:
/// Copy and Open in Jisho, and, for sentences, a Translate submenu with Apple
/// Translate, DeepL and Google Translate. The actions always use `text` exactly
/// as given, so they work the same with furigana on or off. Nothing leaves the
/// app until an item is chosen.
private struct TextActions: ViewModifier {
    let text: String
    let translate: Bool
    @Environment(\.openURL) private var openURL
    @State private var showingAppleTranslation = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") {
                    Clipboard.copy(text)
                }
                if let url = TextLookupURL.jisho(text) {
                    Button("Open in Jisho", systemImage: "book") {
                        openURL(url)
                    }
                }
                if translate {
                    Menu("Translate", systemImage: "translate") {
                        Button("Apple Translate") {
                            showingAppleTranslation = true
                        }
                        if let url = TextLookupURL.deepL(text) {
                            Button("DeepL") { openURL(url) }
                        }
                        if let url = TextLookupURL.google(text) {
                            Button("Google Translate") { openURL(url) }
                        }
                    }
                }
            }
            .translationPresentation(isPresented: $showingAppleTranslation, text: text)
    }
}

extension View {
    /// Adds the text-actions menu for `text`; `translate` adds the Translate
    /// submenu (for sentences).
    func textActions(_ text: String, translate: Bool = false) -> some View {
        modifier(TextActions(text: text, translate: translate))
    }
}
```

- [ ] **Step 2: Attach it to form cells, and share the Jisho encoder**

Apply these diffs. `FormCell` gets a rectangular content shape (so the small cell is easy to long-press) and `.textActions(form)`; the verb page's Jisho link now uses the one encoder:

```diff
diff --git a/App/FormCell.swift b/App/FormCell.swift
index 6d40164..75234ac 100644
--- a/App/FormCell.swift
+++ b/App/FormCell.swift
@@ -19,5 +19,7 @@ struct FormCell: View {
         }
         .lineLimit(1)
         .minimumScaleFactor(0.7)
+        .contentShape(Rectangle())
+        .textActions(form)
     }
 }
```

```diff
diff --git a/App/VerbDetailView.swift b/App/VerbDetailView.swift
index fbca125..befd7b7 100644
--- a/App/VerbDetailView.swift
+++ b/App/VerbDetailView.swift
@@ -11,8 +11,7 @@ struct VerbDetailView: View {
     }
 
     private var jishoURL: URL {
-        let encoded = verb.dict.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verb.dict
-        return URL(string: "https://jisho.org/search/\(encoded)")!
+        TextLookupURL.jisho(verb.dict)!
     }
 
     var body: some View {
```

- [ ] **Step 3: Build both platforms**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 4: Try it in the iOS Simulator**

The app reads its data from GitHub `main`, which already has everything this needs. **Use a unique bundle id**, so your install and its saved sync state cannot collide with another session's build of the same app (a collision shows up as a bogus "Something Went Wrong" screen):

```bash
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" -derivedDataPath /tmp/tacheck CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=dev.martinloeseth.jpverbconjugation.tacheck build 2>&1 | tail -3
xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation.tacheck
```

Then install and launch `/tmp/tacheck/Build/Products/Debug-iphonesimulator/JP Verb Conjugation.app` with the iOS Simulator tool, passing that bundle id. Uninstall between runs (the same command as above): with no App Group the store is in memory but sync state persists, so a relaunch would report "up to date" with no data. A long-press is a tap held for about a second; the page scrolls and re-lays out after taps, so take a fresh screenshot before each press.

Expected, on **Verbs → たべる**: long-pressing a form cell (for example たべます in the Polite column) lifts it and shows a menu with **Copy** and **Open in Jisho** (no Translate). Choosing **Open in Jisho** switches to Safari on a jisho.org search for たべます. Long-pressing a form on **Potential**, **んです** and **Auxiliaries** pages works the same. A long-press on a column header or a row caption shows no menu. Also check **Copy**: long-press a form, choose Copy, then paste into any text field and confirm the whole form appears.

- [ ] **Step 5: Clean up and commit**

```bash
xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation.tacheck
git status --short                       # only the App/ files of this task
git add App
git commit -m "$(cat <<'EOF'
Add a long-press menu to every form

Copy and Open in Jisho on each form cell, from one view modifier that also
carries the Translate submenu the example sentences will use next. The verb
page's own Jisho button now builds its link with the same encoder.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: The menu, with Translate, on example sentences

**Files:**
- Modify: `App/ExampleRow.swift`, `App/ExamplesView.swift`

**Interfaces:**
- Consumes: `View.textActions(_:translate:)` (Task 2).

- [ ] **Step 1: Attach the menu to the sentences**

Apply these diffs. `ExampleRow` keeps its tap-to-reveal `Button`; a context menu on a button leaves the tap alone. The Examples sheet rows get a content shape so the whole row responds:

```diff
diff --git a/App/ExampleRow.swift b/App/ExampleRow.swift
index 1645fea..8b10a57 100644
--- a/App/ExampleRow.swift
+++ b/App/ExampleRow.swift
@@ -24,5 +24,6 @@ struct ExampleRow: View {
             .contentShape(Rectangle())
         }
         .buttonStyle(.plain)
+        .textActions(example.jp, translate: true)
     }
 }
```

```diff
diff --git a/App/ExamplesView.swift b/App/ExamplesView.swift
index 302eda5..ef9003e 100644
--- a/App/ExamplesView.swift
+++ b/App/ExamplesView.swift
@@ -20,6 +20,8 @@ struct ExamplesView: View {
                         .foregroundStyle(.secondary)
                 }
                 .padding(.vertical, 4)
+                .contentShape(Rectangle())
+                .textActions(example.jp, translate: true)
             }
             .navigationTitle("\(verb.dict) — Examples")
             .toolbar {
```

- [ ] **Step 2: Build both platforms and run the tests**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
(cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1)
```

Expected: `** BUILD SUCCEEDED **` twice and `Executed 216 tests, with 0 failures`.

- [ ] **Step 3: Try it in the iOS Simulator**

Build and launch as in Task 2 Step 4 (unique bundle id `…tacheck`, uninstall between runs; take a fresh screenshot before each press). Expected:
- **Grammar → んです**, scroll to "1. Asking for or giving a reason": long-pressing the first example sentence lifts the row and shows **Copy**, **Open in Jisho** and **Translate ›**. Opening **Translate** lists **Apple Translate**, **DeepL** and **Google Translate**.
- **Apple Translate** opens a sheet from the bottom with Apple's own consent screen ("The selected content will be sent to Apple…") and a **Continue** button. (You do not need to continue; close it with the ✕.)
- **DeepL** and **Google Translate** open a page (the app if installed, otherwise the website) with the Japanese sentence filled in, Japanese to English.
- A plain **tap** on the same row still switches "Tap to show English" to the English; the menu does not interfere. (If the press opens nothing and only reveals the English, the page was still scrolling: wait a second and press again.)
- **Verbs → たべる → Examples**: long-pressing a sentence in the sheet shows the same menu.
- With furigana off (Settings → Reading), the menu still works and **Copy** still copies the sentence without readings.

> Not exercised in the verification run: the Examples sheet, Copy then paste, the DeepL and Google pages, iPad and macOS (right-click on macOS shows the same menu; the Apple sheet looks different there).

- [ ] **Step 4: Clean up and commit**

```bash
xcrun simctl uninstall booted dev.martinloeseth.jpverbconjugation.tacheck
git status --short                       # only the App/ files of this task
git add App
git commit -m "$(cat <<'EOF'
Add the long-press menu with Translate to example sentences

Lesson example rows and the Examples sheet get Copy, Open in Jisho and a
Translate submenu with Apple Translate, DeepL and Google Translate. A tap on
a lesson example still reveals the English.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Full verification, merge and publishing

**Files:** none (verification only).

- [ ] **Step 1: Run every test suite**

```bash
cd Packages/VerbKit && swift test 2>&1 | grep -E "error:|failed|Executed .* tests" | tail -1
cd ../.. && python3 -m unittest discover -s scripts -p "test_*.py" 2>&1 | tail -2
python3 scripts/update_data.py --check
```

Expected: `Executed 216 tests, with 0 failures`; `Ran 85 tests ... OK`; `data is up to date`.

- [ ] **Step 2: Build both app targets from a clean generate**

```bash
./scripts/generate-project.sh
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_macOS -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
```

Expected: `** BUILD SUCCEEDED **` twice.

- [ ] **Step 3: Confirm nothing was left behind**

```bash
grep -rn "accessibility" App | grep -E "TextActions|Clipboard"
grep -rn "jisho.org" App Packages | grep -v "/.build/\|Tests"
git status --short
```

Expected: the first prints nothing; the second prints nothing (the only place a Jisho URL is built is `TextLookupURL`, whose file is under `Packages/…/Sources` and contains `jisho.org`, so expect that single line and no line from `App/`); the last shows a clean tree.

- [ ] **Step 4: Merge gracefully**

```bash
git log --oneline main..HEAD | cat                      # only this work's commits
git diff --name-only HEAD...main -- . ':!docs' | cat    # what main changed since we branched
```

If the second command prints nothing, the merge is a fast-forward: from the main checkout, `git merge --ff-only feature/text-actions-impl`. If `main` has moved, do **not** force anything: fetch, merge `origin/main` into the branch (or rebase), keep `main`'s side of any conflict and re-apply only this plan's edits to that file, then re-run Steps 1–3. Get the user's go-ahead before merging into `main`.

- [ ] **Step 5: Publish (needs the user's explicit go-ahead)**

This is an app-only change: nothing here is read from the data repository, so a push changes the source and not what any installed build sees. **Do not push without asking the user first.**
