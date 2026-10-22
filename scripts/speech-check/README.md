# Speech check (#143)

Does Apple's on-device ja-JP transcription keep the verbs a learner says? This harness
transcribes recordings of the 41 test sentences from #143 with `SpeechAnalyzer` +
`SpeechTranscriber` and `DictationTranscriber` (and, optionally, whisper.cpp), then scores
each transcript against the typed sentence. It produces the table #143 asks for and applies
the Whisper decision bar.

It's a maintainer tool for the Mac. It isn't part of the app, and nothing here ships.

## Files

| File | What it is |
|---|---|
| `speech_check.py` | The harness: status, model install, TTS, transcribe + score, decision. Standard library only. |
| `speechcheck.swift` | Small Swift helper: `AssetInventory` install, file transcription, `CFStringTokenizer`. Built on first use into `.build/`. |
| `matcher.py` | The prototype "hybrid" verb matcher from the #142 research. #144/#145 replace it. |
| `sentences.json` | The 41 sentences with hand-labelled verbs (54 verbs; 46 are in `data/verbs.json`). |
| `SCRIPT.md` | The recording script: print it and read from it. |

Generated audio, transcripts and scores go to `.build/` (git-ignored). Put your recordings in
`recordings/` (also git-ignored) or anywhere else. **Don't commit recordings of people's voices.**

## Setup (once)

Needs macOS 26+ and the Xcode command line tools (`swiftc`).

```sh
python3 scripts/speech-check/speech_check.py status    # what's installed
python3 scripts/speech-check/speech_check.py install   # downloads and reserves the ja-JP models
```

`install` uses `AssetInventory.assetInstallationRequest(supporting:)` and
`AssetInventory.reserve(locale:)`. On the maintainer's Mac on 2026-10-22 it took 11 s
(SpeechTranscriber) and 22 s (DictationTranscriber). The system catalogue lists the sizes:

| Model | Asset | Download | On disk |
|---|---|---|---|
| SpeechTranscriber ja | `com.apple.speech.asr.transcription.ja` | 130 MB | 176 MB |
| DictationTranscriber ja | `com.apple.siri.asr.assistant.ja_JP` | 327 MB | 680 MB |

(`AssetInstallationRequest.progress` reports a fraction, not bytes, so the sizes come from
`/System/Library/AssetsV2`. The reservation survives across processes: `status` in a new
process lists `ja-JP` under reserved locales.)

## Record

1. Print `SCRIPT.md`. Each speaker reads all 41 sentences, one file per sentence, named by
   number: `01.m4a` … `41.m4a` (Voice Memos, QuickTime, any recorder; `.m4a`, `.wav`,
   `.aiff`, `.caf`, `.mp3` and `.flac` all work). Leave about half a second of silence before
   speaking. Missing numbers are skipped.
2. One folder per speaker, for example:

   ```
   scripts/speech-check/recordings/native-1/01.m4a …
   scripts/speech-check/recordings/learner-a/01.m4a …
   scripts/speech-check/recordings/learner-b/01.m4a …
   ```

   #143 asks for at least one native speaker and at least two learners, of different levels
   if possible. Record in a normal room with the phone or Mac mic, not a studio.
3. A native speaker listens to each learner's files and notes the numbers they could **not**
   understand. Those sentences are left out of the decision: if a human can't understand it,
   the transcriber isn't to blame.

## Run

```sh
cd scripts/speech-check
python3 speech_check.py run recordings/native-1  --kind native
python3 speech_check.py run recordings/learner-a --kind learner --not-understood 7,22
python3 speech_check.py run recordings/learner-b --kind learner
python3 speech_check.py decide
```

`run` prints a Markdown table per engine plus every transcript that differs from the typed
sentence, with lost and respelled verbs marked. `--reuse` re-scores saved transcripts without
transcribing again. `decide` reads every saved result and applies the bar:

