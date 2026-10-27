#!/usr/bin/env python3
"""Mark counters or grammar points as reviewed.

    python3 scripts/mark_reviewed.py counters hon hai --by teacher --on 2026-10-24
    python3 scripts/mark_reviewed.py grammar n-desu --by owner

Writes (or refreshes) a `review` stamp {by, on, sha256} on each named entry. The hash covers the entry's own
content, so a later edit makes `scripts/update_data.py` fail until the entry is reviewed again. Afterwards run
`make data` and `make sign-commit`: every data change is re-signed by the owner.
"""
import argparse
import datetime
import json
import re
import sys
from pathlib import Path

import update_data as ud

DATA_DIR = Path(__file__).resolve().parent.parent / "data"


def _check_args(by, on):
    if by not in ud.REVIEWERS:
        raise ValueError(f"by must be one of {list(ud.REVIEWERS)}, not {by!r}")
    if not ud.valid_iso_date(on):
        raise ValueError(f"on must be a date like 2026-10-24, not {on!r}")


def _stamp(entry, by, on, generated=()):
    return {"by": by, "on": on, "sha256": ud.review_hash(entry, generated)}


def stamp_counters(doc, ids, by, on):
    """Sets the stamp on each counter in `ids` (mutates `doc`); a missing id is a ValueError."""
    _check_args(by, on)
    entries = {entry["id"]: entry for entry in doc["counters"]}
    for counter_id in ids:
        if counter_id not in entries:
            raise ValueError(f"no counter with id {counter_id!r}")
        entries[counter_id]["review"] = _stamp(entries[counter_id], by, on, ud.COUNTER_GENERATED)


def stamp_grammar_text(text, ids, by, on):
    """Returns `text` (grammar.json) with a `"review": {...},` line right after each entry's `"id"` line.
    The hand-formatted file is otherwise left byte for byte as it was."""
    _check_args(by, on)
    entries = {entry["id"]: entry for entry in json.loads(text)["grammar"]}
    for grammar_id in ids:
        if grammar_id not in entries:
            raise ValueError(f"no grammar point with id {grammar_id!r}")
        stamp = _stamp(entries[grammar_id], by, on)
        id_line = re.compile(rf'^(?P<indent>[ \t]*)"id": "{re.escape(grammar_id)}",\n', re.MULTILINE)
        match = id_line.search(text)
        if match is None:
            raise ValueError(f"cannot find the id line of {grammar_id!r} in grammar.json")
        indent = match.group("indent")
        line = f'{indent}"review": {{ "by": "{stamp["by"]}", "on": "{stamp["on"]}", "sha256": "{stamp["sha256"]}" }},\n'
        rest = text[match.end():]
        existing = re.match(rf'{re.escape(indent)}"review": .*\n', rest)
        text = text[:match.end()] + line + (rest[existing.end():] if existing else rest)
    json.loads(text)
    return text


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("kind", choices=("counters", "grammar"))
    parser.add_argument("ids", nargs="+")
    parser.add_argument("--by", required=True, choices=ud.REVIEWERS)
    parser.add_argument("--on", default=datetime.date.today().isoformat(), help="review date (default: today)")
    parser.add_argument("--data-dir", default=str(DATA_DIR))
    args = parser.parse_args(argv)
    data_dir = Path(args.data_dir)
    try:
        if args.kind == "counters":
            path = data_dir / "counters.json"
            doc = json.loads(path.read_text(encoding="utf-8"))
            stamp_counters(doc, args.ids, args.by, args.on)
            path.write_text(ud.dump_counters(doc), encoding="utf-8")
        else:
            path = data_dir / "grammar.json"
            path.write_text(stamp_grammar_text(path.read_text(encoding="utf-8"), args.ids, args.by, args.on),
                            encoding="utf-8")
    except ValueError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"marked {', '.join(args.ids)} as reviewed by {args.by} on {args.on} in {path.name}")
    print("Next: make data, then make sign-commit (every data change is re-signed by the owner).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
