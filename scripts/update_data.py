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
     Likewise the eight other conjugations (volitional, passive, causative,
     causative-passive, ば and たら conditionals, imperative, たい).
  3. Validates data/grammar.json (hand-authored) against the schema the
     app decodes. It never generates lesson text.
  4. Validates data/furigana.json (hand-authored), then checks that every
     kanji in verbs.json and grammar.json has a reading in it, and that each
     verb's `kanji` spells its kana `dict` form. Missing readings fail the
     run, so new content cannot ship without furigana.
  4b. Generates the forms of every adjective and noun in data/words.json
     (hand-authored apart from `forms`) and checks its fields and furigana.
  5. Recomputes the SHA-256 of all four files into data/manifest.json,
     bumping a file's version (minor) when its content changed.
  6. Writes forms.json (into the VerbKit package), the catalogue of conjugation forms declared in
     scripts/form_catalogue.py (the one place a form id is defined), and
     checks every form id verbs.json uses against it. forms.json is bundled
     with the app, not synced, so it has no manifest entry.
  7. With --check, verifies all of the above without writing anything.

Every manifest change must be re-signed (scripts/sign_manifest.py sign): the app
refuses a manifest whose signature does not match its exact bytes. --ref TAG pins the
entries to that release tag; see docs/security/data-signing.md for the release steps.

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

# --- Other conjugations: volitional, passive, causative, causative-passive,
# conditionals (ば / たら), imperative and たい ---------------------------------

A_ROW = {"う": "わ", "く": "か", "ぐ": "が", "す": "さ", "つ": "た", "ぬ": "な", "ぶ": "ば", "む": "ま", "る": "ら"}
I_ROW = {"う": "い", "く": "き", "ぐ": "ぎ", "す": "し", "つ": "ち", "ぬ": "に", "ぶ": "び", "む": "み", "る": "り"}
O_ROW = {"う": "お", "く": "こ", "ぐ": "ご", "す": "そ", "つ": "と", "ぬ": "の", "ぶ": "ぼ", "む": "も", "る": "ろ"}

# Every field this step owns, in JSON order. The ids come from the form catalogue;
# IRREGULAR_OTHER_FORMS below lists its spellings in the same order.
OTHER_FORM_FIELDS = form_catalogue.ids("verb", family="other")

# Irregular verbs, spelled out: only する and くる.
IRREGULAR_OTHER_FORMS = {
    "する": ["しよう", "される", "させる", "させられる", "すれば", "したら", "しろ", "したい"],
    "くる": ["こよう", "こられる", "こさせる", "こさせられる", "くれば", "きたら", "こい", "きたい"],
}

# Verbs that only have some of these forms; the rest are removed. The existential ある
# has no passive, causative or imperative. Extend as verbs are added.
PARTIAL_OTHER_FORMS = {"ある": {"volitional", "conditional_ba", "conditional_tara", "tai"}}


def other_forms(verb):
    """The eight other conjugations as {field: value}, built from the verb's class and its
    plain past (for たら). Raises ValueError for a class or ending the rules don't cover."""
    dict_form = verb["dict"]
    kind = verb["type"]
    past = verb["forms"].get("short_past")
    if not isinstance(past, str) or not past:
        raise ValueError(f"{dict_form}: no short_past to build the たら form from")
    if kind == "irr.":
        if dict_form not in IRREGULAR_OTHER_FORMS:
            raise ValueError(f"{dict_form}: irregular verb with no known conjugations")
        values = dict(zip(OTHER_FORM_FIELDS, IRREGULAR_OTHER_FORMS[dict_form]))
    elif kind == "ru":
        stem = dict_form[:-1]
        values = {
            "volitional": stem + "よう", "passive": stem + "られる", "causative": stem + "させる",
            "causative_passive": stem + "させられる", "conditional_ba": stem + "れば",
            "conditional_tara": past + "ら", "imperative": stem + "ろ", "tai": stem + "たい",
        }
    elif kind == "u":
        last = dict_form[-1]
        if last not in E_ROW:
            raise ValueError(f"{dict_form}: no conjugation rules for the u-verb ending '{last}'")
        stem = dict_form[:-1]
        values = {
            "volitional": stem + O_ROW[last] + "う", "passive": stem + A_ROW[last] + "れる",
            "causative": stem + A_ROW[last] + "せる", "causative_passive": stem + A_ROW[last] + "せられる",
            "conditional_ba": stem + E_ROW[last] + "ば", "conditional_tara": past + "ら",
            "imperative": stem + E_ROW[last], "tai": stem + I_ROW[last] + "たい",
        }
        if dict_form == "ある":
            values["tai"] = "ありたい"
            values["volitional"] = "あろう"
    else:
        raise ValueError(f"{dict_form}: unknown verb type '{kind}'")
    keep = PARTIAL_OTHER_FORMS.get(dict_form)
    return {name: value for name, value in values.items() if keep is None or name in keep}