> Whisper only if Apple's transcripts lose the target verb or form in more than about 1 in 5
> learner sentences that a native understood, **and** Whisper does clearly better on the same
> audio.

"Clearly better" is set to at least 10 percentage points fewer lost sentences
(`CLEARLY_BETTER` in `speech_check.py`). It's a proposal; the maintainer confirms the decision
on #143.

Synthetic baseline (no recording needed): `make speech-baseline`, or

```sh
python3 speech_check.py tts --voice Kyoko                      # .build/audio/tts-kyoko, 500 ms padding
python3 speech_check.py run .build/audio/tts-kyoko --kind tts
python3 speech_check.py typed                                  # the matcher on the typed text (the ceiling)
```

`say -v '?' | grep ja_JP` lists the other Japanese voices (Kyoko, and Eddy, Flo, Reed, … as
`"Reed (Japanese (Japan))"`).

## What the columns mean

Every metric compares a transcript with the typed sentence in `sentences.json`.

| Column | Meaning |
|---|---|
| Sentences exact | Same text, ignoring punctuation and spaces. |
| Verb chain kept (reading) | The whole labelled verb chain (e.g. 食べさせられなかった) is still there, in any script: same kana reading, on token boundaries. All 54 verbs, in the app or not. |
| Kept verbatim | Same chain, same spelling as typed. |
| Respelled | Kept by reading but spelled differently (分かりません → わかりません, きた → 来た). |
| Matcher right verb / full span | The prototype matcher run on the transcript: right verb found; whole chain matched. 46 in-app verbs. Typed-text ceiling: 46/46 and 44/46. |
| False pos. | Matcher highlights that aren't a labelled in-app verb (grey "not in the app" marks excluded). Typed ceiling: 1. |
| Sentences losing a verb | Sentences where at least one labelled verb chain didn't survive. **This is what the decision bar uses.** |
| Ends 。/？, 、 (typed) | Punctuation: sentences ending in 。/？; commas produced (commas in the typed text). |
| Digits in | Sentences whose transcript contains digits (十分 → 10分, 三年 → 3年). |
| Median s / RTF | Wall time per file from analyzer start to the last final result, and that divided by the audio length. **File input, not live:** it runs faster than real time, so it's a lower bound on the wait after the speaker stops, not live-mic latency. whisper.cpp's time includes loading the model on every file. |
| Mean conf. | Mean `transcriptionConfidence` over the characters (Apple only). |

Both Apple transcribers are run with `.alternativeTranscriptions`. For ja-JP the alternatives
come back as short fragments (" 1分", "充分"), not whole sentences, so they're saved in the
JSON but not scored.

## Whisper (optional)

whisper.cpp from the official sources, a small multilingual model, all local:

```sh
git clone --depth 1 --branch v1.9.5 https://github.com/ggml-org/whisper.cpp ~/src/whisper.cpp
cmake -S ~/src/whisper.cpp -B ~/src/whisper.cpp/build -DCMAKE_BUILD_TYPE=Release   # needs cmake (brew, or pip in a venv)
cmake --build ~/src/whisper.cpp/build -j --target whisper-cli
curl -L -o ~/src/whisper.cpp/models/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin        # 466 MB, the repo's own download source

export WHISPER_CLI=~/src/whisper.cpp/build/bin/whisper-cli
export WHISPER_MODEL=~/src/whisper.cpp/models/ggml-small.bin
python3 speech_check.py run recordings/learner-a --kind learner --engines st,dt,whisper --reuse
```

The harness converts each file to 16 kHz mono WAV with `afconvert` and runs
`whisper-cli -l ja`. kotoba-whisper (Japanese-tuned) has ggml conversions too: point
`WHISPER_MODEL` at one to compare.

## Privacy

Apple's transcribers run on device from the files, and whisper.cpp is local. Nothing is
uploaded. Transcribing files didn't ask for speech-recognition authorisation (the status
stayed `notDetermined`); live mic capture in the app is a separate question for #147.
