#!/usr/bin/env python3
"""Maintainer tool: pre-generate the recorded Japanese audio bundled in the app.

The app plays App/Audio/<name>.mp3 when one exists for the text it is about to
speak, and falls back to the system voice otherwise. <name> is the first 16 hex
digits of the SHA-256 of the cleaned text (see SpeechText.clipName in VerbKit), so
a clip is found by its text and re-running only generates what is missing.

    python3 scripts/generate_audio.py --dry-run              # count texts and characters, no credentials
    python3 scripts/generate_audio.py --engine polly --samples 20 --out /tmp/audio-samples
    python3 scripts/generate_audio.py --engine polly         # fill App/Audio
    python3 scripts/generate_audio.py --engine google --voice ja-JP-Neural2-B
    python3 scripts/generate_audio.py --check                # exit 1 if any clip is missing
    python3 scripts/generate_audio.py --prune --dry-run      # list clips no text uses any more

Engines (credentials come from the environment, never from the repo):
  polly   needs `pip install boto3` and AWS credentials with polly:SynthesizeSpeech.
          Default voice Tomoko (neural); Kazuha and Takumi are the other ja-JP voices.
  google  needs GOOGLE_API_KEY (Cloud Text-to-Speech API enabled). Standard library
          only. Default voice ja-JP-Neural2-B.

Check the provider's terms before shipping generated audio in a distributed app.
"""
import argparse
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
DEFAULT_OUT = ROOT / "App" / "Audio"
EXTENSION = "mp3"

DEFAULT_VOICES = {"polly": "Tomoko", "google": "ja-JP-Neural2-B"}


def spoken(text):
    """Mirror of SpeechText.spoken in VerbKit: what the app actually says."""
    result = text.replace("~", "").replace("〜", "")
    pieces = [p.strip() for p in result.split("/")]
    result = "、".join(p for p in pieces if p)
    result = result.strip()
    return result or None


