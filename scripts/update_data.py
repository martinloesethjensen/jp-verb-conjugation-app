#!/usr/bin/env python3
"""Maintainer tool for the app's published data (data/).

Run after editing data/verbs.json or data/grammar.json:

    python3 scripts/update_data.py            # rewrite files in place
    python3 scripts/update_data.py --check    # verify only; exit 1 if stale/invalid

It does four things:
  1. Fills the nd_* (んです / んだ) forms on every verb in verbs.json by
     appending to the verb's plain forms. Deterministic; safe to re-run.
  2. Fills the nine potential forms (`potential` and the eight pot_* fields)
     from each verb's class, and removes them for verbs that have none.
     Deterministic; safe to re-run.
  3. Validates data/grammar.json (hand-authored) against the schema the
     app decodes. It never generates lesson text.
  4. Recomputes the SHA-256 of both files into data/manifest.json, bumping
     a file's version (minor) when its content changed.

Standard library only.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ND_SUFFIX = "んです"
ND_CASUAL_SUFFIX = "んだ"

# (nd field, plain-form field it attaches to, suffix)
ND_FIELDS = [
    ("nd_pos", "short_pos", ND_SUFFIX),
    ("nd_neg", "short_neg", ND_SUFFIX),
    ("nd_past", "short_past", ND_SUFFIX),
    ("nd_past_neg", "short_past_neg", ND_SUFFIX),
    ("nd_casual_pos", "short_pos", ND_CASUAL_SUFFIX),
    ("nd_casual_neg", "short_neg", ND_CASUAL_SUFFIX),
    ("nd_casual_past", "short_past", ND_CASUAL_SUFFIX),
    ("nd_casual_past_neg", "short_past_neg", ND_CASUAL_SUFFIX),
]

# --- Potential form (grammar point `potential`) -----------------------------

# Where each u-verb ending moves to in the え-row. These are the nine endings
# present in the verb data; a verb ending in anything else is an error, not a
# guess.
E_ROW = {
    "う": "え", "く": "け", "ぐ": "げ", "す": "せ", "つ": "て",
    "ぬ": "ね", "ぶ": "べ", "む": "め", "る": "れ",
}

# The two irregular verbs have unrelated potential stems.
IRREGULAR_POTENTIAL = {"する": "できる", "くる": "こられる"}

# Verbs with no regular potential form. They get no potential fields at all,
# and any stale ones are removed. This is the only hand-maintained part of the
# potential step; extend it as verbs are added (for example わかる).
NO_POTENTIAL = {"ある"}

# A potential verb is itself an ichidan verb, so its other forms are the
# standard ichidan endings on its stem (the base form minus る), in JSON order.
POTENTIAL_CONJUGATIONS = [
    ("pot_masu_pos", "ます"),
    ("pot_masu_neg", "ません"),
    ("pot_masu_past", "ました"),
    ("pot_masu_past_neg", "ませんでした"),
    ("pot_te", "て"),
    ("pot_short_neg", "ない"),
    ("pot_short_past", "た"),
    ("pot_short_past_neg", "なかった"),
]

# Every field the potential step owns: the base form plus the eight above.
POTENTIAL_FIELDS = ["potential"] + [name for name, _ in POTENTIAL_CONJUGATIONS]

LEVELS = {"beginner", "intermediate"}
WORD_CLASSES = {"verb", "i-adjective", "na-adjective", "noun"}
REGISTERS = {"polite", "casual", "formal"}


def nd_forms(forms):
    """The eight んです forms for a verb's `forms` dict."""
    return {name: forms[source] + suffix for name, source, suffix in ND_FIELDS}


def apply_nd_forms(verbs_doc):
    """Set nd_* on every verb in place. Returns True if anything changed."""
    changed = False
    for verb in verbs_doc["verbs"]:
        forms = verb["forms"]
        for name, value in nd_forms(forms).items():
            if forms.get(name) != value:
                forms[name] = value
                changed = True
    return changed


def potential_base(verb):
    """The potential form (plain, present) of a verb from its class, or None
    if the verb has no potential. Raises ValueError for a class or ending the
    rules don't cover, so bad data fails loudly instead of producing a guess."""
    dict_form = verb["dict"]
    if dict_form in NO_POTENTIAL:
        return None
    kind = verb["type"]
    if kind == "ru":
        return dict_form[:-1] + "られる"
    if kind == "u":
        last = dict_form[-1]
        if last not in E_ROW:
            raise ValueError(f"{dict_form}: no え-row mapping for the u-verb ending '{last}'")
        return dict_form[:-1] + E_ROW[last] + "る"
    if kind == "irr.":
        if dict_form not in IRREGULAR_POTENTIAL:
            raise ValueError(f"{dict_form}: irregular verb with no known potential form")
        return IRREGULAR_POTENTIAL[dict_form]
    raise ValueError(f"{dict_form}: unknown verb type '{kind}'")


