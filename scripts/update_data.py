#!/usr/bin/env python3
"""Maintainer tool for the app's published data (data/).

Run after editing data/verbs.json or data/grammar.json:

    python3 scripts/update_data.py            # rewrite files in place
    python3 scripts/update_data.py --check    # verify only; exit 1 if stale/invalid

It does seven things:
  1. Fills the nd_* (んです / んだ) forms on every verb in verbs.json by
     appending to the verb's plain forms. Deterministic; safe to re-run.
  2. Fills the nine potential forms (`potential` and the eight pot_* fields)
     from each verb's class, and removes them for verbs that have none.
     Deterministic; safe to re-run.
  3. Validates data/grammar.json (hand-authored) against the schema the
     app decodes. It never generates lesson text.
  4. Validates data/furigana.json (hand-authored), then checks that every
     kanji in verbs.json and grammar.json has a reading in it, and that each
     verb's `kanji` spells its kana `dict` form. Missing readings fail the
     run, so new content cannot ship without furigana.
  5. Recomputes the SHA-256 of all three files into data/manifest.json,
     bumping a file's version (minor) when its content changed.
  6. Writes forms.json (into the VerbKit package), the catalogue of conjugation forms declared in
     scripts/form_catalogue.py (the one place a form id is defined), and
     checks every form id verbs.json uses against it. forms.json is bundled
     with the app, not synced, so it has no manifest entry.
  7. With --check, verifies all of the above without writing anything.

Standard library only.
"""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import form_catalogue

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

# Every field the potential step owns: the base form plus the eight above. The
# ids come from the form catalogue; the tables above only hold the endings.
POTENTIAL_FIELDS = form_catalogue.ids("verb", family="potential")

# --- Verb auxiliaries (grammar points `teiru`, `teshimau`, `temiru`, `sugiru`) ---

# Verbs that take none of the て-form auxiliaries (ている, てしまう, ておく,
# てみる): they get no such fields, and any stale ones are removed. They keep
# the stem-based forms. This is the only hand-maintained part of the step;
# extend it as verbs are added (for example いる).
NO_TE_AUXILIARIES = {"ある"}

# ている is the one auxiliary conjugated in full: the verb's て-form plus いる
# conjugated as an ichidan verb, in JSON order.
TEIRU_CONJUGATIONS = [
    ("teiru", "いる"),
    ("teiru_neg", "いない"),
    ("teiru_past", "いた"),
    ("teiru_past_neg", "いなかった"),
    ("teiru_masu_pos", "います"),
    ("teiru_masu_neg", "いません"),
    ("teiru_masu_past", "いました"),
    ("teiru_masu_past_neg", "いませんでした"),
    ("teiru_te", "いて"),
]

# Plain and polite forms of the other て-form auxiliaries.
TE_AUXILIARIES = [
    ("teshimau", "しまう"),
    ("teshimau_polite", "しまいます"),
    ("teoku", "おく"),
    ("teoku_polite", "おきます"),
    ("temiru", "みる"),
    ("temiru_polite", "みます"),
]

# The ます-stem auxiliaries: すぎる and the two i-adjective endings get a plain
# and a polite form, ながら a single form.
STEM_AUXILIARIES = [
    ("sugiru", "すぎる"),
    ("sugiru_polite", "すぎます"),
    ("yasui", "やすい"),
    ("yasui_polite", "やすいです"),
    ("nikui", "にくい"),
    ("nikui_polite", "にくいです"),
    ("nagara", "ながら"),
]

TE_AUXILIARY_FIELDS = [name for name, _ in TEIRU_CONJUGATIONS + TE_AUXILIARIES]
STEM_AUXILIARY_FIELDS = [name for name, _ in STEM_AUXILIARIES]
AUXILIARY_FIELDS = form_catalogue.ids("verb", family="auxiliary")

# --- Furigana (readings above kanji) ----------------------------------------

# A reading key may be followed by at most this many kana that select the
# reading (来ら -> こ). The app's matcher uses the same limit.
MAX_OKURIGANA_IN_KEY = 3
MAX_PROBLEMS_SHOWN = 20
KEY_PATTERN = re.compile("^[一-鿿々]+[ぁ-ゖ]{0,%d}$" % MAX_OKURIGANA_IN_KEY)
READING_PATTERN = re.compile("^[ぁ-ゖー]+$")

JLPT_LEVELS = {"N5", "N4", "N3", "N2", "N1"}
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


def masu_stem(verb):
    """The ます-stem: `masu_pos` minus ます (たべ, のみ, し, き). Raises ValueError
    if the verb has no usable `masu_pos`."""
    masu = verb["forms"].get("masu_pos")
    if not isinstance(masu, str) or not masu.endswith("ます") or masu == "ます":
        raise ValueError(f"{verb['dict']}: masu_pos must end in ます, got {masu!r}")
    return masu[:-2]