def clip_name(text):
    """Mirror of SpeechText.clipName in VerbKit."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def collect_texts(verbs_doc, grammar_doc):
    """Every string the app speaks, cleaned, in first-seen order without repeats."""
    raw = []
    for verb in verbs_doc.get("verbs", []):
        # The dictionary form, as the detail header speaks it (kanji when there is one).
        kanji = (verb.get("kanji") or "").strip()
        raw.append(kanji or verb.get("dict"))
        for value in (verb.get("forms") or {}).values():
            raw.append(value)
        for example in verb.get("examples") or []:
            raw.append(example.get("jp"))
    for point in grammar_doc.get("grammar", []):
        for section in ("usages", "pitfalls"):
            for entry in point.get(section) or []:
                for example in entry.get("examples") or []:
                    raw.append(example.get("jp"))
    seen = {}
    for item in raw:
        if not isinstance(item, str):
            continue
        text = spoken(item)
        if text:
            seen.setdefault(text, None)
    return list(seen)


def load_texts():
    verbs = json.loads((DATA / "verbs.json").read_text(encoding="utf-8"))
    grammar = json.loads((DATA / "grammar.json").read_text(encoding="utf-8"))
    return collect_texts(verbs, grammar)


# --- Engines ----------------------------------------------------------------

def synthesize_polly(text, voice):
    try:
        import boto3
    except ImportError:
        sys.exit("The polly engine needs boto3: pip install boto3")
    if not hasattr(synthesize_polly, "client"):
        synthesize_polly.client = boto3.client(
            "polly", region_name=os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION") or "us-east-1"
        )
    client = synthesize_polly.client
    response = client.synthesize_speech(
        Text=text, VoiceId=voice, Engine="neural", LanguageCode="ja-JP", OutputFormat="mp3"
    )
    return response["AudioStream"].read()


def synthesize_google(text, voice):
    key = os.environ.get("GOOGLE_API_KEY")
    if not key:
        sys.exit("The google engine needs GOOGLE_API_KEY in the environment.")
    body = json.dumps({
        "input": {"text": text},
        "voice": {"languageCode": "ja-JP", "name": voice},
        "audioConfig": {"audioEncoding": "MP3"},
    }).encode("utf-8")
    request = urllib.request.Request(
        f"https://texttospeech.googleapis.com/v1/text:synthesize?key={key}",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return base64.b64decode(json.load(response)["audioContent"])


ENGINES = {"polly": synthesize_polly, "google": synthesize_google}


def is_retryable(error):
    """Network trouble, throttling and server errors are worth retrying; bad
    credentials or a bad request will not improve."""
    if isinstance(error, urllib.error.HTTPError):
        return error.code == 429 or error.code >= 500
    if isinstance(error, (urllib.error.URLError, TimeoutError, ConnectionError)):
        return True
    code = getattr(error, "response", {}).get("Error", {}).get("Code", "")  # botocore ClientError
    return code in ("ThrottlingException", "ServiceFailureException", "ServiceUnavailableException")


def synthesize_with_retry(engine, text, voice, attempts=4):
    for attempt in range(attempts):
        try:
            return ENGINES[engine](text, voice)
        except Exception as error:  # noqa: BLE001
            if attempt == attempts - 1 or not is_retryable(error):
                raise
            time.sleep(2 ** (attempt + 1))


# --- Commands ---------------------------------------------------------------

def missing_clips(texts, out):
    return [t for t in texts if not (out / f"{clip_name(t)}.{EXTENSION}").exists()]


def stale_clips(texts, out):
    wanted = {f"{clip_name(t)}.{EXTENSION}" for t in texts}
    return sorted(p for p in out.glob(f"*.{EXTENSION}") if p.name not in wanted)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--engine", choices=sorted(ENGINES), default="polly")
    parser.add_argument("--voice", help="engine voice name (default depends on the engine)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output folder (default App/Audio)")
    parser.add_argument("--samples", type=int, metavar="N", help="only the first N missing clips, spread across the list")
    parser.add_argument("--force", action="store_true", help="regenerate clips that already exist")
    parser.add_argument("--dry-run", action="store_true", help="report what would be done; no network, no writes")
    parser.add_argument("--check", action="store_true", help="exit 1 if any clip is missing")
    parser.add_argument("--prune", action="store_true", help="delete clips no text uses any more")
    args = parser.parse_args(argv)

    texts = load_texts()
    out = args.out
    missing = texts if args.force else missing_clips(texts, out)
    characters = sum(len(t) for t in missing)
    print(f"{len(texts)} texts, {len(texts) - len(missing)} with clips, {len(missing)} to generate ({characters} characters)")

    if args.prune:
        stale = stale_clips(texts, out) if out.exists() else []
        for path in stale:
            print(("would delete " if args.dry_run else "deleting ") + path.name)
            if not args.dry_run:
                path.unlink()
        if not stale:
            print("no stale clips")
        return 0

    if args.check:
        for text in missing:
            print(f"missing: {text}")
        return 1 if missing else 0

    if args.samples is not None and len(missing) > args.samples > 0:
        step = len(missing) / args.samples
        missing = [missing[int(i * step)] for i in range(args.samples)]

    if args.dry_run:
        for text in missing[:20]:
            print(f"would generate {clip_name(text)}.{EXTENSION}: {text}")
        if len(missing) > 20:
            print(f"... and {len(missing) - 20} more")
        return 0

    voice = args.voice or DEFAULT_VOICES[args.engine]
    out.mkdir(parents=True, exist_ok=True)
    for index, text in enumerate(missing, 1):
        audio = synthesize_with_retry(args.engine, text, voice)
        (out / f"{clip_name(text)}.{EXTENSION}").write_bytes(audio)
        print(f"[{index}/{len(missing)}] {text}")
    print(f"Done: {len(missing)} clips written to {out} with {args.engine}/{voice}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