def potential_forms(verb):
    """All nine potential forms as {field: value}, or {} if the verb has none."""
    base = potential_base(verb)
    if base is None:
        return {}
    stem = base[:-1]
    forms = {"potential": base}
    for name, ending in POTENTIAL_CONJUGATIONS:
        forms[name] = stem + ending
    return forms


def apply_potential_forms(verbs_doc):
    """Set the nine potential fields on every verb in place, and remove them
    from verbs that have none. The script owns these fields, so a hand-set
    value is overwritten. Returns True if anything changed."""
    changed = False
    for verb in verbs_doc["verbs"]:
        forms = verb["forms"]
        wanted = potential_forms(verb)
        for name in POTENTIAL_FIELDS:
            if name in wanted:
                if forms.get(name) != wanted[name]:
                    forms[name] = wanted[name]
                    changed = True
            elif name in forms:
                del forms[name]
                changed = True
    return changed


def dump_verbs(doc):
    """Serialize verbs.json in the repo's style: 2-space indent, non-ASCII
    kept, and each example object on a single line."""
    text = json.dumps(doc, ensure_ascii=False, indent=2)
    text = re.sub(
        r'\{\n\s+("form": [^\n]+),\n\s+("jp": [^\n]+),\n\s+("en": [^\n]+)\n\s+\}',
        r"{ \1, \2, \3 }",
        text,
    )
    return text + "\n"


def validate_grammar(doc):
    """Returns a list of human-readable problems (empty when valid)."""
    errors = []
    points = doc.get("grammar")
    if not isinstance(points, list) or not points:
        return ["grammar: must be a non-empty list"]
    for key in ("version", "description"):
        if not isinstance(doc.get(key), str):
            errors.append(f"{key}: missing or not a string")

    ids = [p.get("id") for p in points]
    for dup in {i for i in ids if ids.count(i) > 1}:
        errors.append(f"duplicate id: {dup}")

    for p in points:
        pid = p.get("id", "<no id>")
        for key in ("id", "title", "summary"):
            if not isinstance(p.get(key), str) or not p[key]:
                errors.append(f"{pid}: {key} missing or empty")
        if p.get("level") not in LEVELS:
            errors.append(f"{pid}: level must be one of {sorted(LEVELS)}")
        for related in p.get("related", []):
            if related not in ids:
                errors.append(f"{pid}: related id '{related}' does not exist")
        if not isinstance(p.get("related"), list):
            errors.append(f"{pid}: related must be a list")

        usages = p.get("usages")
        if not isinstance(usages, list) or not usages:
            errors.append(f"{pid}: usages must be a non-empty list")
            usages = []
        for u in usages:
            heading = u.get("heading", "<no heading>")
            for key in ("heading", "explanation"):
                if not isinstance(u.get(key), str) or not u[key]:
                    errors.append(f"{pid}/{heading}: {key} missing or empty")
            examples = u.get("examples")
            if not isinstance(examples, list) or not examples:
                errors.append(f"{pid}/{heading}: needs at least one example")
                examples = []
            for e in examples:
                if not e.get("jp") or not e.get("en"):
                    errors.append(f"{pid}/{heading}: example needs jp and en")

        attachment = p.get("attachment")
        if not isinstance(attachment, list):
            errors.append(f"{pid}: attachment must be a list")
            attachment = []
        for a in attachment:
            if a.get("word_class") not in WORD_CLASSES:
                errors.append(f"{pid}: attachment word_class must be one of {sorted(WORD_CLASSES)}")
            for key in ("pattern", "example"):
                if not isinstance(a.get(key), str) or not a[key]:
                    errors.append(f"{pid}: attachment {key} missing or empty")

        pitfalls = p.get("pitfalls")
        if not isinstance(pitfalls, list):
            errors.append(f"{pid}: pitfalls must be a list")
            pitfalls = []
        for f in pitfalls:
            heading = f.get("heading", "<no heading>")
            for key in ("heading", "explanation"):
                if not isinstance(f.get(key), str) or not f[key]:
                    errors.append(f"{pid}/{heading}: pitfall {key} missing or empty")
            for e in f.get("examples", []):
                if not e.get("jp") or not e.get("en"):
                    errors.append(f"{pid}/{heading}: pitfall example needs jp and en")

        conjugations = p.get("conjugations")
        if not isinstance(conjugations, list):
            errors.append(f"{pid}: conjugations must be a list")
            conjugations = []
        for c in conjugations:
            if not isinstance(c.get("form"), str) or not c["form"]:
                errors.append(f"{pid}: conjugation form missing or empty")
            if c.get("register") not in REGISTERS:
                errors.append(f"{pid}: conjugation register must be one of {sorted(REGISTERS)}")
    return errors


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def bump_minor(version):
    major, minor, _patch = version.split(".")
    return f"{major}.{int(minor) + 1}.0"