def auxiliary_forms(verb):
    """All auxiliary forms for a verb as {field: value}. Verbs in
    NO_TE_AUXILIARIES get only the stem-based ones. Raises ValueError for a
    verb without the form it needs, so bad data fails loudly."""
    stem = masu_stem(verb)
    forms = {}
    if verb["dict"] not in NO_TE_AUXILIARIES:
        te = verb["forms"].get("te")
        if not isinstance(te, str) or not te:
            raise ValueError(f"{verb['dict']}: no te form to build the auxiliaries from")
        for name, ending in TEIRU_CONJUGATIONS + TE_AUXILIARIES:
            forms[name] = te + ending
    for name, ending in STEM_AUXILIARIES:
        forms[name] = stem + ending
    return forms


def apply_auxiliary_forms(verbs_doc):
    """Set the auxiliary fields on every verb in place, and remove the ones a
    verb must not have. The script owns these fields, so a hand-set value is
    overwritten. Returns True if anything changed."""
    changed = False
    for verb in verbs_doc["verbs"]:
        forms = verb["forms"]
        wanted = auxiliary_forms(verb)
        for name in AUXILIARY_FIELDS:
            if name in wanted:
                if forms.get(name) != wanted[name]:
                    forms[name] = wanted[name]
                    changed = True
            elif name in forms:
                del forms[name]
                changed = True
    return changed


def is_kanji(char):
    """CJK ideographs plus the iteration mark 々 (same as the app's matcher)."""
    return "一" <= char <= "鿿" or char == "々"


def scan(text, readings):
    """Split `text` into (piece, reading-or-None) pairs using the reading
    dictionary, exactly as the app does: left to right, at each kanji take the
    longest key that matches from there. A key's kanji part can be any prefix
    of the kanji run, and kana after a run that ends at the key's end can
    follow it (up to MAX_OKURIGANA_IN_KEY). Non-kanji stretches are one piece
    with no reading; a kanji with no matching key is its own piece with none."""
    chars = list(text)
    n = len(chars)
    pieces = []
    plain = []

    def flush():
        if plain:
            pieces.append(("".join(plain), None))
            plain.clear()

    i = 0
    while i < n:
        if not is_kanji(chars[i]):
            plain.append(chars[i])
            i += 1
            continue
        flush()
        run_end = i
        while run_end < n and is_kanji(chars[run_end]):
            run_end += 1
        best = None  # (total length, kanji length, reading)
        for kanji_len in range(run_end - i, 0, -1):
            kanji_end = i + kanji_len
            max_suffix = min(MAX_OKURIGANA_IN_KEY, n - kanji_end) if kanji_end == run_end else 0
            for suffix in range(max_suffix, -1, -1):
                reading = readings.get("".join(chars[i:kanji_end + suffix]))
                if reading is None:
                    continue
                total = kanji_len + suffix
                if best is None or total > best[0]:
                    best = (total, kanji_len, reading)
        if best:
            pieces.append(("".join(chars[i:i + best[1]]), best[2]))
            i += best[1]
        else:
            pieces.append((chars[i], None))
            i += 1
    flush()
    return pieces


def uncovered_kanji(text, readings):
    """The kanji in `text` that have no reading, in order."""
    return [piece for piece, reading in scan(text, readings)
            if reading is None and any(is_kanji(c) for c in piece)]


def kana_reading(text, readings):
    """`text` spelled out in kana, using readings where they exist."""
    return "".join(reading or piece for piece, reading in scan(text, readings))


def validate_furigana(doc):
    """Returns a list of human-readable problems (empty when valid)."""
    if not isinstance(doc, dict):
        return ["furigana: must be an object"]
    errors = []
    for key in ("version", "description"):
        if not isinstance(doc.get(key), str):
            errors.append(f"{key}: missing or not a string")
    readings = doc.get("readings")
    if not isinstance(readings, dict) or not readings:
        errors.append("readings: must be a non-empty object")
        return errors
    for key, value in readings.items():
        if not KEY_PATTERN.match(key):
            errors.append(
                f"readings key '{key}': must be kanji, optionally followed by up to "
                f"{MAX_OKURIGANA_IN_KEY} hiragana"
            )
        if not isinstance(value, str) or not READING_PATTERN.match(value):
            errors.append(f"readings['{key}']: reading '{value}' must be non-empty hiragana")
    return errors


