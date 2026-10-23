#!/usr/bin/env python3
"""Speech check (#143): how well on-device ja-JP transcription keeps the verbs.

Transcribes a folder of recordings of the 41 test sentences with Apple's
SpeechTranscriber ("st") and DictationTranscriber ("dt"), optionally whisper.cpp,
and scores every transcript against the typed sentence. See README.md.

    python3 scripts/speech-check/speech_check.py status
    python3 scripts/speech-check/speech_check.py install           # one-time ja-JP model download
    python3 scripts/speech-check/speech_check.py script > script.md   # what to read aloud
    python3 scripts/speech-check/speech_check.py tts --voice Kyoko   # synthetic baseline audio
    python3 scripts/speech-check/speech_check.py run DIR --kind learner --label me
    python3 scripts/speech-check/speech_check.py decide             # the Whisper decision bar
    python3 scripts/speech-check/speech_check.py typed              # matcher on the typed text

macOS 26+ with Xcode command line tools. Standard library only. Nothing leaves the
Mac: Apple's transcribers run on device from the files, and whisper.cpp is local.
"""
import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD = HERE / ".build"
BIN = BUILD / "speechcheck"
RESULTS = BUILD / "results"
SENTENCES = json.loads((HERE / "sentences.json").read_text())["sentences"]
BY_N = {s["n"]: s for s in SENTENCES}
AUDIO_EXT = {".aiff", ".aif", ".wav", ".m4a", ".caf", ".mp3", ".flac"}
ENGINES = {"st": "SpeechTranscriber", "dt": "DictationTranscriber", "whisper": "whisper.cpp", "typed": "(typed text)"}
PUNCT = "。、？！?!,.・「」 　\t"
DIGIT = re.compile(r"[0-9０-９]")
LOSS_BAR = 0.20          # the issue's "more than about 1 in 5"
CLEARLY_BETTER = 0.10    # Whisper must lose at least 10 points fewer sentences (proposed)


# --- the Swift helper ---------------------------------------------------------

def build_helper():
    src = HERE / "speechcheck.swift"
    if BIN.exists() and BIN.stat().st_mtime >= src.stat().st_mtime:
        return
    BUILD.mkdir(exist_ok=True)
    main = BUILD / "main.swift"   # top-level await needs main.swift
    shutil.copyfile(src, main)
    print("building the Swift helper (once)...", file=sys.stderr)
    subprocess.run(["xcrun", "swiftc", "-O", str(main), "-o", str(BIN)], check=True)


def helper(*args, stdin=None):
    build_helper()
    return subprocess.run([str(BIN), *args], input=stdin, text=True, check=True,
                          stdout=subprocess.PIPE).stdout


_TOK_CACHE = {}


def tokenize(lines):
    todo = [l for l in dict.fromkeys(lines) if l not in _TOK_CACHE]
    if todo:
        for row in json.loads(helper("tokenize", stdin="\n".join(todo) + "\n")):
            _TOK_CACHE[row["text"]] = row["tokens"]
    return [_TOK_CACHE.get(l, []) for l in lines]


# --- audio files --------------------------------------------------------------

def numbered_files(folder):
    """{sentence number: path} for files named 07.m4a, 7.wav, s07.aiff, 07-take2.m4a..."""
    found = {}
    for p in sorted(Path(folder).iterdir()):
        m = re.match(r"^[sS]?0*(\d+)", p.stem)
        if p.suffix.lower() in AUDIO_EXT and m and int(m.group(1)) in BY_N:
            found.setdefault(int(m.group(1)), p)
    return found


def transcribe_apple(engine, files, out):
    helper("transcribe", engine, str(out), *[str(p) for p in files])
    return json.loads(out.read_text())