def build_manifest(existing, verbs_bytes, grammar_bytes, verbs_version=None, grammar_version=None):
    """New manifest dict. A file's version is kept when its hash is
    unchanged, bumped (minor) when it changed, or forced by an explicit
    version. A grammar block that did not exist yet starts at 1.0.0."""
    verbs_hash = sha256_hex(verbs_bytes)
    grammar_hash = sha256_hex(grammar_bytes)

    old_verbs_version = existing.get("version", "1.0.0")
    if verbs_version:
        new_verbs_version = verbs_version
    elif existing.get("sha256") == verbs_hash:
        new_verbs_version = old_verbs_version
    else:
        new_verbs_version = bump_minor(old_verbs_version)

    old_grammar = existing.get("grammar")
    if grammar_version:
        new_grammar_version = grammar_version
    elif old_grammar is None:
        new_grammar_version = "1.0.0"
    elif old_grammar.get("sha256") == grammar_hash:
        new_grammar_version = old_grammar["version"]
    else:
        new_grammar_version = bump_minor(old_grammar["version"])

    return {
        "version": new_verbs_version,
        "sha256": verbs_hash,
        "grammar": {"version": new_grammar_version, "sha256": grammar_hash},
    }


def run(data_dir, check=False, verbs_version=None, grammar_version=None):
    """Returns (exit_code, messages)."""
    data_dir = Path(data_dir)
    verbs_path = data_dir / "verbs.json"
    grammar_path = data_dir / "grammar.json"
    manifest_path = data_dir / "manifest.json"
    messages = []

    grammar_bytes = grammar_path.read_bytes()
    problems = validate_grammar(json.loads(grammar_bytes))
    if problems:
        return 1, ["grammar.json is invalid:"] + [f"  - {p}" for p in problems]

    verbs_doc = json.loads(verbs_path.read_text(encoding="utf-8"))
    apply_nd_forms(verbs_doc)
    try:
        apply_potential_forms(verbs_doc)
    except ValueError as error:
        return 1, [f"cannot generate potential forms: {error}"]
    verbs_text = dump_verbs(verbs_doc)
    verbs_bytes = verbs_text.encode("utf-8")

    existing = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest = build_manifest(existing, verbs_bytes, grammar_bytes, verbs_version, grammar_version)
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"

    stale = []
    if verbs_path.read_bytes() != verbs_bytes:
        stale.append("data/verbs.json")
    if manifest_path.read_text(encoding="utf-8") != manifest_text:
        stale.append("data/manifest.json")

    if check:
        if stale:
            return 1, [f"stale: {', '.join(stale)} (run scripts/update_data.py)"]
        return 0, ["data is up to date"]

    if "data/verbs.json" in stale:
        verbs_path.write_bytes(verbs_bytes)
        messages.append("updated data/verbs.json")
    if "data/manifest.json" in stale:
        manifest_path.write_text(manifest_text, encoding="utf-8")
        messages.append(
            f"updated data/manifest.json (verbs {manifest['version']}, grammar {manifest['grammar']['version']})"
        )
    if not stale:
        messages.append("nothing to do; data is up to date")
    return 0, messages


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data-dir", default=str(Path(__file__).resolve().parent.parent / "data"))
    parser.add_argument("--check", action="store_true", help="verify only; write nothing")
    parser.add_argument("--verbs-version", help="force the verbs.json manifest version")
    parser.add_argument("--grammar-version", help="force the grammar.json manifest version")
    args = parser.parse_args(argv)
    code, messages = run(args.data_dir, args.check, args.verbs_version, args.grammar_version)
    for line in messages:
        print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