def strings_in(doc, path=""):
    """Every string value in a JSON document with a readable location."""
    if isinstance(doc, dict):
        for key, value in doc.items():
            yield from strings_in(value, f"{path}/{key}" if path else key)
    elif isinstance(doc, list):
        for index, value in enumerate(doc):
            yield from strings_in(value, f"{path}[{index}]")
    elif isinstance(doc, str):
        yield path, doc


def check_coverage(verbs_doc, grammar_doc, readings):
    """One problem per unread kanji per string, naming where it occurs."""
    problems = []
    for doc in (verbs_doc, grammar_doc):
        for path, text in strings_in(doc):
            for kanji in dict.fromkeys(uncovered_kanji(text, readings)):
                snippet = text if len(text) <= 40 else text[:40] + "..."
                problems.append(f'{path}: no reading for {kanji} in "{snippet}"')
    return problems


def check_verb_jlpt(verbs_doc):
    """A verb's jlpt is optional, but when present it must be N5..N1."""
    return [
        f"{v.get('dict', '<no dict>')}: jlpt must be one of {sorted(JLPT_LEVELS)}"
        for v in verbs_doc.get("verbs", [])
        if "jlpt" in v and v["jlpt"] not in JLPT_LEVELS
    ]


def check_verb_kanji(verbs_doc, readings):
    """Each verb's `kanji` must spell out its kana `dict` form."""
    problems = []
    for verb in verbs_doc["verbs"]:
        kanji = verb.get("kanji")
        if not kanji:
            continue
        got = kana_reading(kanji, readings)
        if got != verb["dict"]:
            problems.append(f"{verb['dict']}: kanji {kanji} reads as {got}, expected {verb['dict']}")
    return problems


def check_verb_forms(verbs_doc):
    """Problems with the form ids a verb or example uses: an id the catalogue
    does not know, or one that does not apply to verbs. Whether a verb has the
    forms it needs is checked by the generators and the app's data tests."""
    problems = []
    for verb in verbs_doc["verbs"]:
        name = verb.get("dict", "?")
        for key in verb.get("forms", {}):
            spec = form_catalogue.spec(key)
            if spec is None:
                problems.append(f"{name}: unknown form '{key}'")
            elif "verb" not in spec.applies_to:
                problems.append(f"{name}: form '{key}' does not apply to verbs")
        for example in verb.get("examples", []):
            spec = form_catalogue.spec(example.get("form"))
            if spec is None or "verb" not in spec.applies_to:
                problems.append(f"{name}: example uses unknown form '{example.get('form')}'")
    return problems


def dump_forms():
    """Serialize the catalogue as forms.json, in the repo's style."""
    return json.dumps(form_catalogue.to_json_doc(), ensure_ascii=False, indent=2) + "\n"


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
        if p.get("jlpt") not in JLPT_LEVELS:
            errors.append(f"{pid}: jlpt must be one of {sorted(JLPT_LEVELS)}")
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

    by_id = {p.get("id"): p for p in points}
    for p in points:
        related = p.get("related")
        if not isinstance(related, list):
            continue
        for other_id in related:
            other = by_id.get(other_id)
            if other is None or other_id == p.get("id"):
                continue  # dangling ids are reported above
            if p.get("id") not in (other.get("related") or []):
                errors.append(
                    f"{p.get('id')}: related '{other_id}', but '{other_id}' does not list "
                    f"'{p.get('id')}' back (related links must be mutual)"
                )
    return errors


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def bump_minor(version):
    major, minor, _patch = version.split(".")
    return f"{major}.{int(minor) + 1}.0"


def build_manifest(existing, verbs_bytes, grammar_bytes, verbs_version=None, grammar_version=None,
                   furigana_bytes=None, furigana_version=None):
    """New manifest dict. A file's version is kept when its hash is
    unchanged, bumped (minor) when it changed, or forced by an explicit
    version. A grammar or furigana block that did not exist yet starts at
    1.0.0. The furigana block is left out when no furigana bytes are given."""
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

    manifest = {
        "version": new_verbs_version,
        "sha256": verbs_hash,
        "grammar": {"version": new_grammar_version, "sha256": grammar_hash},
    }

    if furigana_bytes is not None:
        furigana_hash = sha256_hex(furigana_bytes)
        old_furigana = existing.get("furigana")
        if furigana_version:
            new_furigana_version = furigana_version
        elif old_furigana is None:
            new_furigana_version = "1.0.0"
        elif old_furigana.get("sha256") == furigana_hash:
            new_furigana_version = old_furigana["version"]
        else:
            new_furigana_version = bump_minor(old_furigana["version"])
        manifest["furigana"] = {"version": new_furigana_version, "sha256": furigana_hash}
    return manifest