def transcribe_whisper(files, out):
    cli, model = os.environ.get("WHISPER_CLI"), os.environ.get("WHISPER_MODEL")
    if not (cli and model):
        sys.exit("whisper needs WHISPER_CLI and WHISPER_MODEL (see README.md)")
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        for p in files:
            wav = Path(tmp) / (p.stem + ".wav")
            subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(p), str(wav)], check=True)
            t0 = time.monotonic()
            r = subprocess.run([cli, "-m", model, "-l", "ja", "-nt", "-np", "-t", "8", "-f", str(wav)],
                               text=True, capture_output=True)
            wall = time.monotonic() - t0
            text = "".join(l.strip() for l in r.stdout.splitlines())
            dur = float(subprocess.run(["afinfo", "-b", str(wav)], text=True, capture_output=True).stdout
                        .split(" sec")[0].split()[-1] or 0)
            rows.append({"file": p.name, "engine": "whisper", "text": text, "alternatives": [],
                         "confidence": None, "audioSeconds": dur, "wallSeconds": wall,
                         "firstResultSeconds": None, "error": r.stderr[-300:] if r.returncode else None})
            print(f"  [whisper] {p.name}: {text}", file=sys.stderr)
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    return rows


# --- scoring ------------------------------------------------------------------

def norm(text):
    return "".join(c for c in text if c not in PUNCT)


def reading(tokens):
    return "".join(t["kana"] or t["w"] for t in tokens)


def reading_on_boundaries(target, parts):
    """True if the kana `target` is a run of whole tokens: かった in 先週|かっ|た, not in 面白かっ|た."""
    if not target:
        return False
    for i in range(len(parts)):
        acc = ""
        for p in parts[i:]:
            acc += p
            if acc == target:
                return True
            if not target.startswith(acc):
                break
    return False


def gold_readings(sentence):
    """Kana reading of each labelled verb, from the typed sentence's own tokens."""
    text = sentence["text"]
    toks = tokenize([text])[0]
    out = []
    for g in sentence["verbs"]:
        a = text.index(g["surface"]); b = a + len(g["surface"])
        inside = [t for t in toks if t["s"] >= a and t["s"] + len(t["w"]) <= b]
        if sum(len(t["w"]) for t in inside) == b - a:
            out.append(reading(inside))
        else:
            out.append(reading(tokenize([g["surface"]])[0]))
    return out


def score_one(sentence, transcript):
    """Per-verb results for one transcript of one sentence."""
    import matcher
    text = re.sub(r"\s+", "", transcript)   # keep punctuation: the matcher uses it as a boundary
    toks = tokenize([text])[0] if text else []
    parts = [t["kana"] or t["w"] for t in toks]
    hits = matcher.match(text, toks) if text else []
    used = set()
    verbs = []
    for g, gread in zip(sentence["verbs"], gold_readings(sentence)):
        r = {"surface": g["surface"], "verb": g["verb"],
             "verbatim": g["surface"] in text,
             "chain": g["surface"] in text or reading_on_boundaries(gread, parts)}
        r["respelled"] = r["chain"] and not r["verbatim"]
        if g["verb"]:
            r["right_verb"] = r["full_span"] = False
            for k, (i, span, cands, chain) in enumerate(hits):
                if k in used or g["verb"] not in {c[0] for c in cands}:
                    continue
                used.add(k)
                r["right_verb"] = True
                span_read = reading([t for t in toks if i <= t["s"] < i + len(span)])
                r["full_span"] = span == g["surface"] or span_read == gread
                r["matched"] = span
                break
        verbs.append(r)
    golds = [(g["surface"], r) for g, r in zip(sentence["verbs"], gold_readings(sentence)) if g["verb"]]

    def inside_a_chain(i, span):   # e.g. もらいました split off 教えてもらいました: partial, not a false positive
        r = reading([t for t in toks if i <= t["s"] < i + len(span)])
        return any(span in gs or (r and r in gr) for gs, gr in golds)

    fp = sum(1 for k, (i, span, _, chain) in enumerate(hits)
             if k not in used and chain != "not in the app yet" and not inside_a_chain(i, span))
    return verbs, fp


