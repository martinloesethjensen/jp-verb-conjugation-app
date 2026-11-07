# Paper-and-ink redesign — design

Status: design agreed on the canvas, not built. Canvas: https://claude.ai/artifact/7eCLPFjJnWRoGB2n85ocr2
(private; boards named below).

## Goal

Bring the Kotoba Table review site's look — paper, ink, red only where something was marked — into the
iOS app while it stays a native SwiftUI app, and add themes, kanji stroke order, a global search and
onboarding.

## Rules (all plans)

1. **Liquid Glass on chrome only**: tab bar, navigation bar, toolbar buttons, sheets. Content sits on
   `paper` with `card` surfaces outlined by a 1 pt `rule`, not glass.
2. **Red is earned**: `mark` colours wrong answers, corrections and destructive actions only.
3. **Ink is the one strong colour**: selected chips and the primary button fill with `button`.
4. **Furigana on every kanji** when "Show furigana" is on: all Japanese goes through `JapaneseText`.
5. **Verb forms are kana**, as published in `data/verbs.json` (`たべます`, not `食べます`). Kanji appear
   in headwords, examples and explanations.
6. **Type colours stay, quieter**: a verb type is an ink label with a small colour dot. Pastel and
   Ice cream fill the pill with the type colour instead.
7. **Never colour alone**: the type name or て ending sits beside every dot; quiz marks carry a glyph.
   With Differentiate Without Color on, dots become shapes (Irregular ◆ `diamond.fill`, Ru ●
   `circle.fill`, U ▲ `triangle.fill`) and quiz marks add the words "Your answer" / "Correct".
8. **Contrast**: text tokens ≥ 4.5:1 on `paper` and `card` in every palette (checked below). Increase
   Contrast darkens `muted` and `rule` (see Increase Contrast).
9. **Type**: SF Pro with Dynamic Type for Latin text. Japanese headwords use Hiragino Mincho ProN
   W6 (`HiraMinProN-W6`, ships with iOS); example sentences and common phrases use the lighter W3
   (`HiraMinProN-W3`), with the example's verb form underlined (and bold where the face allows), as
   the boards draw them. Both scale `relativeTo:` a text style. Dense form tables keep the system
   Japanese font.
10. **No in-app colour-blind themes**: iOS Color Filters cover that. The app honours Differentiate
    Without Color and Increase Contrast.

## Themes

Ten themes in four picker groups, and every theme has a light half and a dark half. Names are UI copy and
live in App. Light/Dark and Latte/Coffee are one theme each, named after whichever half is showing.

| Group | Theme (`ThemeID`) | Name (light / dark half) | Palettes (light / dark) |
|---|---|---|---|
| Everyday | `light` | Light / Dark | light / dark |
| Everyday | `pastel` | Pastel | pastel / pastelDark |
| Everyday | `sand` | Sand | sand / sandDark |
| Café | `matcha` | Matcha | matcha / matchaDark |
| Café | `latte` | Latte / Coffee | latte / coffee |
| Café | `iceCream` | Ice cream | iceCream / iceCreamDark |
| Night | `northernLights` | Northern lights | northernLightsLight / northernLights |
| Night | `nocturnal` | Nocturnal | nocturnalLight / nocturnal |
| Seasonal | `halloween` | Halloween; automatic in October | halloweenLight / halloween |
| Seasonal | `christmas` | Christmas; automatic in December | christmas / christmasDark |

Settings › Theme: an **Appearance** control (**Automatic**, **Light**, **Dark**; default Automatic), the ten
swatches, and **Seasonal themes** (default off). Automatic follows iOS; Light and Dark pin the window, so
sheets, alerts and the keyboard match. The theme never forces an appearance. Swatches show the half that
is showing. With seasonal on, October shows Halloween and December shows Christmas, whatever the chosen
theme, in the chosen appearance; on 1 November and 1 January the chosen theme returns.