def apply_other_forms(verbs_doc):
    """Set the eight fields on every verb in place and remove the ones a verb must not have.
    The script owns these fields. Returns True if anything changed."""
    changed = False
    for verb in verbs_doc["verbs"]:
        forms = verb["forms"]
        wanted = other_forms(verb)
        for name in OTHER_FORM_FIELDS:
            if name in wanted:
                if forms.get(name) != wanted[name]:
                    forms[name] = wanted[name]
                    changed = True
            elif name in forms:
                del forms[name]
                changed = True
    return changed


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


def check_coverage(verbs_doc, grammar_doc, readings, *extra_docs):
    """One problem per unread kanji per string, naming where it occurs."""
    problems = []
    for doc in (verbs_doc, grammar_doc, *extra_docs):
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


# --- Adjectives and nouns (words.json) ---------------------------------------

WORD_FILE_CLASSES = ("i-adjective", "na-adjective", "noun")
# The building blocks a grammar rule attaches to (grammar.json `slots`).
SLOTS = ("plain", "plainNeg", "plainPast", "plainPastNeg", "stem", "te")
# いい and its compounds conjugate from よい. An explicit list: かわいい also ends in いい
# but is regular (かわいくない).
II_ADJECTIVES = {"いい", "かっこいい"}


def word_forms(word):
    """The generated forms of an adjective or noun: the catalogue's forms for its class in
    catalogue order, then `stem` (a slot form the grammar patterns attach to, not a
    catalogue form). Raises ValueError for a class words.json does not hold or a
    malformed word."""
    cls, d = word.get("class"), word.get("dict", "")
    if cls == "i-adjective":
        if not d.endswith("い") or len(d) < 2:
            raise ValueError(f"{d}: an い-adjective must end in い")
        base = d[:-2] + "よ" if d in II_ADJECTIVES else d[:-1]
        forms = {"short_pos": d, "short_neg": base + "くない", "short_past": base + "かった",
                 "short_past_neg": base + "くなかった", "te": base + "くて", "stem": base}
    elif cls in ("na-adjective", "noun"):
        if not d:
            raise ValueError("a word needs a dict form")
        forms = {"short_pos": d + "だ", "short_neg": d + "じゃない", "short_past": d + "だった",
                 "short_past_neg": d + "じゃなかった", "te": d + "で"}
        if cls == "na-adjective":
            forms["stem"] = d
    else:
        raise ValueError(f"{d}: class must be one of {WORD_FILE_CLASSES}, got {cls!r}")
    order = form_catalogue.ids(cls) + ["stem"]
    return {key: forms[key] for key in order if key in forms}


def apply_word_forms(words_doc):
    """Set every word's `forms` (the script owns them). Returns True if anything changed."""
    changed = False
    for word in words_doc["words"]:
        wanted = word_forms(word)
        if word.get("forms") != wanted:
            word["forms"] = wanted
            changed = True
    return changed