def score(rows, kind):
    """Aggregate the transcripts of one engine on one source."""
    per = []
    for row in rows:
        n = int(re.match(r"^[sS]?0*(\d+)", Path(row["file"]).stem).group(1))
        s = BY_N[n]
        verbs, fp = score_one(s, row["text"] or "")
        alts_hit = any(norm(a) == norm(s["text"]) for a in row.get("alternatives") or [])
        per.append({"n": n, "typed": s["text"], "text": row["text"], "verbs": verbs, "fp": fp,
                    "exact": norm(row["text"] or "") == norm(s["text"]),
                    "lost": not all(v["chain"] for v in verbs),
                    "alt_has_typed": alts_hit,
                    "final_punct": bool(row["text"]) and row["text"].rstrip()[-1:] in "。？！?!",
                    "commas_typed": s["text"].count("、"), "commas": (row["text"] or "").count("、"),
                    "digits": bool(DIGIT.search(row["text"] or "")),
                    "confidence": row.get("confidence"), "wall": row["wallSeconds"],
                    "audio": row["audioSeconds"], "error": row.get("error")})
    allv = [v for p in per for v in p["verbs"]]
    inapp = [v for v in allv if v["verb"]]
    walls = [p["wall"] for p in per if not p["error"]]
    rtf = [p["wall"] / p["audio"] for p in per if p["audio"] and not p["error"]]
    conf = [p["confidence"] for p in per if p["confidence"] is not None]
    return {
        "sentences": len(per), "verbs": len(allv), "in_app": len(inapp),
        "exact": sum(p["exact"] for p in per),
        "chain": sum(v["chain"] for v in allv), "verbatim": sum(v["verbatim"] for v in allv),
        "respelled": sum(v["respelled"] for v in allv),
        "right_verb": sum(v.get("right_verb", False) for v in inapp),
        "full_span": sum(v.get("full_span", False) for v in inapp),
        "fp": sum(p["fp"] for p in per),
        "lost_sentences": sum(p["lost"] for p in per),
        "final_punct": sum(p["final_punct"] for p in per),
        "commas": sum(p["commas"] for p in per), "commas_typed": sum(p["commas_typed"] for p in per),
        "digits": [p["n"] for p in per if p["digits"]],
        "alt_has_typed": sum(p["alt_has_typed"] for p in per),
        "median_wall": statistics.median(walls) if walls else None,
        "max_wall": max(walls) if walls else None,
        "median_rtf": statistics.median(rtf) if rtf else None,
        "mean_conf": statistics.mean(conf) if conf else None,
        "errors": [p["n"] for p in per if p["error"]],
        "per_sentence": per,
    }


def pct(a, b):
    return f"{a}/{b} ({100 * a / b:.0f}%)" if b else "-"


