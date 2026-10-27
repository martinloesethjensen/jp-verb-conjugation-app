#!/usr/bin/env python3
"""Give every reviewable item in data/ a stable id (see stable_ids.py).

    python3 scripts/assign_ids.py [--data-dir DIR]

Adds an id to each example sentence, grammar usage, pitfall and counter thing that has none; existing ids are
kept. verbs.json and counters.json are rewritten by their usual dumpers; the hand-formatted grammar.json only
gains the id text and is otherwise left byte for byte as it was. Afterwards run `make data` and
`make sign-commit`: every data change is re-signed by the owner.
"""
import argparse
import json
import re
import sys
from pathlib import Path

import stable_ids
import update_data as ud

DATA_DIR = Path(__file__).resolve().parent.parent / "data"

ONE_LINE_EXAMPLE = re.compile(r'^(?P<indent>\s*)\{ "jp": ')
OPEN_BRACE = re.compile(r"^\s*\{$")
HEADING = re.compile(r'^(?P<indent>\s*)"heading": ')


def _taken(dataset, doc):
    return {item["id"] for _, item in stable_ids.id_slots(dataset, doc) if isinstance(item.get("id"), str)}


def assign_json(dataset, doc):
    """Gives every slot in `doc` without an id a new one, as its first key. Returns how many were added."""
    taken = _taken(dataset, doc)
    added = 0
    for _, item in stable_ids.id_slots(dataset, doc):
        if "id" in item:
            continue
        rest = dict(item)
        item.clear()
        item["id"] = stable_ids.new_id(taken)
        item.update(rest)
        added += 1
    return added


def assign_grammar_text(text):
    """Returns (grammar.json text with an id on every usage, pitfall and example, number added). Raises
    ValueError, and changes nothing, when an object is laid out in a way this cannot place an id in."""
    taken = _taken("grammar", json.loads(text))
    lines = text.split("\n")
    out, added = [], 0
    for index, line in enumerate(lines):
        if ONE_LINE_EXAMPLE.match(line):
            line = line.replace("{ ", f'{{ "id": "{stable_ids.new_id(taken)}", ', 1)
            added += 1
        else:
            heading = HEADING.match(line)
            if heading and index > 0 and OPEN_BRACE.match(lines[index - 1]):
                out.append(f'{heading.group("indent")}"id": "{stable_ids.new_id(taken)}",')
                added += 1
        out.append(line)
    result = "\n".join(out)
    problems = stable_ids.check_stable_ids("grammar", json.loads(result))
    if problems:
        raise ValueError("cannot place an id in grammar.json for: " + "; ".join(problems))
    return result, added


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", type=Path, default=DATA_DIR)
    args = parser.parse_args(argv)

    verbs_path, counters_path, grammar_path = (args.data_dir / f"{name}.json"
                                               for name in ("verbs", "counters", "grammar"))
    try:
        grammar_text, grammar_added = assign_grammar_text(grammar_path.read_text(encoding="utf-8"))
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    verbs = json.loads(verbs_path.read_text(encoding="utf-8"))
    verbs_added = assign_json("verbs", verbs)
    counters = json.loads(counters_path.read_text(encoding="utf-8"))
    counters_added = assign_json("counters", counters)

    grammar_path.write_text(grammar_text, encoding="utf-8")
    verbs_path.write_text(ud.dump_verbs(verbs), encoding="utf-8")
    counters_path.write_text(ud.dump_counters(counters), encoding="utf-8")
    print(f"verbs.json: {verbs_added} ids added")
    print(f"grammar.json: {grammar_added} ids added")
    print(f"counters.json: {counters_added} ids added")
    print("Now run `make data`, then `make sign-commit`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
