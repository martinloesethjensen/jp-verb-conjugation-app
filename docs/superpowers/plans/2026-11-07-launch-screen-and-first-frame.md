# Launch Screen and Themed First Frame Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Replace the navy glass launch screen with paper and the 活 seal: a red teacher's circle in Light, a sumi brush circle in Dark.
- Give the default app icon the same face.
- Have the app's first frame cross-fade from that neutral launch to the chosen theme's paper and stamp, then fade to content.

**Architecture:**
- **VerbKit** gets two testable pieces:
  - an SVG path-data parser that turns `d` strings into path elements (arcs become cubics);
  - the twelve stamp shapes from the canvas as path data.
- **A Swift script** (the existing `scripts/generate-icon.swift`, rewritten) outlines 活 from Shippori Mincho B1. From that outline it renders the launch image and the iOS icons, and writes the same outline as generated Swift. The app and the launch image then draw an identical glyph without bundling the font.
- **App** maps each theme half to a stamp and its colours, draws the seal, and runs the hand-off overlay on iOS.

**Tech Stack:** Swift 6, SwiftUI (iOS 26), CoreGraphics/CoreText/ImageIO in the generator script, XCTest in `Packages/VerbKit`, XcodeGen asset catalog.

**Spec:** `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`, row 2c of "Boards → plans". Design hand-over: canvas boards "Launch screen" (option L2 + L3), "Themed first frame", "App icons" (the Light · Dark set only). Decisions recorded on 2026-11-07:
- the red circle stays on the Light seal;
- 活 is outlined from Shippori Mincho B1 (SIL OFL);
- L3 ships together with L2;
- Mac stays parked;
- seasonal themes never change the icon.

## Global Constraints

- **Branch:** `claude/launch-screen`, from `origin/main` (plans 1, 2 and 2b merged).
- **Seal geometry** is one coordinate space, used everywhere:
  - a 120 × 120 unit box;
  - 活 at an em of 60 units, its bounding box centred in the box;
  - stamp paths in the same box, scaled 0.84 about the centre (60, 60), with round caps and joins;
  - stroke width = the board's base width × 1.8 (`k`), in box units, also scaled by 0.84.
- **Sizes:**
  - launch image and first-frame seal: 122 pt square (122 / 244 / 366 px at @1x/@2x/@3x), centred on the full screen, never scaled with Dynamic Type;
  - app icon: 1024 px square.