def check_words(words_doc, readings):
    """Problems with the hand-written fields of words.json."""
    problems, seen = [], set()
    for word in words_doc.get("words", []):
        d = word.get("dict", "<no dict>")
        key = (word.get("class"), d)
        if key in seen:
            problems.append(f"{d}: duplicate word")
        seen.add(key)
        if word.get("class") not in WORD_FILE_CLASSES:
            problems.append(f"{d}: class must be one of {WORD_FILE_CLASSES}")
        if not isinstance(word.get("meaning"), str) or not word["meaning"]:
            problems.append(f"{d}: meaning missing or empty")
        if "jlpt" in word and word["jlpt"] not in JLPT_LEVELS:
            problems.append(f"{d}: jlpt must be one of {sorted(JLPT_LEVELS)}")
        kanji = word.get("kanji")
        if kanji:
            got = kana_reading(kanji, readings)
            if got != d:
                problems.append(f"{d}: kanji {kanji} reads as {got}, expected {d}")
    return problems


def dump_words(doc):
    """Serialize words.json: 2-space indent, non-ASCII kept, each word on one line."""
    lines = [json.dumps(word, ensure_ascii=False) for word in doc["words"]]
    head = {key: value for key, value in doc.items() if key != "words"}
    text = json.dumps(head, ensure_ascii=False, indent=2)[:-2]
    body = ",\n".join(f"    {line}" for line in lines)
    return f'{text},\n  "words": [\n{body}\n  ]\n}}\n' if lines else f'{text},\n  "words": []\n}}\n'


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
            slots = a.get("slots")
            if slots is not None:
                if not isinstance(slots, list) or not slots or any(slot not in SLOTS for slot in slots):
                    errors.append(f"{pid}: attachment slots must be a non-empty list of {list(SLOTS)}")
                    slots = []
                if a.get("word_class") == "noun" and "stem" in slots:
                    errors.append(f"{pid}: a noun has no stem")
            if a.get("da_to_na"):
                if a.get("word_class") not in ("na-adjective", "noun") or "plain" not in (slots or []):
                    errors.append(f"{pid}: da_to_na needs a na-adjective or noun rule with the plain slot")
            if "then" in a:
                if not isinstance(a["then"], str) or not a["then"]:
                    errors.append(f"{pid}: attachment then must be a non-empty string")
                if slots is None:
                    errors.append(f"{pid}: attachment then needs slots")

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

        for c in p.get("contrasts", []):
            for key in ("pattern", "explanation"):
                if not isinstance(c.get(key), str) or not c[key]:
                    errors.append(f"{pid}: contrast {key} missing or empty")
            if c.get("id") is not None and c["id"] not in ids:
                errors.append(f"{pid}: contrast id '{c['id']}' does not exist")
            for e in c.get("examples", []):
                if not e.get("jp") or not e.get("en"):
                    errors.append(f"{pid}: contrast example needs jp and en")

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


REF_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def valid_ref(text):
    """argparse type: a release tag the app accepts (it ends up in a URL path)."""
    if not REF_PATTERN.match(text):
        raise argparse.ArgumentTypeError("a tag may use letters, digits, '.', '_' and '-' only (max 64, start with a letter or digit)")
    return text


def entry_ref(old, new_hash, ref):
    """The `ref` for a manifest entry. An explicit ref wins. Otherwise the old one is kept only
    while the file's content is unchanged: a tag made before an edit does not contain the edit, so
    keeping it would pin the app to stale data (and fail its hash check)."""
    if ref:
        return ref
    if old and old.get("sha256") == new_hash and old.get("ref"):
        return old["ref"]
    return None


def with_ref(entry, ref):
    if ref:
        entry["ref"] = ref
    return entry