def capped(heading, problems):
    """A problem list for the user, cut to MAX_PROBLEMS_SHOWN lines."""
    lines = [heading] + [f"  - {p}" for p in problems[:MAX_PROBLEMS_SHOWN]]
    if len(problems) > MAX_PROBLEMS_SHOWN:
        lines.append(f"  ... and {len(problems) - MAX_PROBLEMS_SHOWN} more")
    return lines


# forms.json is bundled with the app (read through Bundle.module), so it lives
# in the package, not in data/. `run` skips it when no path is given.
DEFAULT_FORMS_PATH = (
    Path(__file__).resolve().parent.parent
    / "Packages/VerbKit/Sources/VerbKit/Resources/forms.json"
)


def run(data_dir, check=False, verbs_version=None, grammar_version=None, furigana_version=None,
        forms_path=None):
    """Returns (exit_code, messages). `forms_path` is where forms.json is
    written and checked; None leaves it alone."""
    data_dir = Path(data_dir)
    verbs_path = data_dir / "verbs.json"
    grammar_path = data_dir / "grammar.json"
    furigana_path = data_dir / "furigana.json"
    manifest_path = data_dir / "manifest.json"
    messages = []

    problems = form_catalogue.problems()
    if problems:
        return 1, capped("the form catalogue is invalid:", problems)

    grammar_bytes = grammar_path.read_bytes()
    grammar_doc = json.loads(grammar_bytes)
    problems = validate_grammar(grammar_doc)
    if problems:
        return 1, ["grammar.json is invalid:"] + [f"  - {p}" for p in problems]

    furigana_bytes = furigana_path.read_bytes()
    furigana_doc = json.loads(furigana_bytes)
    problems = validate_furigana(furigana_doc)
    if problems:
        return 1, capped("furigana.json is invalid:", problems)
    readings = furigana_doc["readings"]

    verbs_doc = json.loads(verbs_path.read_text(encoding="utf-8"))
    problems = check_verb_jlpt(verbs_doc)
    if problems:
        return 1, capped("verbs.json has an invalid jlpt level:", problems)
    problems = check_verb_forms(verbs_doc)
    if problems:
        return 1, capped("verbs.json has invalid forms:", problems)
    apply_nd_forms(verbs_doc)
    try:
        apply_potential_forms(verbs_doc)
    except ValueError as error:
        return 1, [f"cannot generate potential forms: {error}"]
    try:
        apply_auxiliary_forms(verbs_doc)
    except ValueError as error:
        return 1, [f"cannot generate auxiliary forms: {error}"]
    problems = check_coverage(verbs_doc, grammar_doc, readings)
    if problems:
        return 1, capped("kanji without a reading in furigana.json:", problems)
    problems = check_verb_kanji(verbs_doc, readings)
    if problems:
        return 1, capped("a verb's kanji does not match its kana form:", problems)
    verbs_text = dump_verbs(verbs_doc)
    verbs_bytes = verbs_text.encode("utf-8")

    existing = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest = build_manifest(
        existing, verbs_bytes, grammar_bytes, verbs_version, grammar_version,
        furigana_bytes=furigana_bytes, furigana_version=furigana_version,
    )
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"

    forms_text = dump_forms()

    stale = []
    if verbs_path.read_bytes() != verbs_bytes:
        stale.append("data/verbs.json")
    if forms_path is not None:
        forms_path = Path(forms_path)
        if not forms_path.exists() or forms_path.read_text(encoding="utf-8") != forms_text:
            stale.append("forms.json")
    if manifest_path.read_text(encoding="utf-8") != manifest_text:
        stale.append("data/manifest.json")

    if check:
        if stale:
            return 1, [f"stale: {', '.join(stale)} (run scripts/update_data.py)"]
        return 0, ["data is up to date"]

    if "data/verbs.json" in stale:
        verbs_path.write_bytes(verbs_bytes)
        messages.append("updated data/verbs.json")
    if "forms.json" in stale:
        forms_path.parent.mkdir(parents=True, exist_ok=True)
        forms_path.write_text(forms_text, encoding="utf-8")
        messages.append(f"updated {forms_path.name}")
    if "data/manifest.json" in stale:
        manifest_path.write_text(manifest_text, encoding="utf-8")
        messages.append(
            f"updated data/manifest.json (verbs {manifest['version']}, grammar {manifest['grammar']['version']}, "
            f"furigana {manifest['furigana']['version']})"
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
    parser.add_argument("--furigana-version", help="force the furigana.json manifest version")
    parser.add_argument("--forms-path", default=str(DEFAULT_FORMS_PATH),
                        help="where to write the form catalogue (forms.json)")
    args = parser.parse_args(argv)
    code, messages = run(args.data_dir, args.check, args.verbs_version, args.grammar_version,
                         args.furigana_version, forms_path=args.forms_path)
    for line in messages:
        print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
