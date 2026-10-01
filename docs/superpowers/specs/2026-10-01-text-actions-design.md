# Text Actions — Design

**Date:** 2026-10-01
**Status:** Approved in brainstorming, pending written-spec review
**Builds on:** [2026-10-01-verb-page-redesign-design.md](2026-10-01-verb-page-redesign-design.md)
(whose tables made every form its own view),
[2026-09-29-grammar-foundation-nd-desu-design.md](2026-09-29-grammar-foundation-nd-desu-design.md)
(the lesson example rows), [2026-09-30-furigana-design.md](2026-09-30-furigana-design.md)
(why the Japanese text is drawn from many small views) and the
[native rewrite spec](2026-09-23-native-apple-rewrite-design.md) (section 10, the visual
design direction). A UX addition, not part of the grammar roadmap.

## Summary

A **long-press menu** (right-click on macOS) on forms and example sentences, with
actions on the item's exact Japanese text:

- **Forms** (every cell in the Plain / Polite tables): **Copy**, **Open in Jisho**.
- **Example sentences** (the Examples sheet and every lesson example row): **Copy**,
  **Open in Jisho**, and a **Translate** submenu with **Apple Translate**, **DeepL**
  and **Google Translate**.

Decided in brainstorming: actions act on **whole items**, not on a partial selection.
Japanese text with furigana is drawn from many small views, so dragging a selection
handle over part of a sentence is not practical without a custom text view, which
would be a large piece of work and would replace the layout built for furigana.

## 1. What the user gets

- **Exact text.** Each action uses the item's original Japanese: the whole form
  (たべられます, not only the highlighted ending) or the sentence without furigana.
  Copy puts that string on the clipboard.
- **Open in Jisho** opens `https://jisho.org/search/<text>` in the browser, like the
  verb page's Jisho button.
- **Apple Translate** opens the system translation sheet over the app, so the user
  stays in place. The sheet asks for its own consent first (found while building this):
  the text is sent to Apple to be translated unless offline translation is chosen in
  Settings, and the first offline use may download the Japanese language pack. The app
  sends nothing itself.
- **DeepL** and **Google Translate** open with the sentence filled in, Japanese to
  English: in their app if it handles the link, otherwise on the website. Nothing is
  sent anywhere until the user taps one of them.
- **Tap still works.** On a lesson example row a tap still reveals the English and a
  long-press shows the menu. On the Examples sheet the English is already visible, so
  the menu is the only addition.
- **Furigana on or off** makes no difference to the menu.

## 2. Implementation

### Pure logic in VerbKit

`TextLookupURL` builds the three web links from a string and is unit-tested:

- `jisho(_:)` → `https://jisho.org/search/<text>`.
- `deepL(_:)` → `https://www.deepl.com/translator#ja/en/<text>`. The text goes in the
  fragment, so it needs stricter encoding (`/`, `?`, `#`, `%` and spaces all escaped).
- `google(_:)` → `https://translate.google.com/?sl=ja&tl=en&text=<text>&op=translate`.
- Each returns `nil` for blank text. The verb page's own Jisho button moves onto the
  same function so there is one encoder.

### One menu in the app

A single view modifier, `.textActions(_ text: String, translate: Bool)`:

- Attaches a `contextMenu` with **Copy** (a small `Clipboard` helper over
  `UIPasteboard` / `NSPasteboard`), **Open in Jisho** (`openURL`) and, when `translate`
  is true, a **Translate** submenu.
- Apple Translate uses `.translationPresentation(isPresented:text:)`. The modifier holds
  the `@State`, so the sheet attaches outside the menu.
- DeepL and Google use `openURL`.

### Where it attaches

- `FormCell` gets `.textActions(form, translate: false)`, which covers every table on
  every page. Cells get a rectangular content shape so the small hit area is easy to
  long-press.
- `ExampleRow` and the Examples sheet rows get `.textActions(example.jp, translate: true)`.
  `ExampleRow` keeps its tap-to-reveal `Button`; a context menu on a button leaves the
  tap alone.

Visual direction as before: standard menus and controls, no accessibility-specific
modifiers.

## 3. Testing, rollout and risks

### Testing

- **Swift:** `TextLookupURL` against hand-written cases (kanji and kana, Japanese
  punctuation, `/`, `?`, `#`, `%`, spaces, an empty string) and a round trip: decoding
  each URL's text gives back the original.
- **Simulator:** long-press a form and a sentence on iPhone; Copy, then paste into a text
  field; Jisho opens Safari with the right word; the Apple sheet appears and translates;
  DeepL and Google open their web pages with the sentence filled in; a tap on a lesson
  example still reveals the English; the menu works with furigana on and off.

### Rollout

App-only: no data, script or model change, so a push changes the app source and not what
older builds see.

### Risks

| Risk | Covered by |
|---|---|
| Long-press clashes with the tap or with scrolling in a `List` or `ScrollView` | Simulator checks on all three surfaces |
| The Apple sheet asks for consent, needs the language pack, or behaves differently on macOS | The system handles the prompt (checked on iPhone: the sheet opens with its consent screen); macOS noted as unverified |
| DeepL or Google change their URL format | Unit tests pin the format; the links degrade to the website |
| The DeepL fragment mis-encodes unusual characters | The stricter encoding and its tests |

## Files this touches

- **New:** `TextLookupURL` (VerbKit), `App/TextActions.swift`, `App/Clipboard.swift`, and
  tests.
- **Edited, patch-style on top of the latest `main`:** `FormCell.swift`,
  `ExampleRow.swift`, `ExamplesView.swift`, and `VerbDetailView.swift` (the Jisho link
  only).

## Not in this sub-project

- Selecting part of a sentence, menus on lesson headings, the verb header or English
  paragraphs, a preferred-service setting, translating English to Japanese, and any
  history of lookups.
