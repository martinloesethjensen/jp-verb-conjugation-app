# Audio for Verbs and Forms — Design

**Date:** 2026-10-01
**Status:** Approved in brainstorming
**Builds on:** the [text-actions spec](2026-10-01-text-actions-design.md) (the long-press
menu stays as it is) and the [verb page redesign](2026-10-01-verb-page-redesign-design.md).

## Summary

Speak Japanese with the system's built-in voice (`AVSpeechSynthesizer`): forms, the
dictionary form, example sentences and quiz answers. No recorded audio, no server, no
data change.

Out of scope: recorded native audio, a voice picker, pitch accent, per-word
highlighting, speaking lesson body text.

## 1. What the user gets

- **Tap a form cell** (verb page, Potential, んです and Auxiliaries sub-pages, the
  Overview table) to hear it. Cells did nothing on tap before, so nothing is replaced;
  Copy and Open in Jisho stay on long-press.
- **Verb page:** a speaker button beside the dictionary form in the header, and a
  speaker in the toolbar.
- **Example sentences:** a small speaker icon on each example row (Examples and the
  grammar lessons). Tapping the sentence text still does nothing.
- **Quiz:** the correct answer is spoken after each answer, on by default.
- **Settings > Audio:** *Speak after quiz answers* (switch, default on) and *Speed*
  (Normal or Slow, Slow is about 70% of the default rate). A footer points to
  iOS Settings > Accessibility > Spoken Content for downloading better voices.
- Tapping while speaking stops it; starting a new utterance cuts off the previous one.

## 2. Structure

- **`VerbKit/Speech/SpeechText.swift`** (pure, tested): `SpeechText.spoken(_ text:)`
  returns what to say or nil. It trims whitespace, removes ruby markup and the
  separators `~` and `/`, and returns nil for blank text. A dictionary form with kanji
  is spoken from the kanji; forms and sentences are spoken as shown.
- **`App/Speaker.swift`:** one shared `@Observable Speaker` wrapping
  `AVSpeechSynthesizer`.
  - Voice: chosen once from `AVSpeechSynthesisVoice.speechVoices()` filtered to `ja-JP`,
    highest quality first (Premium, Enhanced, Default).
  - Audio session: `.playback` with ducking, so speech is audible with the silent switch
    on, other audio is lowered, then restored. (macOS has no audio session; it is skipped
    there.)
  - API: `speak(_ text: String)`, `stop()`, `isSpeaking`, and rate from the Settings
    speed (`@AppStorage("speechSpeed")`).
- **`.speakOnTap(_ text: String)`** (view modifier, used by `FormCell`) and
  **`SpeakButton`** (small icon button, used by the verb header, toolbar and
  `ExampleRow`/`ExamplesView`).
- **`QuizView`** speaks the correct answer after feedback shows, if the Settings switch
  is on; leaving the quiz stops speech.
- **`SettingsView`** gains the Audio section.

If no Japanese voice is installed, buttons do nothing silently, and the Audio section
shows a short "No Japanese voice installed" note.

## 3. Testing

- **Swift (VerbKit):** `SpeechText` on kanji, kana, sentences with ruby markup,
  separators and blank input.
- **Simulator:** buttons, tap targets, quiz flow and the Settings section. Actual sound
  cannot be checked from a screenshot; the final report says so and asks the user to
  listen on a device.

## Risks

| Risk | Covered by |
|---|---|
| No sound with the silent switch on | `.playback` session |
| Overlapping or stuck speech | Stop before each speak; stop on leaving the quiz |
| A tap on a cell also triggers the row or a navigation link | Simulator check on every table |
| Poor default voice | Best installed voice is chosen; footer points to downloads |

## Files this touches

- **New:** `VerbKit/.../Speech/SpeechText.swift`, `App/Speaker.swift`, `App/SpeakButton.swift`,
  tests.
- **Edited:** `FormCell.swift`, `VerbDetailView.swift`, `ExampleRow.swift`,
  `ExamplesView.swift`, `QuizView.swift`, `SettingsView.swift`.

## Addendum: recorded clips

Recorded native-quality audio is now supported alongside the system voice.

- `scripts/generate_audio.py` collects every string the app speaks (verb dictionary
  forms, all conjugated forms, verb and lesson example sentences), cleans it as
  `SpeechText.spoken` does, and synthesizes one `App/Audio/<name>.mp3` per text with
  Amazon Polly or Google Cloud TTS. `<name>` is `SpeechText.clipName`, the first 16
  hex digits of the SHA-256 of the cleaned text, so re-runs only generate what is
  missing. `--dry-run`, `--check`, `--samples N` and `--prune` are available.
- `Speaker` plays the clip when one is bundled and the voice setting is Automatic.
  Text without a clip (for example verbs added later through the data update) and
  any specific voice chosen in Settings use the system voice.
- Slow speed plays clips at 0.75x with `AVAudioPlayer`.
- Check the provider's terms before shipping generated audio.