def print_table(label, kind, scores):
    print(f"\n## {label} ({kind})\n")
    print("| Engine | Sentences exact | Verb chain kept (reading) | Kept verbatim | Respelled | "
          "Matcher right verb | Matcher full span | False pos. | Sentences losing a verb | "
          "Ends 。/？ | 、 (typed) | Digits in | Median s / RTF | Mean conf. |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    for eng, s in scores.items():
        lat = f"{s['median_wall']:.2f} / {s['median_rtf']:.2f}" if s["median_rtf"] is not None else "-"
        conf = f"{s['mean_conf']:.2f}" if s["mean_conf"] is not None else "-"
        print(f"| {ENGINES[eng]} | {pct(s['exact'], s['sentences'])} | {pct(s['chain'], s['verbs'])} | "
              f"{pct(s['verbatim'], s['verbs'])} | {s['respelled']} | {pct(s['right_verb'], s['in_app'])} | "
              f"{pct(s['full_span'], s['in_app'])} | {s['fp']} | {pct(s['lost_sentences'], s['sentences'])} | "
              f"{s['final_punct']}/{s['sentences']} | {s['commas']} ({s['commas_typed']}) | "
              f"{', '.join(f'#{n}' for n in s['digits']) or 'none'} | {lat} | {conf} |")
    for eng, s in scores.items():
        diffs = [p for p in s["per_sentence"] if not p["exact"]]
        if not diffs:
            continue
        print(f"\n{ENGINES[eng]}: transcripts that differ from the typed sentence\n")
        for p in diffs:
            lost = [v["surface"] for v in p["verbs"] if not v["chain"]]
            resp = [v["surface"] for v in p["verbs"] if v["respelled"]]
            note = (f"  LOST {', '.join(lost)}" if lost else "") + (f"  respelled {', '.join(resp)}" if resp else "")
            print(f"- #{p['n']:02d} {p['text'] or '(empty)'}{note}")
        if s["errors"]:
            print(f"\nerrors on: {s['errors']}")


# --- commands -----------------------------------------------------------------

def cmd_status(_):
    print(helper("status"), end="")


def cmd_install(_):
    build_helper()
    subprocess.run([str(BIN), "install"], check=True)


def cmd_script(_):
    print("# Speech check (#143): recording script\n")
    print("Read each sentence once, at your normal pace. Save one file per sentence, named by its "
          "number: `01.m4a` … `41.m4a` (Voice Memos, QuickTime or any recorder; .m4a, .wav or .aiff). "
          "Leave about half a second of silence before you start. For a retake, replace the file; "
          "a missing number is simply skipped. Don't read the numbers aloud.\n")
    for s in SENTENCES:
        print(f"{s['n']:>2}. {s['text']}  ")
    print("\nAfter recording, a native speaker marks the numbers they could *not* understand; pass them "
          "to `run --not-understood`.")


def cmd_tts(a):
    out = Path(a.out or BUILD / "audio" / f"tts-{a.voice.lower()}")
    out.mkdir(parents=True, exist_ok=True)
    for s in SENTENCES:
        f = out / f"{s['n']:02d}.aiff"
        if not f.exists():
            # a recorder always catches some silence around the speech; say doesn't
            text = f"[[slnc {a.pad}]]{s['text']}[[slnc {a.pad}]]" if a.pad else s["text"]
            subprocess.run(["say", "-v", a.voice, "-o", str(f), text], check=True)
    print(out)


def cmd_run(a):
    files = numbered_files(a.folder)
    if not files:
        sys.exit(f"no numbered audio files (01.m4a … 41.m4a) in {a.folder}")
    label = a.label or Path(a.folder).name
    dest = RESULTS / label
    dest.mkdir(parents=True, exist_ok=True)
    nu = sorted({int(x) for x in re.split(r"[,\s]+", a.not_understood or "") if x})
    meta = {"label": label, "kind": a.kind, "folder": str(Path(a.folder).resolve()),
            "not_understood": nu, "engines": a.engines.split(",")}
    (dest / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1))
    order = [files[n] for n in sorted(files)]
    print(f"{label}: {len(order)} recordings, engines {a.engines}", file=sys.stderr)
    scores = {}
    for eng in meta["engines"]:
        out = dest / f"{eng}.json"
        if not (a.reuse and out.exists()):
            if eng == "whisper":
                transcribe_whisper(order, out)
            else:
                transcribe_apple(eng, order, out)
        scores[eng] = score(json.loads(out.read_text()), a.kind)
    (dest / "score.json").write_text(json.dumps(scores, ensure_ascii=False, indent=1))
    print_table(label, a.kind, scores)
    if nu:
        print(f"\nNot understood by the native listener (left out of the decision): {nu}")