Stored settings migrate once:
- Before themes, `appearanceMode`: `system` → Light + Automatic; `light` → Light + Light; `dark` → Light + Dark.
- Plan 1's keys (`theme`, `themeMatchesSystem`): `dark` becomes `light` and `coffee` becomes `latte`. Matching
  on becomes Automatic. Matching off pins the half that was showing: Dark for `dark` and `coffee`, Light for
  `light`, `latte`, `pastel` and `sand`. The six themes that used to force an appearance become Automatic.

### Palettes

Twenty palettes of twelve tokens. Hex, sRGB.

| Palette | paper | card | ink | muted | rule | mark | markSoft | good | goodSoft | button | onButton | accent |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| light | f6f7f4 | ffffff | 1e2633 | 5f6673 | dce0d8 | c2372b | fbeceb | 2e6b45 | e2f0e6 | 1e2633 | ffffff | 1e2633 |
| dark | 14171c | 1d2128 | e9ebe6 | 9aa1ad | 2c323b | ef6b5e | 3a2422 | 6fbf8c | 1f3327 | e9ebe6 | 14171c | 6fbf8c |
| pastel | fbf5fa | ffffff | 3a2e4a | 6e6280 | eddff0 | c43a5c | fce8ee | 3c7a5a | e4f3ea | 3a2e4a | ffffff | 9b7fe6 |
| pastelDark | 1c1724 | 262033 | f0e8f6 | b3a7c2 | 3a3049 | f27a98 | 3d2230 | 8fd1aa | 1f3328 | d9c8f5 | 1c1724 | b9a3ef |
| sand | f2ebdf | fbf7f0 | 3b2f22 | 6a5b47 | e0d3bd | b5432a | f6e3da | 4f6b34 | e8eedb | 3b2f22 | fbf7f0 | a8743a |
| sandDark | 1e1a15 | 29231c | f1e8da | b9aa94 | 3d3428 | e8775a | 3d241b | a9c47f | 2a3220 | f1e8da | 1e1a15 | c08a4a |
| matcha | eef1e6 | fbfcf7 | 24361f | 5a6852 | d5dccb | b23a2e | f6e2df | 3f6b2a | e1ecd6 | 4a6b35 | ffffff | 5f8a43 |
| latte | f5eee6 | fffaf5 | 4a3426 | 735a4b | e6d8ca | b5442f | f7e3dc | 4d6b3c | e5eedc | 8a5a3c | ffffff | a8714a |
| coffee | 1f1712 | 2a201a | f0e6dc | b8a796 | 3e3027 | f07a62 | 3e231c | a8c98a | 26301e | d9b48f | 1f1712 | c8945f |
| iceCream | fff6f8 | ffffff | 3d2b3a | 75606f | f3dde4 | c7365e | fde6ec | 2f7d6a | dff3ec | 3d2b3a | ffffff | e07aa0 |
| northernLights | 0d1622 | 142233 | e6f1f2 | 9fb4bf | 22364a | ff7a8a | 3a1d28 | 5fe3b0 | 123a30 | 5fe3b0 | 0d1622 | 3fcf98 |
| nocturnal | 0b0b14 | 141422 | d9d7f0 | 9894b8 | 25243a | e8836f | 34201f | 8fc7a0 | 1a2e24 | b9b3ff | 0b0b14 | 8f86f0 |
| halloween | 17121c | 231a2b | f5ebdd | b7a9bd | 3a2d44 | ff8a2a | 3b2516 | 9ad36a | 25331d | ff8a2a | 17121c | ff8a2a |
| christmas | f4f0e8 | ffffff | 163a2a | 56675c | ddd7c9 | b3202c | f8e4e3 | 1f6b45 | e0efe5 | 163a2a | ffffff | 1f6b45 |
| matchaDark | 141a12 | 1c2419 | e6eddc | a6b29a | 2e3a28 | ec7a66 | 3a2420 | 9fcf7f | 22301c | b5d39a | 141a12 | 8fbf6a |
| iceCreamDark | 1f1720 | 2a1f2b | f6e6ee | c3a9b8 | 413041 | ff7a9a | 40202c | 7fd8bd | 1d3530 | f2a6c4 | 1f1720 | f08ab0 |
| christmasDark | 0f1d16 | 16271e | f1ece0 | a9b8ad | 284034 | ef6b5e | 3a2220 | 7fcf9a | 1a3326 | f1ece0 | 0f1d16 | d9b45a |
| northernLightsLight | eef5f6 | ffffff | 12283a | 4d6676 | d3e2e6 | c2364a | fbe6ea | 1f7a5a | dcf1e8 | 12283a | ffffff | 1fae84 |
| nocturnalLight | f3f2fa | ffffff | 24223f | 5f5b80 | e0def0 | bf3f30 | f9e5e2 | 2f6f4a | e0efe6 | 3d3680 | ffffff | 7a70e0 |
| halloweenLight | f6efe4 | fffaf2 | 2e2135 | 66586c | e6d9c6 | b3361f | f8e2da | 4d7a2a | e5efd8 | 2e2135 | fffaf2 | e2701a |

