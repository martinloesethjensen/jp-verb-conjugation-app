#!/usr/bin/env python3
"""Builds data/kanji.json, the stroke order, readings and meanings of every kanji the app can show.

Coverage: every jōyō kanji (KANJIDIC2 grade 1–8) plus every kanji in the app's other published data
files. The repeat mark 々 is never an entry. Run by hand when the sources or the coverage change:

    make kanji KANJIVG=path/to/kanjivg-YYYYMMDD.xml.gz KANJIDIC=path/to/kanjidic2.xml.gz

The sources are generation-time inputs only and are never committed:
  - KanjiVG (https://kanjivg.tagaini.net), (c) Ulrich Apel, CC BY-SA 3.0: the stroke paths, copied verbatim
    in KanjiVG's 109 x 109 box, in stroke order.
  - KANJIDIC2 (https://www.edrdg.org/wiki/index.php/KANJIDIC_Project), (c) EDRDG, CC BY-SA 4.0: on and kun
    readings, the first three English meanings and the school grade (1–6, 8 for the rest of jōyō).

The output is therefore CC BY-SA too; its `license` field says so. `make data` validates the file, checks
it still covers the app's data and publishes it. The contract is
docs/superpowers/specs/2026-11-07-kanji-stroke-order-design.md.
"""

import argparse
import gzip
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SCHEMA = 1
MAX_MEANINGS = 3
JOYO_GRADES = {1, 2, 3, 4, 5, 6, 8}
LICENSE = ("Stroke paths: KanjiVG (c) Ulrich Apel, CC BY-SA 3.0. "
           "Readings and meanings: KANJIDIC2 (c) EDRDG, CC BY-SA 4.0.")
# The published files whose kanji must be covered. kanji.json itself is not one of them.
APP_DATA_FILES = ("verbs", "grammar", "counters", "words", "furigana", "forms")

KVG_NS = "{http://kanjivg.tagaini.net}"
BASE_ID = re.compile(r"^kvg:kanji_([0-9a-f]{5})$")
STROKE_ID = re.compile(r"-s(\d+)$")
KANJIVG_DATE = re.compile(r"kanjivg-(\d{8})")
# A kun reading is native Japanese, written in hiragana. KANJIDIC2 also lists a few katakana loan readings
# under ja_kun (志 シリング, 粉 デシメートル); they are units, not readings a learner should see.
KUN = re.compile(r"^-?[ぁ-ゖー]+(\.[ぁ-ゖー]+)?-?$")


def is_kanji(char):
    """A CJK unified ideograph (U+4E00–U+9FFF). 々 is deliberately not one."""
    return "一" <= char <= "鿿"


def _open(path):
    path = Path(path)
    return gzip.open(path, "rb") if path.suffix == ".gz" else path.open("rb")


def read_kanjivg(path):
    """{kanji: [d, …]} for every base entry (`kvg:kanji_XXXXX`, not the -Kaisho style variants)."""
    out = {}
    with _open(path) as handle:
        for _, elem in ET.iterparse(handle, events=("end",)):
            if elem.tag != "kanji":
                continue
            match = BASE_ID.match(elem.get("id", ""))
            if match:
                strokes = []
                for p in elem.iter("path"):
                    number = STROKE_ID.search(p.get("id", ""))
                    if number and p.get("d"):
                        strokes.append((int(number.group(1)), p.get("d")))
                if strokes:
                    out[chr(int(match.group(1), 16))] = [d for _, d in sorted(strokes)]
            elem.clear()
    return out


def read_kanjidic(path):
    """(date_of_creation, {kanji: {"grade"?, "on", "kun", "meanings"}})."""
    created = ""
    entries = {}
    with _open(path) as handle:
        for _, elem in ET.iterparse(handle, events=("end",)):
            if elem.tag == "date_of_creation":
                created = (elem.text or "").strip()
            elif elem.tag == "character":
                literal = elem.findtext("literal")
                entry = {}
                grade = elem.findtext("misc/grade")
                if grade and int(grade) in JOYO_GRADES:
                    entry["grade"] = int(grade)
                readings = elem.findall("reading_meaning/rmgroup/reading")
                entry["on"] = [r.text for r in readings if r.get("r_type") == "ja_on" and r.text]
                entry["kun"] = [r.text for r in readings if r.get("r_type") == "ja_kun" and r.text and KUN.match(r.text)]
                meanings = [m.text for m in elem.findall("reading_meaning/rmgroup/meaning")
                            if m.get("m_lang") is None and m.text]
                entry["meanings"] = meanings[:MAX_MEANINGS]
                if literal and literal not in entries:
                    entries[literal] = entry
                elem.clear()
    return created, entries


def app_kanji(data_dir):
    """Every kanji in the app's published data files (not kanji.json), without 々."""
    found = set()
    for name in APP_DATA_FILES:
        path = Path(data_dir) / f"{name}.json"
        if path.exists():
            found.update(c for c in path.read_text(encoding="utf-8") if is_kanji(c))
    return found


def build(kanjivg_path, kanjidic_path, data_dir):
    """The kanji.json document. Exits naming every wanted kanji a source lacks."""
    strokes = read_kanjivg(kanjivg_path)
    created, dictionary = read_kanjidic(kanjidic_path)
    joyo = {k for k, e in dictionary.items() if "grade" in e and is_kanji(k)}
    wanted = joyo | app_kanji(data_dir)
    missing = sorted(k for k in wanted if k not in strokes or k not in dictionary)
    if missing:
        detail = ", ".join(f"{k} ({'KanjiVG' if k not in strokes else 'KANJIDIC2'})" for k in missing)
        sys.exit(f"build_kanji: no source entry for {len(missing)} kanji: {detail}")
    date = KANJIVG_DATE.search(Path(kanjivg_path).name)
    kanji = {}
    for k in sorted(wanted):
        entry = {"strokes": strokes[k]}
        entry.update(dictionary[k])
        kanji[k] = entry
    return {
        "schema": SCHEMA,
        "sources": {"kanjivg": date.group(1) if date else "unknown", "kanjidic2": created},
        "license": LICENSE,
        "kanji": kanji,
    }


def dumps(doc):
    return json.dumps(doc, ensure_ascii=False, indent=1) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--kanjivg", required=True, help="kanjivg-YYYYMMDD.xml(.gz)")
    parser.add_argument("--kanjidic", required=True, help="kanjidic2.xml(.gz)")
    parser.add_argument("--data-dir", default=str(Path(__file__).resolve().parent.parent / "data"))
    args = parser.parse_args(argv)
    doc = build(args.kanjivg, args.kanjidic, args.data_dir)
    out = Path(args.data_dir) / "kanji.json"
    text = dumps(doc)
    out.write_text(text, encoding="utf-8")
    print(f"Wrote {out}: {len(doc['kanji'])} kanji, {len(text.encode('utf-8')) / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