def cmd_decide(_):
    """The issue's bar: Whisper only if Apple loses the target verb or form in more than
    ~1 in 5 learner sentences a native understood, and Whisper clearly does better."""
    if not RESULTS.exists():
        sys.exit("no results yet: run `run` first")
    rows = []
    for d in sorted(RESULTS.iterdir()):
        if not (d / "score.json").exists():
            continue
        meta = json.loads((d / "meta.json").read_text())
        scores = json.loads((d / "score.json").read_text())
        for eng, s in scores.items():
            kept = [p for p in s["per_sentence"] if p["n"] not in meta["not_understood"]]
            lost = sum(p["lost"] for p in kept)
            rows.append((meta["kind"], meta["label"], eng, lost, len(kept)))
    print("| Source | Label | Engine | Sentences losing a verb/form (of those understood) |")
    print("|---|---|---|---|")
    for kind, label, eng, lost, n in rows:
        print(f"| {kind} | {label} | {ENGINES[eng]} | {pct(lost, n)} |")

    def rate(eng):
        L = [(l, n) for k, _, e, l, n in rows if k == "learner" and e == eng]
        return (sum(l for l, _ in L) / sum(n for _, n in L)) if L and sum(n for _, n in L) else None

    apple = {e: rate(e) for e in ("st", "dt")}
    whisper = rate("whisper")
    print()
    if all(v is None for v in apple.values()):
        print("Decision: NOT YET. No learner recordings. Record at least two learners (see README.md).")
        return
    best = min((v, e) for e, v in apple.items() if v is not None)
    print(f"Apple, learner speech: SpeechTranscriber {fmt(apple['st'])}, DictationTranscriber {fmt(apple['dt'])} "
          f"of understood sentences lose a verb or form (bar: more than {LOSS_BAR:.0%}).")
    if best[0] <= LOSS_BAR:
        print(f"Decision: NO WHISPER. Apple ({ENGINES[best[1]]}) stays within the bar.")
    elif whisper is None:
        print("Apple misses the bar. Run the same learner folders with --engines st,dt,whisper to finish the check.")
    elif whisper <= best[0] - CLEARLY_BETTER:
        print(f"Decision: WHISPER FALLBACK. Apple misses the bar and Whisper loses {fmt(whisper)}, "
              f"at least {CLEARLY_BETTER:.0%} points better on the same audio.")
    else:
        print(f"Decision: NO WHISPER. Apple misses the bar, but Whisper ({fmt(whisper)}) isn't clearly better "
              "on the same audio; fix it in the matcher or the UI instead.")
    print("The maintainer confirms the decision on #143.")


def fmt(v):
    return "-" if v is None else f"{v:.0%}"


def cmd_typed(_):
    """Score the typed sentences themselves: the matcher's ceiling."""
    rows = [{"file": f"{s['n']:02d}", "text": s["text"], "wallSeconds": 0, "audioSeconds": 0}
            for s in SENTENCES]
    print_table("typed text", "reference", {"typed": score(rows, "typed")})


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status", help="speech model availability on this Mac").set_defaults(f=cmd_status)
    sub.add_parser("install", help="download and reserve the ja-JP models (one-time)").set_defaults(f=cmd_install)
    sub.add_parser("script", help="print the recording script (Markdown)").set_defaults(f=cmd_script)
    t = sub.add_parser("tts", help="synthesise the 41 sentences with a macOS voice")
    t.add_argument("--voice", default="Kyoko")
    t.add_argument("--out")
    t.add_argument("--pad", type=int, default=500, help="ms of silence before and after (default 500, 0 = none)")
    t.set_defaults(f=cmd_tts)
    r = sub.add_parser("run", help="transcribe and score a folder of numbered recordings")
    r.add_argument("folder")
    r.add_argument("--kind", required=True, choices=["tts", "native", "learner"])
    r.add_argument("--label", help="results name (default: the folder name)")
    r.add_argument("--engines", default="st,dt", help="comma list of st, dt, whisper")
    r.add_argument("--not-understood", default="", help="sentence numbers a native listener couldn't understand")
    r.add_argument("--reuse", action="store_true", help="re-score saved transcripts without transcribing")
    r.set_defaults(f=cmd_run)
    sub.add_parser("decide", help="apply the Whisper decision bar to all results").set_defaults(f=cmd_decide)
    sub.add_parser("typed", help="score the typed sentences (the matcher's ceiling)").set_defaults(f=cmd_typed)
    a = p.parse_args()
    sys.path.insert(0, str(HERE))
    a.f(a)


if __name__ == "__main__":
    main()