- **Launch colours** (the spec's `light` and `dark` palettes):
  - Light: paper `#f6f7f4`, 活 `#1e2633`, teacher's circle `#c2372b`;
  - Dark: paper `#14171c`, 活 and the sumi circle `#e9ebe6`.
- **Font:** Shippori Mincho B1 Bold (`ShipporiMinchoB1-Bold.ttf`, SIL OFL 1.1).
  - It is used only at generation time and is never committed or bundled.
  - The executor downloads it only after the user approves: name, source and size, from `https://github.com/google/fonts/raw/main/ofl/shipporiminchob1/ShipporiMinchoB1-Bold.ttf`, into the session scratchpad.
- **Mac is parked:** the Mac icon PNGs in `AppIcon.appiconset` stay as they are, and the hand-off overlay is iOS only.
- **VerbKit stays UI-free.** The parser and the stamp shapes use `CGPoint` only (Foundation), no SwiftUI.
- **No change under `data/`.** `project.yml` keeps `UILaunchScreen` as it is: same asset names, new contents.
- **Tests:** `make test-swift`. **iOS build:** `make project && xcodebuild -project JPVerbConjugation.xcodeproj -scheme JPVerbConjugation_iOS -destination 'generic/platform=iOS Simulator' build -quiet`. **macOS build:** the same with `-scheme JPVerbConjugation_macOS -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO`; the check is that it shows no Swift `error:` lines.
- **AGENTS.md:** each task adds its shared symbols to the tables, in the same commit.

## Review Focus

- **The seal jumps between the iOS launch screen and the first app frame.** Expected: it stays in the same place and size, and only the paper and stamp change. Covered by the frame-by-frame check in Task 3, step 5.
- **Appearance pinned opposite the phone,** for example Coffee with Appearance Dark on a phone in Light. iOS shows the light launch screen, so the overlay's first layer must match it (screen trait, not the window override), then fade to Coffee. Covered by Task 3, step 5.
- **Reduce Motion on.** Expected: content straight away, with no fade. Covered by Task 3, step 5.
- **The overlay blocks VoiceOver or taps.** Expected: it is hidden from accessibility, never takes hits, and is removed from the view tree when done. Covered by `allowsHitTesting(false)` / `accessibilityHidden(true)` in Task 3, step 3, and the step 5 VoiceOver check.
- **iOS caches the old launch screen.** Testing on a simulator that has the old one installed shows navy. Task 3, step 5 erases the app (uninstall + install) before checking.

---

### Task 1: SVG path data and stamp shapes (VerbKit)

**Files:**
- Create: `Packages/VerbKit/Sources/VerbKit/Seal/SVGPathData.swift`
- Create: `Packages/VerbKit/Sources/VerbKit/Seal/StampShape.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/SVGPathDataTests.swift`
- Create: `Packages/VerbKit/Tests/VerbKitTests/StampShapeTests.swift`
- Modify: `AGENTS.md` (VerbKit table)

**Interfaces:**
- Produces:
  - `public enum SVGPathElement: Equatable, Sendable { case move(CGPoint), line(CGPoint), quad(to: CGPoint, control: CGPoint), cubic(to: CGPoint, control1: CGPoint, control2: CGPoint), close }`
  - `public enum SVGPathData { public static func parse(_ d: String) -> [SVGPathElement] }`. It reads `M m L l H h V v C c S s Q q A a Z z`, implicit command repeats, and numbers such as `-0.1`, `.01` and `1-0.1`. Arcs become one cubic per ≤ 90° segment. Unknown input stops parsing and returns what it has so far.
  - `public enum StampShape: String, CaseIterable, Sendable { case teacher, sumi, rings, raked, enso, heart, mug, scoop, aurora, moon, pumpkin, wreath }`
  - `public struct StampStroke: Equatable, Sendable { public let d: String; public let usesSecondColor: Bool; public let baseWidth: CGFloat }`
  - `StampShape.strokes: [StampStroke]`: the board's `stamp()` table, with `a` meaning `usesSecondColor == false`, `b` meaning `true`, and `baseWidth` set to the width before `k`.
  - `StampShape.ring(_ r:)`, `scallop(cx:cy:r:n:)`, `wavyRing(r:amp:n:)` as `static func … -> String`. Each produces the same string as the board's JavaScript (`toFixed(1)`).

- [ ] **Step 1: Write the failing tests.**

```swift
// SVGPathDataTests
func testAbsoluteAndRelativeCubics() {
    let e = SVGPathData.parse("M60 10C87 9 110 31 109 60c-1 28-23 50-51 49")
    XCTAssertEqual(e.first, .move(CGPoint(x: 60, y: 10)))
    XCTAssertEqual(e[1], .cubic(to: CGPoint(x: 109, y: 60), control1: CGPoint(x: 87, y: 9), control2: CGPoint(x: 110, y: 31)))
    XCTAssertEqual(e[2], .cubic(to: CGPoint(x: 58, y: 109), control1: CGPoint(x: 108, y: 88), control2: CGPoint(x: 86, y: 110)))
}
func testImplicitRepeatAndSmoothCubic() {        // "C… 12 34 31 14 57 11" repeats C; "s22 44 46 46" reflects the last control
}
func testArcBecomesCubicsEndingAtTheEndpoint() { // ring(48): "M60 12a48 48 0 1 1-0.1 0" ends at (59.9, 12) within 0.001, and every segment stays within 48 ± 0.5 of (60, 60)
}
func testHorizontalDotAndClose() {               // "M22 30h.01" → [.move(22,30), .line(22.01,30)]; "…z" ends in .close
}
func testGarbageStopsWithoutCrashing() { XCTAssertEqual(SVGPathData.parse("M1 2 X 3"), [.move(CGPoint(x: 1, y: 2))]) }

// StampShapeTests
func testRingMatchesBoardString() { XCTAssertEqual(StampShape.ring(48), "M60 12a48 48 0 1 1-0.1 0") }
func testScallopAndWavyRingStartLikeTheBoard() {
    XCTAssertTrue(StampShape.scallop(cx: 60, cy: 60, r: 44, n: 14).hasPrefix("M104.0,60.0Q"))
    XCTAssertTrue(StampShape.wavyRing(r: 46, amp: 2.5, n: 7).hasPrefix("M106.0,60.0L"))
}
func testStrokeTable() {                          // teacher: one stroke, base 3, first colour; rings: [5 a, 2 b]; moon: 3 strokes [1.8 a, 2 b, 3 b]
}
func testEveryShapeParses() { for s in StampShape.allCases { for st in s.strokes { XCTAssertFalse(SVGPathData.parse(st.d).isEmpty, "\(s) \(st.d)") } } }
```

- [ ] **Step 2: Run the tests and confirm they fail.** Run `cd Packages/VerbKit && swift test --filter 'SVGPathDataTests|StampShapeTests'`. Expected: a compile failure.
- [ ] **Step 3: Implement both files.**
  - **Arcs:** use the SVG implementation notes' endpoint-to-centre conversion (F.6.5). Scale up radii that are too small (F.6.6). Split the arc into segments of 90° or less, each a cubic with handle length `4/3·tan(Δθ/4)`.
  - **Literal paths:** copy the board's teacher, sumi, enso, heart, moon and pumpkin strings exactly. Copy the extra strings for the mug, pumpkin stem and leaf, wreath berries and moon stars exactly.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the filter, then `make test-swift`. Expected: all pass.
- [ ] **Step 5: Update AGENTS.md and commit.**
  - AGENTS.md VerbKit table: add `SVGPathData.parse(_:)` (SVG `d` strings to path elements, arcs as cubics) and `StampShape` (the twelve results/icon stamps as path data).
  - Commit message: `Seal: SVG path data parser and the twelve stamp shapes`.

### Task 2: Generator, launch assets and default icon

**Files:**
- Rewrite: `scripts/generate-icon.swift`
- Create (generated, committed): `App/Launch/SealGlyph.swift`
- Modify (generated): `App/Assets.xcassets/LaunchBackground.colorset/Contents.json`, `App/Assets.xcassets/LaunchImage.imageset/*` (light and dark PNGs, plus `Contents.json` with a dark appearance), and `App/Assets.xcassets/AppIcon.appiconset/icon-1024{,-dark,-tinted}.png`

**Interfaces:**
- Consumes: the seal geometry from Global Constraints. The teacher and sumi `d` strings are converted to absolute CoreGraphics calls in the script, with a comment pointing to `StampShape`. The script is standalone and can't import VerbKit.
- Produces: `enum SealGlyph { static func path(in rect: CGRect) -> Path }` in App. It draws the 活 outline in the 120-unit box, scaled to `rect`. Its coordinates are generated, rounded to 0.01, and y-down.

- [ ] **Step 1: Ask the user to approve the font download, then download it.** Give the name, source and size. After approval, run `curl -L -o <scratchpad>/fonts/ShipporiMinchoB1-Bold.ttf <url>`, then `file <path>`. Expected: `TrueType Font data`.
- [ ] **Step 2: Rewrite the script.**
  - Usage: `swift scripts/generate-icon.swift --font <ttf> [repo-root]`.
  - Without `--font` it exits 1, printing the download URL and the licence.
  - It loads the font with `CTFontManagerCreateFontDescriptorsFromURL` and takes the glyph path for 活 with `CTFontCreatePathForGlyph`. It flips the path to y-down and centres the glyph's bounding box in the 120 box at an em of 60.
  - It writes:
    - `App/Launch/SealGlyph.swift`, with a header saying it is generated, the font, and the licence;
    - `LaunchBackground`: any appearance `#f6f7f4`, dark `#14171c`;
    - `LaunchImage`: transparent PNGs, `launch-light@{1,2,3}x.png` with the teacher's circle and `launch-dark@{1,2,3}x.png` with the sumi circle, at 122 pt;
    - the iOS icons at 1024 px:
      - default: paper `#f6f7f4`, the teacher's circle and ink 活;
      - dark: paper `#14171c`, sumi, `#e9ebe6`;
      - tinted: black background, 活 white at 95%, the stamp white at 60% (the board's Tinted look).
  - It doesn't write Mac files or the old aurora art; delete those functions.
- [ ] **Step 3: Run the script, then look at the outputs.** Open `launch-light@3x.png`, `launch-dark@3x.png` and the three 1024 icons with the Read tool. Expected: they match the board's L2 phones and the Light · Dark icon set, and the old navy art is gone.
- [ ] **Step 4: Build iOS.** Expected: it succeeds. Nothing uses `SealGlyph` yet; it only has to compile.
- [ ] **Step 5: Commit** the script, the generated Swift and the assets. Message: `Launch screen and default icon: paper with the 活 seal, outlined from Shippori Mincho B1`.

### Task 3: Theme stamps, seal view and the first-frame hand-off (App)

**Files:**
- Create: `App/Launch/ThemeStamp.swift`
- Create: `App/Launch/SealView.swift`
- Create: `App/Launch/LaunchHandoff.swift`
- Modify: `App/JPVerbConjugationApp.swift` (overlay on the main `WindowGroup` content, iOS only)
- Modify: `AGENTS.md` (components table)

**Interfaces:**
- Consumes: Task 1's `StampShape`, `StampStroke` and `SVGPathData`; Task 2's `SealGlyph`; plan 2b's `ThemeChoice`, `ThemePalette.resolve(_:isDark:contrast:)` and `\.palette`.
- Produces:
  - `struct ThemeStamp { let shape: StampShape; let first: Color; let second: Color }` with `static func stamp(for theme: ThemeID, isDark: Bool) -> ThemeStamp`. Its values come from the "Themed first frame" board:

| Theme | Light half (shape, a, b) | Dark half (shape, a, b) |
|---|---|---|
| light | teacher `c2372b` | sumi `e9ebe6` |
| pastel | rings `c9b6f2`, `f2b8cf` | rings `b9a3ef`, `f27a98` |
| sand | raked `a8743a` | raked `c08a4a` |
| matcha | enso `4a6b35` | enso `8fbf6a` |
| latte | heart `a8714a` | mug `c8945f` |
| iceCream | scoop `e07aa0` | scoop `f08ab0` |
| northernLights | aurora `1fae84`, `7c5fd6` | aurora `5fe3b0`, `a78bfa` |
| nocturnal | moon `7a70e0`, `3d3680` | moon `8f86f0`, `b9b3ff` |
| halloween | pumpkin `e2701a`, `4d7a2a` | pumpkin `ff8a2a`, `9ad36a` |
| christmas | wreath `1f6b45`, `b3202c` | wreath `7fcf9a`, `ef6b5e` |

  A shape with no `b` uses `a` for both colours.
  - `struct SealView: View { let stamp: ThemeStamp; let ink: Color }`. It draws in a fixed 122 × 122 pt frame using the seal geometry: each `StampStroke` parsed and stroked with `baseWidth × 1.8 × 0.84 × (122 / 120)`, then `SealGlyph` filled with `ink`. It is `accessibilityHidden(true)`.
  - `struct LaunchHandoff: View`. It is the full-screen overlay; the App owns `@State var showsHandoff = true` and removes it on completion.

- [ ] **Step 1: Implement `ThemeStamp` and `SealView`.**
- [ ] **Step 2: Implement `LaunchHandoff`.** It has two layers, `ignoresSafeArea()`, with the seal centred:
  1. **Launch layer:** the iOS launch look for the phone's own appearance, read from `UIScreen.main.traitCollection.userInterfaceStyle` (the window override doesn't change it). It shows the `light` or `dark` palette paper, the teacher or sumi stamp, and that palette's ink.
  2. **Theme layer:** on top, the current theme half's paper from `\.palette`, `ThemeStamp.stamp(for: effectiveTheme, isDark:)` and `palette.ink`. It starts at opacity 0.

  Sequence:
  - After the first frame (`.task { await Task.yield() }`), the theme layer fades in over 250 ms (`.easeOut`), then the whole overlay fades out over 200 ms. Then it calls `onFinished`.
  - With Reduce Motion on, `onFinished` is called at once, with no animation.
  - It never waits for data.
  - `allowsHitTesting(false)`, `accessibilityHidden(true)`.
- [ ] **Step 3: Wire it in.** In the main `WindowGroup`, inside `.themedRoot()` so the palette is available, add `#if os(iOS) .overlay { if showsHandoff { LaunchHandoff { showsHandoff = false } } } #endif`. The state lives in the App struct, so the overlay runs once per cold launch.
- [ ] **Step 4: Build iOS and macOS.** Expected: iOS succeeds, and macOS shows no Swift `error:` lines.
- [ ] **Step 5: Check on the simulator.** Uninstall the app first, so iOS drops the cached launch screen.
  - **Frame by frame:** record with `xcrun simctl io <udid> recordVideo <file>` while launching. If `ffmpeg` is installed, extract the frames; otherwise step through the video in QuickTime. Check:
    - Light theme, Automatic, phone Light: the paper and teacher seal stay put from the launch to the first frame, then the content fades in.
    - Coffee (latte), Appearance Dark, phone Light: the light launch, then the paper and mug stamp fade to Coffee with the seal in the same place, then the content.
    - Nocturnal, Automatic, phone Dark: the dark launch, then the moon stamp on nocturnal paper.
  - **Reduce Motion** (`xcrun simctl spawn <udid> defaults write com.apple.Accessibility ReduceMotionEnabled -bool true`, then relaunch): content straight away. Turn it back off afterwards.
  - **VoiceOver:** the Accessibility Inspector, or a VoiceOver swipe right after launch, lands on content, never on the seal.
- [ ] **Step 6: Update AGENTS.md and commit.**
  - AGENTS.md components table: add `ThemeStamp` / `SealView` (a theme half's stamp and the 活 seal, for the first frame now and alternate icons later) and `LaunchHandoff`.
  - AGENTS.md traps: "The launch screen and icons are generated by `swift scripts/generate-icon.swift --font <ShipporiMinchoB1-Bold.ttf>`. Don't hand-edit `SealGlyph.swift` or the PNGs."
  - Commit message: `First frame: cross-fade from the launch seal to the theme's stamp, then to content`.

### Task 4: Spec status and checks

**Files:**
- Modify: `docs/superpowers/specs/2026-11-06-paper-ink-redesign-design.md`

- [ ] **Step 1: Update the spec.**
  - Mark row 2c "(built)".
  - Add a short "Launch" paragraph under Themes, covering the static L2 launch, the first-frame cross-fade, Reduce Motion, and that 活 comes from Shippori Mincho B1 (OFL).
- [ ] **Step 2: Run `make check`, `make check-project` and `make test-swift`.** Expected: all pass.
- [ ] **Step 3: Commit.** Message: `Spec: launch screen and first frame built`.