Palette per theme and half: the Themes table above.

Checked contrast (WCAG): ink on paper 10.1–15.8; muted on paper 5.2–8.4 and on card 5.6–7.5; mark on
card 5.1–7.1; good on card 4.9–10.0; onButton on button 5.8–15.2; button on paper and card,
and ink on markSoft and goodSoft, pass in every palette. All ≥ 4.5; the six palettes added for the dark and light halves are checked on the canvas board "Six new halves" (lowest: good on card in halloweenLight, 4.9). `accent` and `mark`/`good` on
their soft fills do **not** pass in every light palette, so they never colour text: a marked quiz
answer keeps ink text and carries the mark colour in its outline, strike and glyph.

**Increase Contrast**: `muted` becomes a 50/50 mix of `muted` and `ink`; `rule` becomes a 50/50 mix
of `rule` and `muted`; card outlines draw at 1.5 pt.

`accent` fills switches only. Text buttons, links and the selected tab use `button`. Pastel, pastelDark,
Ice cream and iceCreamDark set `fillsTypePills`.

## Boards → plans

| Plan | Scope | Canvas boards |
|---|---|---|
| 1. Theme foundation | `ThemeID`/`ThemeChoice`, palettes, root wiring and migration, paper surfaces, type label, Mincho headword in verb rows, level badge, filter chip, quiz marking, theme picker, widget palette | Style map, Proposed list/page/quiz/dark, Settings, Theme picker v2, Themes across screens, Colour-blind and contrast |
| 2. Verb page and examples (built) | Mincho headwords on detail pages, Plain/Polite table, More forms rows, genkō example cards, results stamp | Verb page full length, potential, quiz results |
| 2b. Theme halves and Appearance | Every theme light and dark, six new palettes, the Appearance control, ten swatches, migration, widgets | Six new halves, Theme picker, Themes across screens |
| 2c. Launch screen and first frame | Paper launch screen with the 活 seal (Shippori Mincho B1), the themed first frame that fades to content | Launch screen, Themed first frame |
| 3. Kanji stroke order | KanjiVG subset as a signed `data/` file + schema + spec, a seventh concrete sync service, path parser, Watch/Trace sheet, entry points | Kanji stroke order, trace, opening it |
| 4. Global search | `Tab(role: .search)`, one index over verbs, grammar, counters and the Word Bank, romaji, recents, hidden-level row | Search boards |
| 5. Onboarding | Levels, furigana, theme, first verb | Onboarding |
| 6. Theme personality | Alternate app icons, title motifs, results stamps | Theme personality |
| 7. Word Bank depth | Entry page and editor restyle, suggestion card | Word Bank entry, add a word |

Plans 2–7 depend only on plan 1. Each is planned when it starts.
