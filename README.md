# Verb Table

A Japanese verb conjugation app for iOS and macOS (SwiftUI, iOS 26 / macOS 26), with home screen
widgets, grammar lessons and a quiz.

## Layout

| Path | What it is |
|---|---|
| `App/` | The SwiftUI app |
| `Widgets/` | The widget extension |
| `Packages/VerbKit/` | The shared Swift package: models, data sync, quiz, persistence, search. Its tests run with `swift test` |
| `data/` | The published data (`verbs.json`, `grammar.json`, `furigana.json`, `words.json`, `counters.json`, `forms.json`) and the signed `manifest.json` the app syncs from |
| `scripts/` | Python and shell tools for the data, signing, audio and the Xcode project |
| `docs/` | Specs, plans and the data-signing guide |

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not committed.

## Commands

Run `make` to list them. Needs Python 3; `make test-swift` and `make project` need macOS with Xcode and XcodeGen.

| Command | What it does |
|---|---|
| `make install-deps` | Install the Python dependencies (`cryptography`, for signing) |
| `make data` | Regenerate the generated forms, `data/forms.json`, the generated counter readings, the app's bundled copies of all six data files (so a first launch works offline) and `data/manifest.json` after editing `data/*.json` or `scripts/form_catalogue.py` |
| `make data-check` | Verify the data is generated, valid and up to date, without writing |
| `make sign` | Sign `data/manifest.json` with your private key |
| `make verify` | Check `data/manifest.sig` against the key the app trusts |
| `make sign-commit` | Check, sign, verify and commit `data/manifest.sig` (`make sign-commit PUSH=1` also pushes) |
| `make keygen` | Create the signing key (once) |
| `make test` | Run the Python and Swift tests |
| `make test-py` | Run the Python script tests |
| `make test-swift` | Run VerbKit's Swift tests |
| `make check-project` | Check `project.yml` is consistent |
| `make check` | Run the checks CI runs, except the Swift tests |
| `make project` | Generate the Xcode project |
| `make audio-dry` | List the audio clips that would be generated, with no API calls |
| `make clean` | Remove Python caches |

`PYTHON=python3.12 make ...` uses another interpreter.

## Changing the data

The app only trusts a manifest signed with the maintainer's key, so every change under `data/` ends
with a signature. The CI `data` check fails until that is done.

1. Edit `data/verbs.json`, `data/grammar.json`, `data/furigana.json` or `data/words.json`.
2. `make data` regenerates the derived forms and the manifest. Commit the result.
3. On a machine that has the private key, run `make sign-commit` (or `scripts/sign_and_commit.sh`).

Each data file also ships inside the app (`Packages/VerbKit/Sources/VerbKit/Resources/`, written by `make data`,
checked by `make data-check`). On launch a store installs its bundled copy into the persisted data when it is
newer than anything the device has accepted, so a first launch with no network still has every file; a sync
replaces it as usual, and Settings > Data shows "Bundled" until then.

`scripts/sign_and_commit.sh` does the signing step safely:

- It runs `update_data.py --check` first and stops if the data is stale, so it never signs an
  out-of-date manifest.
- It signs, then verifies against the public key in `ManifestSignatureVerifier.swift`. If the
  signature does not verify (usually the wrong key), it puts the old `manifest.sig` back.
- It commits only `data/manifest.sig`, as `data: sign manifest`. It refuses to run with other
  uncommitted changes, or on `main`.
- `--push` pushes the current branch afterwards, and `--no-commit` signs and verifies only.
- The key is read from `$VERBTABLE_SIGNING_KEY` or `~/.config/verbtable/manifest-signing.key`. It
  never leaves your machine and is never committed.

Every verb has a stable id that favourites, quiz history, widgets and links store. It is the verb's
`dict` unless two verbs are spelled the same in kana; the newer one then gets an explicit
`"id": "きる:切る"`. An id never changes once published, and `make data-check` fails if one published
on `origin/main` disappears (fetch `main` first). See
[`docs/superpowers/specs/2026-10-17-verb-id-scheme-design.md`](docs/superpowers/specs/2026-10-17-verb-id-scheme-design.md).

If two branches both change the data, merge one, then on the other run `make data`, commit, and
sign again: the manifest's version and hash change every time. Key setup, data releases and key
rotation are in [`docs/security/data-signing.md`](docs/security/data-signing.md).