def build_manifest(existing, verbs_bytes, grammar_bytes, verbs_version=None, grammar_version=None,
                   furigana_bytes=None, furigana_version=None, ref=None, words_bytes=None, words_version=None):
    """New manifest dict. A file's version is kept when its hash is
    unchanged, bumped (minor) when it changed, or forced by an explicit
    version. A grammar or furigana block that did not exist yet starts at
    1.0.0. The furigana block is left out when no furigana bytes are given.

    `ref` pins every entry to that release tag; see `entry_ref`."""
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

    manifest = with_ref({"version": new_verbs_version, "sha256": verbs_hash}, entry_ref(existing, verbs_hash, ref))
    manifest["grammar"] = with_ref(
        {"version": new_grammar_version, "sha256": grammar_hash}, entry_ref(old_grammar, grammar_hash, ref)
    )

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
        manifest["furigana"] = with_ref(
            {"version": new_furigana_version, "sha256": furigana_hash}, entry_ref(old_furigana, furigana_hash, ref)
        )
    if words_bytes is not None:
        words_hash = sha256_hex(words_bytes)
        old_words = existing.get("words")
        if words_version:
            new_words_version = words_version
        elif old_words is None:
            new_words_version = "1.0.0"
        elif old_words.get("sha256") == words_hash:
            new_words_version = old_words["version"]
        else:
            new_words_version = bump_minor(old_words["version"])
        manifest["words"] = with_ref(
            {"version": new_words_version, "sha256": words_hash}, entry_ref(old_words, words_hash, ref)
        )
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
        forms_path=None, ref=None, words_version=None):
    """Returns (exit_code, messages). `forms_path` is where forms.json is
    written and checked; None leaves it alone. `ref` pins the manifest entries
    to a release tag."""
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
    try:
        apply_other_forms(verbs_doc)
    except ValueError as error:
        return 1, [f"cannot generate the other conjugations: {error}"]
    words_path = data_dir / "words.json"
    words_doc = json.loads(words_path.read_text(encoding="utf-8")) if words_path.exists() else None
    words_bytes = None
    if words_doc is not None:
        problems = check_words(words_doc, readings)
        if problems:
            return 1, capped("words.json is invalid:", problems)
        try:
            apply_word_forms(words_doc)
        except ValueError as error:
            return 1, [f"cannot generate word forms: {error}"]
        words_bytes = dump_words(words_doc).encode("utf-8")
    problems = check_coverage(verbs_doc, grammar_doc, readings, *([words_doc] if words_doc else []))
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
        furigana_bytes=furigana_bytes, furigana_version=furigana_version, ref=ref,
        words_bytes=words_bytes, words_version=words_version,
    )
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"

    forms_text = dump_forms()

    stale = []
    if verbs_path.read_bytes() != verbs_bytes:
        stale.append("data/verbs.json")
    if words_bytes is not None and words_path.read_bytes() != words_bytes:
        stale.append("data/words.json")
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
    if "data/words.json" in stale:
        words_path.write_bytes(words_bytes)
        messages.append("updated data/words.json")
    if "forms.json" in stale:
        forms_path.parent.mkdir(parents=True, exist_ok=True)
        forms_path.write_text(forms_text, encoding="utf-8")
        messages.append(f"updated {forms_path.name}")
    if "data/manifest.json" in stale:
        manifest_path.write_text(manifest_text, encoding="utf-8")
        messages.append(
            f"updated data/manifest.json (verbs {manifest['version']}, grammar {manifest['grammar']['version']}, "
            f"furigana {manifest['furigana']['version']}"
            + (f", words {manifest['words']['version']}" if "words" in manifest else "") + ")"
        )
        messages.append("the manifest changed: re-sign it with scripts/sign_manifest.py sign")
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
    parser.add_argument("--words-version", help="force the words.json manifest version")
    parser.add_argument("--forms-path", default=str(DEFAULT_FORMS_PATH),
                        help="where to write the form catalogue (forms.json)")
    parser.add_argument("--ref", type=valid_ref, help="release tag the app fetches the data files from (see docs/security/data-signing.md)")
    args = parser.parse_args(argv)
    code, messages = run(args.data_dir, args.check, args.verbs_version, args.grammar_version,
                         args.furigana_version, forms_path=args.forms_path, ref=args.ref,
                         words_version=args.words_version)
    for line in messages:
        print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
