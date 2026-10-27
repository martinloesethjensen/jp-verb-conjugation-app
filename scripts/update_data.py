#!/usr/bin/env python3
"""Maintainer tool for the app's published data (data/).

Run after editing data/verbs.json or data/grammar.json:

    python3 scripts/update_data.py            # rewrite files in place
    python3 scripts/update_data.py --check    # verify only; exit 1 if stale/invalid

It does eight things:
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
  4c. Generates the readings, `changed` keys and quiz `distractors` of every counter in data/counters.json
      (hand-authored apart from `readings`, `changed` and `distractors`), checks its fields,
      groups and furigana, and that every counted word in an example reads as
      its counter says.
  5. Recomputes the SHA-256 of every published file into data/manifest.json,
     bumping a file's version (minor) when its content changed.
  6. Writes data/forms.json, the catalogue of conjugation forms declared in
     scripts/form_catalogue.py (the one place a form id is defined), and
     checks every form id verbs.json uses against it. forms.json is published
     data like the others: it has a manifest entry, so manifest.sig covers it
     and apps sync it. The app also bundles it as an offline fallback; this
     script writes that copy too (byte for byte the same, plus
     forms.manifest.json with its version and hash), so scripts/form_catalogue.py
     stays the one source and --check fails if the copies drift.
  7. With --check, verifies all of the above without writing anything.
  8. Checks verb ids: a verb's id is its `dict` unless it has an explicit `id` (`きる:切る`, only
     where two verbs are spelled the same in kana). Ids must be unique, and no id published on
     origin/main may disappear or change (--published-ref; skipped when that ref is not available).
     See docs/superpowers/specs/2026-10-17-verb-id-scheme-design.md.

Every manifest change must be re-signed (scripts/sign_manifest.py sign): the app
refuses a manifest whose signature does not match its exact bytes. --ref TAG pins the
entries to that release tag; see docs/security/data-signing.md for the release steps.

Standard library only.
"""
import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

import form_catalogue
from stable_ids import check_stable_ids, loads as loads_without_duplicate_keys

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
# potential step; extend it as verbs are added. わかる is already potential in
# meaning (わかれる reads as 分かれる), つかれる is not something you choose to do,
# and しれる is mostly heard in しれない / かもしれない. できる already means "can"
# (×できられる). みえる, きこえる, あく (開く) and ふる (降る) happen by themselves, so
# "can be seen" and the like make no sense (あける would also read as 開ける). くれる has
# no potential (×くれられる); people say もらえる instead.
NO_POTENTIAL = {"ある", "わかる", "しる", "つかれる", "できる", "みえる", "きこえる", "あく", "ふる", "くれる"}

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

# Every field this step owns, in JSON order. The ids come from the form catalogue.
OTHER_FORM_FIELDS = form_catalogue.ids("verb", family="other")

# The eight textbook conjugations `other_forms` builds from the verb's class.
# IRREGULAR_OTHER_FORMS below lists their spellings in this order. The remaining fields
# (causative_passive_short and the everyday forms) come from `extra_forms`.
BASE_OTHER_FIELDS = (
    "volitional", "passive", "causative", "causative_passive",
    "conditional_ba", "conditional_tara", "imperative", "tai",
)

# Irregular verbs, spelled out: only する and くる.
IRREGULAR_OTHER_FORMS = {
    "する": ["しよう", "される", "させる", "させられる", "すれば", "したら", "しろ", "したい"],
    "くる": ["こよう", "こられる", "こさせる", "こさせられる", "くれば", "きたら", "こい", "きたい"],
}

# Verbs that only have some of these forms; the rest are removed. Extend as verbs are added.
# - ある: no passive, causative or imperative.
# - わかる, つかれる: not volitional, so no volitional or imperative (つかれろ, わかれ), and
#   no passive. わからせる / つかれさせる are in common use and stay.
# - しる: no volitional or imperative. The passive stays (しられている); the long
#   causative-passive しらせられる is not used (people say しらされる).
# - おわる: the passive おわられる only reads as the honorific, so it is left out.
# - なる: no passive (なられる only reads as the honorific) and no causative (people say
#   医者にさせる, not ならせる), so no causative-passive either.
# - くれる: only the ば and たら conditionals and the imperative, which is irregular (くれ, see
#   IRREGULAR_IMPERATIVE). You cannot plan, want or be made to give to yourself.
# - できる, みえる, きこえる, あく (開く): not volitional, so only the ば and たら conditionals
#   (できれば, 見えたら). あく's passive あかれる and causative あかせる are not used.
# - おくれる: like つかれる, not volitional: no volitional or imperative (おくれろ), and no passive.
#   おくれさせる (to delay something) stays.
# - ふる (降る): no volitional, imperative or たい. The passive stays (雨に降られた, "caught in
#   the rain") and so does the causative (雨を降らせる); the causative-passive does not.
# - つく (着く): no passive or causative (つかせる reads as 付かせる / 落ち着かせる).
PARTIAL_OTHER_FORMS = {
    "ある": {"volitional", "conditional_ba", "conditional_tara", "tai"},
    "わかる": {"causative", "causative_passive", "conditional_ba", "conditional_tara", "tai"},
    "しる": {"passive", "causative", "conditional_ba", "conditional_tara", "tai"},
    "つかれる": {"causative", "conditional_ba", "conditional_tara"},
    "おわる": {"volitional", "causative", "causative_passive", "conditional_ba", "conditional_tara",
             "imperative", "tai"},
    "なる": {"volitional", "conditional_ba", "conditional_tara", "imperative", "tai"},
    "くれる": {"conditional_ba", "conditional_tara", "imperative"},
    "できる": {"conditional_ba", "conditional_tara"},
    "みえる": {"conditional_ba", "conditional_tara"},
    "きこえる": {"conditional_ba", "conditional_tara"},
    "あく": {"conditional_ba", "conditional_tara"},
    "おくれる": {"causative", "conditional_ba", "conditional_tara"},
    "ふる": {"passive", "causative", "conditional_ba", "conditional_tara"},
    "つく": {"volitional", "conditional_ba", "conditional_tara", "imperative", "tai"},
}

# Verbs whose imperative breaks the rule for their class. くれる is a ru-verb, but its imperative
# is くれ, not ×くれろ.
IRREGULAR_IMPERATIVE = {"くれる": "くれ"}


def other_forms(verb):
    """The eight textbook conjugations as {field: value}, built from the verb's class and its
    plain past (for たら). Raises ValueError for a class or ending the rules don't cover."""
    dict_form = verb["dict"]
    kind = verb["type"]
    past = verb["forms"].get("short_past")
    if not isinstance(past, str) or not past:
        raise ValueError(f"{dict_form}: no short_past to build the たら form from")
    if kind == "irr.":
        if dict_form not in IRREGULAR_OTHER_FORMS:
            raise ValueError(f"{dict_form}: irregular verb with no known conjugations")
        values = dict(zip(BASE_OTHER_FIELDS, IRREGULAR_OTHER_FORMS[dict_form]))
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
    if dict_form in IRREGULAR_IMPERATIVE:
        values["imperative"] = IRREGULAR_IMPERATIVE[dict_form]
    keep = PARTIAL_OTHER_FORMS.get(dict_form)
    return {name: value for name, value in values.items() if keep is None or name in keep}


# Forms that only make sense when another form exists: ましょう needs a volitional verb, and
# the negative imperative and なさい need an imperative. Without them the verb gets none
# (ある, わかる, しる, つかれる, おわる keep their exclusions). The short causative-passive
# needs the causative, so おわる gets none; しる does get しらされる.
EXTRA_NEEDS = {
    "masu_volitional": "volitional",
    "neg_imperative": "imperative",
    "nasai": "imperative",
    "causative_passive_short": "causative",
}


# Forms the rules would build but nobody says for a particular verb, so they are left out.
# Extend this as verbs are added (see also PARTIAL_OTHER_FORMS for the base conjugations).
# - しぬ: しになさい is not said, and neither is the short causative-passive しなされる.
#   しぬな ("don't die") is natural and stays. The imperative しね is a harsh insult; the verb's
#   note says so, and the form stays for reference.
# - おわる: おわりなさい and おわるな are not said (the event ends by itself). おわりましょう is.
# - くれる: ×くれなさい is not said, and くれるな ("don't give me") is literary at best. The
#   imperative くれ stays.
# - ふる (降る): the short causative-passive ふらされる is not said.
EXTRA_EXCLUDED = {
    "しぬ": {"nasai", "causative_passive_short"},
    "おわる": {"nasai", "neg_imperative"},
    "くれる": {"nasai", "neg_imperative"},
    "ふる": {"causative_passive_short"},
}


def extra_forms(verb, kept):
    """The forms beyond the eight conjugations, as {field: value}: the short causative-passive,
    and the everyday N5/N4 forms built from the verb's authored ます, て, plain and ない forms.
    `kept` is the set of base forms the verb has, which decides the ones in EXTRA_NEEDS.
    Raises ValueError for a verb missing a form they are built from."""
    dict_form = verb["dict"]
    forms = verb["forms"]
    for name in ("masu_pos", "te", "short_pos", "short_neg"):
        if not isinstance(forms.get(name), str) or not forms[name]:
            raise ValueError(f"{dict_form}: no {name} to build the everyday forms from")
    te = forms["te"]
    if te[-1] not in "てで":
        raise ValueError(f"{dict_form}: te form must end in て or で, got {te!r}")
    negative = forms["short_neg"]
    if not negative.endswith("ない"):
        raise ValueError(f"{dict_form}: short_neg must end in ない, got {negative!r}")
    base = negative[:-2]  # たべ, の ま, "" for ある (ない)
    plain = forms["short_pos"]
    values = {
        "masu_volitional": masu_stem(verb) + "ましょう",
        "neg_te": negative + "で",
        "nakute": base + "なくて",
        "te_mo_ii": te + "もいい",
        "te_wa_ikenai": te + "はいけない",
        "te_cha_dame": te[:-1] + ("ちゃ" if te[-1] == "て" else "じゃ") + "だめ",
        "nakereba_naranai": base + "なければならない",
        "nakute_wa_ikenai": base + "なくてはいけない",
        "nakya": base + "なきゃ",
        "nakucha": base + "なくちゃ",
        "nakute_mo_ii": base + "なくてもいい",
        "neg_imperative": plain + "な",
        "nasai": masu_stem(verb) + "なさい",
        "conditional_to": plain + "と",
        "conditional_nara": plain + "なら",
    }
    # Only godan verbs have the short causative-passive (のまされる), and not す-verbs:
    # はなさせられる, never ×はなさされる. Ichidan verbs, する and くる have no short form.
    if verb["type"] == "u" and dict_form[-1] in A_ROW and dict_form[-1] != "す":
        values["causative_passive_short"] = dict_form[:-1] + A_ROW[dict_form[-1]] + "される"
    excluded = EXTRA_EXCLUDED.get(dict_form, ())
    return {
        name: value for name, value in values.items()
        if name not in excluded and (EXTRA_NEEDS.get(name) is None or EXTRA_NEEDS[name] in kept)
    }


def apply_other_forms(verbs_doc):
    """Set the other-conjugation fields on every verb in place and remove the ones a verb must
    not have. The script owns these fields. Returns True if anything changed."""
    changed = False
    for verb in verbs_doc["verbs"]:
        forms = verb["forms"]
        wanted = other_forms(verb)
        wanted.update(extra_forms(verb, set(wanted)))
        for name in OTHER_FORM_FIELDS:
            if name in wanted:
                if forms.get(name) != wanted[name]:
                    forms[name] = wanted[name]
                    changed = True
            elif name in forms:
                del forms[name]
                changed = True
        if in_catalogue_order(forms):
            continue
        # A form inserted between two older ones (causative_passive_short) is appended by the
        # assignment above; put the keys back in the catalogue's order.
        ordered = sorted(forms, key=catalogue_position)
        verb["forms"] = {name: forms[name] for name in ordered}
        changed = True
    return changed


def catalogue_position(form_id):
    """Where a form id sits in the catalogue; ids it does not know go last."""
    known = form_catalogue.ids("verb")
    return known.index(form_id) if form_id in known else len(known)


def in_catalogue_order(forms):
    keys = list(forms)
    return keys == sorted(keys, key=catalogue_position)


# --- Verb auxiliaries (grammar points `teiru`, `teshimau`, `temiru`, `sugiru`) ---

# Verbs that take none of the て-form auxiliaries (ている, てしまう, ておく,
# てみる): they get no such fields, and any stale ones are removed. They keep
# the stem-based forms. This is the only hand-maintained part of the step;
# extend it as verbs are added. いる takes none of them (×いている, ×いてしまう); its
# stem-based forms (いすぎる, いながら) stay.
NO_TE_AUXILIARIES = {"ある", "いる"}

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


# --- Verb ids ----------------------------------------------------------------
# A verb's id is its kana `dict` unless it has an explicit `id`, which exists only where two verbs
# are spelled the same in kana (着る and 切る are both きる): the older keeps the bare `きる`, the newer
# is `きる:切る`. An id never changes once published, even if the verb's spelling is corrected.
# See docs/superpowers/specs/2026-10-17-verb-id-scheme-design.md.
EXPLICIT_ID_PATTERN = re.compile(r"^[ぁ-ゖァ-ヺー]+:[ぁ-ゖァ-ヺー一-鿿々]+$")
PUBLISHED_REF = "origin/main"


def verb_id(verb):
    return verb.get("id") or verb.get("dict")


def check_verb_ids(verbs_doc):
    """Problems with verb ids: a malformed explicit id, or two verbs with the same id."""
    problems = []
    owner = {}
    for verb in verbs_doc["verbs"]:
        dict_form = verb.get("dict", "<no dict>")
        if "id" in verb:
            explicit = verb["id"]
            if (not isinstance(explicit, str) or not EXPLICIT_ID_PATTERN.match(explicit)
                    or not explicit.startswith(dict_form + ":")):
                problems.append(
                    f"{dict_form}: id {explicit!r} must be the verb's kana, a ':' and its kanji, "
                    f"like '{dict_form}:切る'"
                )
        vid = verb_id(verb)
        if vid in owner:
            problems.append(
                f"{dict_form}: id '{vid}' is already used by {owner[vid]}; give the newer verb an "
                f"explicit id of the form '{dict_form}:<kanji>'"
            )
        else:
            owner[vid] = dict_form
    return problems


def published_verbs_doc(ref=PUBLISHED_REF, repo=None):
    """data/verbs.json as published at git `ref` (the last release on main), or None when git or
    the ref is unavailable, for example a shallow clone that did not fetch main."""
    try:
        shown = subprocess.run(
            ["git", "show", f"{ref}:data/verbs.json"], cwd=repo or Path(__file__).resolve().parent.parent,
            capture_output=True, text=True, check=True, timeout=30,
        ).stdout
        return json.loads(shown)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def check_published_ids(verbs_doc, published_doc):
    """Ids that were published and are gone now. Favourites, quiz history, widget configuration and
    links all store ids, so renaming or removing one breaks saved data. None means nothing to compare."""
    if published_doc is None:
        return []
    now = {verb_id(v) for v in verbs_doc["verbs"]}
    return [
        f"id '{vid}' is published on {PUBLISHED_REF} but missing here; ids never change "
        f"(if the verb was added on main after this branch started, merge main)"
        for vid in (verb_id(v) for v in published_doc.get("verbs", [])) if vid not in now
    ]


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


def check_example_forms(verbs_doc):
    """Problems with an example tagged with a form its verb does not have: one the
    generators leave out for that verb (EXTRA_EXCLUDED, PARTIAL_OTHER_FORMS) or that
    has no value. Run after the forms are generated; `check_verb_forms` has already
    checked that the tag is a verb form in the catalogue."""
    problems = []
    for verb in verbs_doc["verbs"]:
        forms = verb.get("forms", {})
        for example in verb.get("examples", []):
            form = example.get("form")
            if not forms.get(form):
                problems.append(f"{verb.get('dict', '?')}: example uses form '{form}', which the verb does not have")
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


# --- Counters (counters.json) ---------------------------------------------

COUNTER_KEYS = [str(n) for n in range(1, 11)] + ["what"]
SOUND_CLASSES = ("plain", "k", "s", "h-b", "h-p", "irregular")
COUNTER_FITS = ("primary", "acceptable", "casual")
BASE_NUMBERS = {"1": "いち", "2": "に", "3": "さん", "4": "よん", "5": "ご", "6": "ろく",
                "7": "なな", "8": "はち", "9": "きゅう", "10": "じゅう", "what": "なん"}
HUNDREDS = {1: "ひゃく", 2: "にひゃく", 3: "さんびゃく", 4: "よんひゃく", 5: "ごひゃく", 6: "ろっぴゃく",
            7: "ななひゃく", 8: "はっぴゃく", 9: "きゅうひゃく"}
THOUSANDS = {1: "せん", 2: "にせん", 3: "さんぜん", 4: "よんせん", 5: "ごせん", 6: "ろくせん", 7: "ななせん",
             8: "はっせん", 9: "きゅうせん"}
# The kana a small っ can come before (か, さ, た, は rows and their voiced forms).
GEMINATING_ROWS = set("かきくけこがぎぐげごさしすせそざじずぜぞたちつてとだぢづでどはひふへほばびぶべぼぱぴぷぺぽ")
# The numbers above `extent` a counter may list in `extra`: 100 is composed, the rest are authored.
EXTRA_NUMBERS = ([100 * n for n in range(1, 10)] + [1000 * n for n in range(1, 10)] + [10000])


def plain_number(n):
    """The number said on its own, in hiragana, with the preferred reading of each part (にじゅう,
    さんびゃく). Supports 1 to 99 and the round numbers in `EXTRA_NUMBERS`."""
    if 1 <= n <= 9:
        return BASE_NUMBERS[str(n)]
    if 10 <= n <= 99:
        tens, ones = divmod(n, 10)
        return ("" if tens == 1 else BASE_NUMBERS[str(tens)]) + "じゅう" + (BASE_NUMBERS[str(ones)] if ones else "")
    if n in EXTRA_NUMBERS:
        if n == 10000:
            return "いちまん"
        return HUNDREDS[n // 100] if n < 1000 else THOUSANDS[n // 1000]
    raise ValueError(f"no reading for {n}")


def counter_keys(counter):
    """Every key a counter has readings for, in order: 1 to 10 and 何, then 11 up to `extent`, then
    `extra`. A counter opts in to bigger numbers: without `extent` it has only 1 to 10 and 何."""
    extent = counter.get("extent", 10)
    keys = list(COUNTER_KEYS) + [str(n) for n in range(11, extent + 1)]
    return keys + [str(n) for n in counter.get("extra", [])]


# The small-っ form of the numbers that can geminate (いち -> いっ).
GEMINATED = {"1": "いっ", "6": "ろっ", "8": "はっ", "10": "じゅっ"}
GEMINATING_KEYS = {"k": ("1", "6", "8", "10"), "s": ("1", "8", "10"),
                   "h-b": ("1", "6", "8", "10"), "h-p": ("1", "6", "8", "10")}
# は-row counters: the keys that voice to b or p without gemination.
VOICED_KEYS = {"h-b": {"3": "b", "what": "b"}, "h-p": {"3": "p", "4": "p", "what": "p"}}
HA_ROW = {"は": ("ぱ", "ば"), "ひ": ("ぴ", "び"), "ふ": ("ぷ", "ぶ"), "へ": ("ぺ", "べ"), "ほ": ("ぽ", "ぼ")}


def _voiced(reading, kind):
    """ほん -> ぽん (p) or ぼん (b)."""
    p, b = HA_ROW[reading[0]]
    return (p if kind == "p" else b) + reading[1:]


def counter_readings(counter):
    """Every key's readings, preferred first: the class's rule, then the author's overrides, then for
    each number above ten the composed reading unless an override covers it. An irregular counter's
    readings for 1 to 10 are its overrides. A key the counter cannot compose and has no override for is
    left out; `check_counters` reports it."""
    sound, reading = counter["sound"], counter["reading"]
    overrides = counter.get("overrides", {})
    if sound == "irregular":
        core = {key: list(overrides[key]) for key in COUNTER_KEYS}
    else:
        core = {}
        for key in COUNTER_KEYS:
            plain = BASE_NUMBERS[key] + reading
            if key in GEMINATING_KEYS.get(sound, ()):
                rest = _voiced(reading, "p") if sound.startswith("h-") else reading
                readings = [GEMINATED[key] + rest]
                if key == "8" and sound != "s":
                    readings.append(plain)        # はちほん, はちこ are heard too
                if key == "10":
                    readings.append("じっ" + rest)
            elif key in VOICED_KEYS.get(sound, {}):
                readings = [BASE_NUMBERS[key] + _voiced(reading, VOICED_KEYS[sound][key])]
            else:
                readings = [plain]
            core[key] = readings
        for key in COUNTER_KEYS:
            if key in overrides:
                core[key] = list(overrides[key])
    result = dict(core)
    for key in counter_keys(counter)[len(COUNTER_KEYS):]:
        if key in overrides:
            result[key] = list(overrides[key])
        else:
            composed = compose_readings(counter, int(key), core)
            if composed:
                result[key] = composed
    return {key: result[key] for key in counter_keys(counter) if key in result}


def _unique(items):
    """`items` without repeats, in order."""
    return list(dict.fromkeys(items))


def compose_readings(counter, n, core):
    """The readings for a number above ten, preferred first, built from the counter's readings for 1 to 10
    (`core`) by the rules in the design: a tens prefix, then the last digit's readings; a round ten keeps
    the counter's reading of 10 behind the prefix; 100 is ひゃっ before か and は row counters and ひゃく
    otherwise. A counter's `compound` replaces a last digit (人: いちにん) and gives the reading after a
    round ten. Returns None when the counter cannot compose `n` (an irregular counter with no `compound`,
    or a round number above 100, which is authored)."""
    compound = counter.get("compound", {})
    if n <= 10:
        return core.get(str(n))
    if counter["sound"] == "irregular" and not compound:
        return None     # an irregular counter's compounds are authored (compound or overrides), never guessed
    if n == 100:
        zero = compound.get("0")
        if zero:
            return _unique("ひゃく" + z for z in zero)
        if counter["sound"] in ("k", "h-b", "h-p"):
            first = core["10"][0]
            return [("ひゃっ" + first[len("じゅっ"):])] if first.startswith("じゅっ") else None
        return None if counter["sound"] == "irregular" else ["ひゃく" + counter["reading"]]
    if not 11 <= n <= 99:
        return None
    tens, ones = divmod(n, 10)
    prefix = "" if tens == 1 else BASE_NUMBERS[str(tens)]
    if ones:
        units = compound.get(str(ones)) or core[str(ones)]
        return _unique(prefix + "じゅう" + reading for reading in units)
    if "0" in compound:
        return _unique(prefix + "じゅう" + reading for reading in compound["0"])
    if counter["sound"] == "irregular":
        return None
    composed = []
    for reading in core["10"]:
        head = next((h for h in ("じゅう", "じゅっ", "じっ") if reading.startswith(h)), None)
        if head is None:
            return None
        composed.append(prefix + head + reading[len(head):])
    return _unique(composed)


def _plain_reading(counter, key):
    """The number said on its own followed by the counter's reading: the form a learner would guess."""
    number = BASE_NUMBERS[key] if key in BASE_NUMBERS else plain_number(int(key))
    return number + counter["reading"]


def changed_keys(counter, readings):
    """The keys whose preferred reading is not the plain number plus the counter's reading.
    Irregular counters have none: every cell differs, so marking them says nothing."""
    if counter["sound"] == "irregular":
        return []
    return [key for key in readings if readings[key][0] != _plain_reading(counter, key)]


def _swap_voicing(preferred, reading, sound):
    """The preferred reading of an h-b or h-p counter with its は-row sound flipped between ば and
    ぱ rows; a plain は-row sound takes the class's own sound. None when it cannot be located."""
    tail = reading[1:]
    if len(preferred) < len(tail) + 1 or not preferred.endswith(tail):
        return None
    sound_at = len(preferred) - len(tail) - 1
    plain = reading[0]
    p, b = HA_ROW[plain]
    current = preferred[sound_at]
    if current == p:
        flipped = b
    elif current == b:
        flipped = p
    elif current == plain:
        flipped = b if sound == "h-b" else p
    else:
        return None
    return preferred[:sound_at] + flipped + tail


def counter_distractors(counter, readings):
    """Wrong readings a quiz can offer for each key, up to three, none of them an accepted reading.

    Tried in order: the unchanged reading (さんほん); for h-b and h-p the preferred reading with its
    ば/ぱ sound flipped (さんぽん); the base number's last kana turned into a small っ before the
    counter's reading, its は-row sound as ぱ row for h-b and h-p (さっぽん). Irregular counters get
    only the unchanged reading. A base number of one kana (に, ご) has no small-っ form.

    A number above ten gets distractors only when it changed or is authored (an override); every
    other extended key is left out, which keeps the file small. For those, the small-っ form is only
    tried when the number ends in a syllable that geminates (にじゅう -> にじゅっ) and the counter starts
    on a sound that can follow a small っ (か, さ, た, は rows): にひゃっえん is not Japanese."""
    sound, reading = counter["sound"], counter["reading"]
    overrides = counter.get("overrides", {})
    changed = set(changed_keys(counter, readings))
    result = {}
    for key in readings:
        extended = key not in COUNTER_KEYS
        if extended and key not in changed and key not in overrides:
            continue            # no key at all: the app reads a missing key as no distractors
        accepted = set(readings[key])
        base = BASE_NUMBERS[key] if not extended else plain_number(int(key))
        candidates = [base + reading]
        if sound != "irregular":
            if sound in ("h-b", "h-p"):
                candidates.append(_swap_voicing(readings[key][0], reading, sound))
            geminates = (base.endswith(("いち", "ろく", "はち", "じゅう", "ひゃく")) and reading[0] in GEMINATING_ROWS
                         if extended else len(base) > 1)
            if geminates:
                rest = _voiced(reading, "p") if sound in ("h-b", "h-p") else reading
                candidates.append(base[:-1] + "っ" + rest)
        wrong = []
        for candidate in candidates:
            if candidate and candidate not in accepted and candidate not in wrong:
                wrong.append(candidate)
        result[key] = wrong[:3]
    return result


NUMBER_KANJI = {"一": "1", "二": "2", "三": "3", "四": "4", "五": "5", "六": "6", "七": "7",
                "八": "8", "九": "9", "十": "10", "何": "what"}
# A number is only a counted run when nothing numeric comes before it (二十本 is not 十本).
NUMERAL_CHARS = "".join(NUMBER_KANJI) + "百千万"


def _is_hiragana(text):
    return isinstance(text, str) and bool(READING_PATTERN.match(text))


def _is_kana(text):
    return isinstance(text, str) and bool(re.match("^[ぁ-ゖァ-ヺー]+$", text))


def _check_example(where, example, problems):
    if not isinstance(example, dict) or not example.get("jp") or not example.get("en"):
        problems.append(f"{where}: example needs jp and en")
        return
    for kanji, reading in (example.get("readings") or {}).items():
        if kanji not in example["jp"]:
            problems.append(f"{where}: readings key {kanji} does not occur in the sentence")
        if not _is_hiragana(reading):
            problems.append(f"{where}: readings['{kanji}'] must be hiragana")


def check_counters(doc, readings):
    """Problems with the hand-written fields of counters.json (counters and groups)."""
    problems = []
    counters = doc.get("counters")
    if not isinstance(counters, list) or not counters:
        return ["counters: must be a non-empty list"]
    ids = [c.get("id") for c in counters]
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        problems.append(f"{dup}: duplicate id")
    for c in counters:
        cid = c.get("id", "<no id>")
        for key in ("id", "counter", "reading", "meaning", "symbol"):
            if not isinstance(c.get(key), str) or not c[key]:
                problems.append(f"{cid}: {key} missing or empty")
        if not _is_hiragana(c.get("reading")):
            problems.append(f"{cid}: reading must be hiragana")
        if c.get("jlpt") not in JLPT_LEVELS:
            problems.append(f"{cid}: jlpt must be one of {sorted(JLPT_LEVELS)}")
        sound = c.get("sound")
        if sound not in SOUND_CLASSES:
            problems.append(f"{cid}: sound must be one of {SOUND_CLASSES}")
        elif sound in ("h-b", "h-p") and _is_hiragana(c.get("reading")) and c["reading"][0] not in HA_ROW:
            problems.append(f"{cid}: an {sound} counter's reading must start on the は-row")
        if "countsObjects" in c and not isinstance(c["countsObjects"], bool):
            problems.append(f"{cid}: countsObjects must be true or false")
        if "questions" in c:
            _check_questions(c, problems)
        big_fields_ok = _check_big_number_fields(c, problems)
        keys = counter_keys(c) if big_fields_ok else COUNTER_KEYS
        overrides = c.get("overrides", {})
        if not isinstance(overrides, dict):
            problems.append(f"{cid}: overrides must be an object")
            overrides = {}
        for key, value in overrides.items():
            if key not in keys:
                problems.append(f"{cid}: overrides key '{key}' must be one of its keys (1 to 10, 何, 11 up to "
                                f"extent {c.get('extent', 10)}, and extra {c.get('extra', [])})")
            if not isinstance(value, list) or not value or not all(_is_hiragana(v) for v in value):
                problems.append(f"{cid}: overrides['{key}'] must be a non-empty list of hiragana")
        if sound == "irregular":
            missing = [key for key in COUNTER_KEYS if key not in overrides]
            if missing:
                problems.append(f"{cid}: an irregular counter must override every key; missing {missing}")
        core_complete = sound != "irregular" or all(key in overrides for key in COUNTER_KEYS)
        if big_fields_ok and core_complete and sound in SOUND_CLASSES and isinstance(overrides, dict):
            try:
                composed = counter_readings(c)
            except (KeyError, IndexError, TypeError, ValueError):
                composed = None         # a malformed reading or sound: the checks above report it
            absent = [key for key in keys if key not in composed] if composed is not None else []
            if absent and sound == "irregular":
                problems.append(f"{cid}: an irregular counter with extent {c.get('extent', 10)} needs a compound "
                                f"(with '0') or overrides for every bigger number; missing {absent[:6]}")
            elif absent:
                problems.append(f"{cid}: numbers {absent[:6]} are authored and must override")
        for related in c.get("related", []):
            if related not in ids:
                problems.append(f"{cid}: related id '{related}' does not exist")
        for thing in c.get("things", []):
            word = thing.get("word", "<no word>")
            for key in ("word", "kana", "meaning"):
                if not isinstance(thing.get(key), str) or not thing[key]:
                    problems.append(f"{cid}/{word}: thing {key} missing or empty")
            if thing.get("fit") not in COUNTER_FITS:
                problems.append(f"{cid}/{word}: thing fit must be one of {COUNTER_FITS}")
            if _is_kana(thing.get("kana")) and isinstance(thing.get("word"), str):
                if not uncovered_kanji(thing["word"], readings):
                    got = kana_reading(thing["word"], readings)
                    if any(is_kanji(ch) for ch in thing["word"]) and got != thing["kana"]:
                        problems.append(f"{cid}/{word}: {word} reads as {got}, expected {thing['kana']}")
            elif "kana" in thing:
                problems.append(f"{cid}/{word}: thing kana must be hiragana or katakana")
        for index, example in enumerate(c.get("examples", [])):
            _check_example(f"{cid}: examples[{index}]", example, problems)
        for pitfall in c.get("pitfalls", []):
            heading = pitfall.get("heading", "<no heading>")
            for key in ("heading", "explanation"):
                if not isinstance(pitfall.get(key), str) or not pitfall[key]:
                    problems.append(f"{cid}/{heading}: pitfall {key} missing or empty")
            if "wrong" in pitfall and (not isinstance(pitfall["wrong"], str) or not pitfall["wrong"].strip()):
                problems.append(f"{cid}/{heading}: pitfall wrong must be a non-empty string when present")
            for index, example in enumerate(pitfall.get("examples", [])):
                _check_example(f"{cid}/{heading}: pitfall example {index}", example, problems)

    groups = doc.get("groups")
    if not isinstance(groups, list):
        problems.append("groups: must be a list")
        return problems
    group_ids = [g.get("id") for g in groups]
    for dup in sorted({i for i in group_ids if group_ids.count(i) > 1}):
        problems.append(f"{dup}: duplicate group id")
    grouped = set()
    for g in groups:
        gid = g.get("id", "<no id>")
        for key in ("id", "title", "symbol", "summary"):
            if not isinstance(g.get(key), str) or not g[key]:
                problems.append(f"group {gid}: {key} missing or empty")
        members = [m.get("counter") for m in g.get("members", [])]
        for member in members:
            if member not in ids:
                problems.append(f"group {gid}: member '{member}' is not a counter")
            grouped.add(member)
        for dup in sorted({m for m in members if members.count(m) > 1}):
            problems.append(f"group {gid}: member '{dup}' listed twice")
    for cid in ids:
        if cid not in grouped:
            problems.append(f"{cid}: counter is in no group")
    if "sections" in doc:
        problems.extend(_check_sections(doc["sections"], ids))
    return problems


def _check_big_number_fields(c, problems):
    """The optional `extent`, `extra` and `compound` of one counter. Returns False when any is malformed,
    so later checks do not build on it."""
    cid, ok = c.get("id", "<no id>"), True
    extent = c.get("extent", 10)
    if "extent" in c and (isinstance(extent, bool) or not isinstance(extent, int) or not 10 <= extent <= 99):
        problems.append(f"{cid}: extent must be a whole number from 10 to 99")
        ok = False
    extra = c.get("extra", [])
    if not isinstance(extra, list) or not all(isinstance(n, int) and not isinstance(n, bool) and n in EXTRA_NUMBERS
                                                for n in extra) or extra != sorted(set(extra)):
        problems.append(f"{cid}: extra must be an ascending list of numbers from {EXTRA_NUMBERS}")
        ok = False
    compound = c.get("compound", {})
    if not isinstance(compound, dict):
        problems.append(f"{cid}: compound must be an object with keys '0' to '9'")
        return False
    for key, value in compound.items():
        if key not in [str(d) for d in range(10)]:
            problems.append(f"{cid}: compound must be an object with keys '0' to '9', not '{key}'")
            ok = False
        elif not isinstance(value, list) or not value or not all(_is_hiragana(v) for v in value):
            problems.append(f"{cid}: compound must be an object of non-empty hiragana lists; '{key}' is not")
            ok = False
    return ok


def _check_questions(c, problems):
    """The optional 何 questions of one counter: each an object with a Japanese sentence that holds
    何 plus the counter, and an English question."""
    cid, questions = c.get("id", "<no id>"), c["questions"]
    if not isinstance(questions, list):
        problems.append(f"{cid}: questions must be a list")
        return
    for index, question in enumerate(questions):
        where = f"{cid}: questions[{index}]"
        if not isinstance(question, dict):
            problems.append(f"{where}: question must be an object")
            continue
        for key in ("jp", "en"):
            if not isinstance(question.get(key), str) or not question[key].strip():
                problems.append(f"{where}: question {key} missing or empty")
        asked = "何" + str(c.get("counter", ""))
        longer = "" if asked.endswith("間") else "(?!間)"     # 何時間 is not a question for 時
        if (isinstance(question.get("jp"), str) and question["jp"].strip()
                and not re.search(re.escape(asked) + longer, question["jp"])):
            problems.append(f"{where}: jp must contain {asked}")


def _check_sections(sections, ids):
    """Problems with the optional home-list `sections` of counters.json."""
    if not isinstance(sections, list):
        return ["sections: must be a list"]
    problems = []
    section_ids = [s.get("id") for s in sections if isinstance(s, dict)]
    for dup in sorted({i for i in section_ids if section_ids.count(i) > 1}):
        problems.append(f"{dup}: duplicate section id")
    listed = set()
    for s in sections:
        if not isinstance(s, dict):
            problems.append(f"section {s!r}: must be an object")
            continue
        sid = s.get("id", "<no id>")
        for key in ("id", "title"):
            if not isinstance(s.get(key), str) or not s[key]:
                problems.append(f"section {sid}: {key} missing or empty")
        members = s.get("counters")
        if not isinstance(members, list) or not all(isinstance(m, str) for m in members):
            problems.append(f"section {sid}: counters must be a list of counter ids")
            continue
        if not members:
            problems.append(f"section {sid}: has no counters")
        for member in members:
            if member not in ids:
                problems.append(f"section {sid}: '{member}' is not a counter")
            listed.add(member)
        for dup in sorted({m for m in members if members.count(m) > 1}):
            problems.append(f"section {sid}: '{dup}' listed twice")
    for cid in ids:
        if cid not in listed:
            problems.append(f"{cid}: counter is in no section")
    return problems


def apply_counter_readings(doc):
    """Set every counter's `readings` and `changed` (the script owns them). Returns True if anything changed."""
    changed = False
    for c in doc["counters"]:
        wanted = counter_readings(c)
        keys = changed_keys(c, wanted)
        wrong = counter_distractors(c, wanted)
        order = list(wanted)
        if (c.get("readings") != wanted or list(c.get("readings", {})) != order or c.get("changed") != keys
                or c.get("distractors") != wrong or list(c.get("distractors", {})) != list(wrong)):
            c["readings"], c["changed"], c["distractors"] = wanted, keys, wrong
            changed = True
    return changed


def check_counter_distractors(doc):
    """Problems in the generated `distractors`, run after `apply_counter_readings`: each is hiragana,
    at most three per key, and never an accepted reading of its key."""
    problems = []
    for c in doc["counters"]:
        for key in counter_keys(c):
            if key not in COUNTER_KEYS and key not in (c.get("distractors") or {}):
                continue        # an extended number with no distractors has no key
            wrong = (c.get("distractors") or {}).get(key)
            if not isinstance(wrong, list) or len(wrong) > 3:
                problems.append(f"{c['id']}: distractors['{key}'] must be a list of at most three readings")
                continue
            for reading in wrong:
                if not _is_hiragana(reading):
                    problems.append(f"{c['id']}: distractors['{key}'] has '{reading}', which is not hiragana")
                elif reading in c["readings"][key]:
                    problems.append(f"{c['id']}: distractors['{key}'] has '{reading}', an accepted reading")
    return problems


_DIGITS = "一二三四五六七八九"
_NUMERAL_PARTS = (rf"(?:[{_DIGITS}]万)?(?:[二三四五六七八九]?千)?(?:[二三四五六七八九]?百)?"
                  rf"(?:[二三四五六七八九]?十)?[{_DIGITS}]?")
_NUMERAL_FULL = re.compile(
    rf"(?:(?P<man>[{_DIGITS}])万)?(?:(?P<sen>[二三四五六七八九])?(?P<sen_mark>千))?"
    rf"(?:(?P<hyaku>[二三四五六七八九])?(?P<hyaku_mark>百))?(?:(?P<ju>[二三四五六七八九])?(?P<ju_mark>十))?"
    rf"(?P<one>[{_DIGITS}])?")


def parse_numeral(text):
    """The value of a kanji numeral (十五, 二十, 三百, 一万), or None if it is not a well-formed one:
    no 一 before 十, 百 or 千 (those say 十, 百, 千), parts in descending order, and not empty."""
    match = _NUMERAL_FULL.fullmatch(text)
    if not text or not match:
        return None
    digit = lambda ch: _DIGITS.index(ch) + 1
    total = 0
    if match["man"]:
        total += digit(match["man"]) * 10000
    for mark, place, value in (("sen_mark", "sen", 1000), ("hyaku_mark", "hyaku", 100), ("ju_mark", "ju", 10)):
        if match[mark]:
            total += (digit(match[place]) if match[place] else 1) * value
    if match["one"]:
        total += digit(match["one"])
    return total or None


def check_counted_runs(doc, readings):
    """Every counted run (三本, 何日) in an example must read as one of its counter's readings
    for that number. The example's own `readings` come first, then furigana.json."""
    problems = []
    for c in doc["counters"]:
        # 三時間 is a run of 時間, not of 時: leave a run followed by 間 to the longer counter.
        longer = "" if c["counter"].endswith("間") else "(?!間)"
        pattern = re.compile(
            f"(?<![{NUMERAL_CHARS}])(何|(?=[{_DIGITS}十百千万]){_NUMERAL_PARTS}){re.escape(c['counter'])}{longer}")
        keys = counter_keys(c)
        sources = [(f"examples[{i}]", e) for i, e in enumerate(c.get("examples", []))]
        sources += [(f"questions[{i}]", q) for i, q in enumerate(c.get("questions", [])) if isinstance(q, dict)]
        for pitfall in c.get("pitfalls", []):
            sources += [(f"{pitfall.get('heading', 'pitfall')} example {i}", e)
                        for i, e in enumerate(pitfall.get("examples", []))]
            for key in ("heading", "explanation"):      # shown with ruby too
                if isinstance(pitfall.get(key), str):
                    sources.append((f"{pitfall.get('heading', 'pitfall')} {key}", {"jp": pitfall[key]}))
        for where, example in sources:
            own = example.get("readings") or {}
            for match in pattern.finditer(example.get("jp", "")):
                run = match.group(0)
                number = match.group(1)
                key = "what" if number == "何" else str(parse_numeral(number))
                if key not in keys or key not in c["readings"]:
                    continue        # a number the counter has no readings for (百五十本) is not checked
                accepted = c["readings"][key]
                got = own.get(run) or kana_reading(run, readings)
                if got not in accepted:
                    problems.append(
                        f'{c["id"]}: {where}: {run} reads as {got}, expected {" or ".join(accepted)}; '
                        f'add "{run}": "{accepted[0]}" to furigana.json'
                        f' (or to the example\'s readings if the dictionary must read it another way)')
    return problems


def dump_counters(doc):
    """Serialize counters.json: 2-space indent, non-ASCII kept, each counter and group on one line."""
    head = {key: value for key, value in doc.items() if key not in ("counters", "groups", "sections")}
    text = json.dumps(head, ensure_ascii=False, indent=2)[:-2]
    sections = []
    for name in ("counters", "groups", "sections"):
        if name in doc:
            body = ",\n".join(f"    {json.dumps(item, ensure_ascii=False)}" for item in doc[name])
            sections.append(f'  "{name}": [\n{body}\n  ]' if body else f'  "{name}": []')
    return text + ",\n" + ",\n".join(sections) + "\n}\n"


def dump_forms():
    """Serialize the catalogue as forms.json, in the repo's style."""
    return json.dumps(form_catalogue.to_json_doc(), ensure_ascii=False, indent=2) + "\n"


def dump_verbs(doc):
    """Serialize verbs.json in the repo's style: 2-space indent, non-ASCII
    kept, and each example object on a single line."""
    text = json.dumps(doc, ensure_ascii=False, indent=2)
    text = re.sub(
        r'\{\n(?:\s+("id": [^\n]+),\n)?\s+("form": [^\n]+),\n\s+("jp": [^\n]+),\n\s+("en": [^\n]+)\n\s+\}',
        lambda m: "{ " + ", ".join(part for part in m.groups() if part) + " }",
        text,
    )
    return text + "\n"


def check_books(doc):
    """Problems with the optional top-level `books` and each point's `taught_in`."""
    errors = []
    ranges = {}
    seen = set()
    for book in doc.get("books", []):
        bid = book.get("id")
        if bid in seen:
            errors.append(f"books: duplicate id {bid}")
        seen.add(bid)
        if not isinstance(book.get("title"), str) or not book["title"]:
            errors.append(f"books: {bid} title missing")
        if "edition" in book and (not isinstance(book["edition"], str) or not book["edition"]):
            errors.append(f"books: {bid} edition must be a non-empty string when present")
        first = book.get("first_lesson", 1)
        last = book.get("lessons")
        if not isinstance(first, int) or isinstance(first, bool) or first < 1:
            errors.append(f"books: {bid} first_lesson must be a positive integer")
        elif not isinstance(last, int) or isinstance(last, bool) or last < first:
            errors.append(f"books: {bid} lessons must be >= first_lesson")
        else:
            ranges[bid] = (first, last)

    for p in doc.get("grammar", []):
        pid = p.get("id", "<no id>")
        listed = set()
        for ref in p.get("taught_in", []):
            book, lesson = ref.get("book"), ref.get("lesson")
            if book not in seen:
                errors.append(f"{pid}: taught_in book '{book}' does not exist")
            elif book in ranges:
                first, last = ranges[book]
                if not isinstance(lesson, int) or isinstance(lesson, bool) or not first <= lesson <= last:
                    errors.append(f"{pid}: taught_in {book} lesson {lesson} is outside {first}-{last}")
            if not isinstance(ref.get("reviewed"), bool):
                errors.append(f"{pid}: taught_in reviewed must be true or false")
            if (book, lesson) in listed:
                errors.append(f"{pid}: taught_in lists {book} lesson {lesson} twice")
            listed.add((book, lesson))
    return errors


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
            if "wrong" in f and (not isinstance(f["wrong"], str) or not f["wrong"].strip()):
                errors.append(f"{pid}/{heading}: pitfall wrong must be a non-empty string when present")
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

    errors.extend(check_books(doc))

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


# Review stamps: an entry (a counter, a grammar point) may carry {"by", "on", "sha256"}. The hash covers the
# entry's own content without the stamp and without generated fields, so regenerating keeps a stamp valid and
# any edit to the text makes it stale.
REVIEWERS = ("owner", "teacher")
COUNTER_GENERATED = ("readings", "changed", "distractors")
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def review_hash(entry, generated=()):
    """SHA-256 of an entry's canonical JSON without `review` and the `generated` fields."""
    content = {key: value for key, value in entry.items() if key != "review" and key not in generated}
    text = json.dumps(content, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def valid_iso_date(text):
    if not isinstance(text, str) or not ISO_DATE.match(text):
        return False
    try:
        datetime.date.fromisoformat(text)
    except ValueError:
        return False
    return True


def check_reviews(entries, generated=()):
    """Problems with the `review` stamps in `entries`: a bad shape, or a stamp whose hash no longer matches."""
    problems = []
    for entry in entries:
        if "review" not in entry:
            continue
        name, stamp = entry.get("id", "<no id>"), entry["review"]
        if not isinstance(stamp, dict):
            problems.append(f"{name}: review must be an object with by, on and sha256")
            continue
        if stamp.get("by") not in REVIEWERS:
            problems.append(f"{name}: review.by must be one of {list(REVIEWERS)}")
        if not valid_iso_date(stamp.get("on")):
            problems.append(f"{name}: review.on must be a date like 2026-10-24")
        if not isinstance(stamp.get("sha256"), str):
            problems.append(f"{name}: review.sha256 is missing")
        elif stamp["sha256"] != review_hash(entry, generated) and stamp.get("by") in REVIEWERS \
                and valid_iso_date(stamp.get("on")):
            problems.append(
                f"{name} was edited after review on {stamp['on']}: re-review it, "
                f"or run scripts/mark_reviewed.py again")
    return problems


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


def optional_entry(existing, name, data, forced_version, ref):
    """The manifest entry for the optional file `name` (`forms`): its version is kept while the
    hash is unchanged, bumped (minor) when it changed, started at 1.0.0 when the entry is new,
    or forced by `forced_version`."""
    digest = sha256_hex(data)
    old = existing.get(name)
    if forced_version:
        version = forced_version
    elif old is None:
        version = "1.0.0"
    elif old.get("sha256") == digest:
        version = old["version"]
    else:
        version = bump_minor(old["version"])
    return with_ref({"version": version, "sha256": digest}, entry_ref(old, digest, ref))


def build_manifest(existing, verbs_bytes, grammar_bytes, verbs_version=None, grammar_version=None,
                   furigana_bytes=None, furigana_version=None, ref=None, words_bytes=None, words_version=None,
                   counters_bytes=None, counters_version=None, forms_bytes=None, forms_version=None):
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
    if counters_bytes is not None:
        counters_hash = sha256_hex(counters_bytes)
        old_counters = existing.get("counters")
        if counters_version:
            new_counters_version = counters_version
        elif old_counters is None:
            new_counters_version = "1.0.0"
        elif old_counters.get("sha256") == counters_hash:
            new_counters_version = old_counters["version"]
        else:
            new_counters_version = bump_minor(old_counters["version"])
        manifest["counters"] = with_ref(
            {"version": new_counters_version, "sha256": counters_hash}, entry_ref(old_counters, counters_hash, ref)
        )
    if forms_bytes is not None:
        manifest["forms"] = optional_entry(existing, "forms", forms_bytes, forms_version, ref)
    return manifest


def capped(heading, problems):
    """A problem list for the user, cut to MAX_PROBLEMS_SHOWN lines."""
    lines = [heading] + [f"  - {p}" for p in problems[:MAX_PROBLEMS_SHOWN]]
    if len(problems) > MAX_PROBLEMS_SHOWN:
        lines.append(f"  ... and {len(problems) - MAX_PROBLEMS_SHOWN} more")
    return lines


# The app's bundled copy of data/forms.json (read through Bundle.module): its offline fallback
# until a synced catalogue arrives. SwiftPM cannot bundle a file from outside the package, so this
# script writes the copy, and --check fails if it differs from data/forms.json.
DEFAULT_BUNDLED_FORMS_PATH = (
    Path(__file__).resolve().parent.parent
    / "Packages/VerbKit/Sources/VerbKit/Resources/forms.json"
)


# The app's bundled copy of data/counters.json, written the same way: the Counters tab's offline
# fallback until a synced copy arrives. counters.manifest.json beside it holds its version and hash.
DEFAULT_BUNDLED_COUNTERS_PATH = (
    Path(__file__).resolve().parent.parent
    / "Packages/VerbKit/Sources/VerbKit/Resources/counters.json"
)


# The app's bundled copies of verbs.json, grammar.json, furigana.json and words.json, written next to the
# forms and counters copies, each with a sidecar of its manifest entry. The app installs a bundle into its
# store when it is newer than anything it has, so a first launch works offline.
DEFAULT_BUNDLED_DATA_DIR = Path(__file__).resolve().parent.parent / "Packages/VerbKit/Sources/VerbKit/Resources"


def bundled_counters_manifest_path(bundled_counters_path):
    """Where the bundled counters copy's version and hash go: counters.manifest.json, next to it."""
    return Path(bundled_counters_path).with_name("counters.manifest.json")


def bundled_forms_manifest_path(bundled_forms_path):
    """Where the bundled copy's version and hash go: forms.manifest.json, next to it. The app
    compares it with a synced catalogue's version to use whichever is newer."""
    return Path(bundled_forms_path).with_name("forms.manifest.json")


def run(data_dir, check=False, verbs_version=None, grammar_version=None, furigana_version=None,
        bundled_forms_path=None, ref=None, words_version=None, counters_version=None, published_verbs=None,
        forms_version=None, bundled_counters_path=None, bundled_data_dir=None):
    """Returns (exit_code, messages). data/forms.json is always written and checked;
    `bundled_forms_path` is where the app's bundled copy (and forms.manifest.json beside it) is
    written and checked, and None leaves them alone; `bundled_counters_path` does the same for
    counters.json and counters.manifest.json, and `bundled_data_dir` for verbs, grammar, furigana and
    words (each `<name>.json` with `<name>.manifest.json`). `ref` pins the manifest entries
    to a release tag. `published_verbs` is the published verbs.json (see
    `published_verbs_doc`) that no id may disappear from; None skips that check."""
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
    try:
        grammar_doc = loads_without_duplicate_keys(grammar_bytes)
    except ValueError as error:
        return 1, [f"grammar.json is invalid: {error}"]
    problems = check_stable_ids("grammar", grammar_doc)
    if problems:
        return 1, capped("grammar.json has items without a valid stable id:", problems)
    problems = validate_grammar(grammar_doc) + check_reviews(grammar_doc["grammar"])
    if problems:
        return 1, ["grammar.json is invalid:"] + [f"  - {p}" for p in problems]

    furigana_bytes = furigana_path.read_bytes()
    furigana_doc = json.loads(furigana_bytes)
    problems = validate_furigana(furigana_doc)
    if problems:
        return 1, capped("furigana.json is invalid:", problems)
    readings = furigana_doc["readings"]

    try:
        verbs_doc = loads_without_duplicate_keys(verbs_path.read_text(encoding="utf-8"))
    except ValueError as error:
        return 1, [f"verbs.json is invalid: {error}"]
    problems = check_verb_jlpt(verbs_doc)
    if problems:
        return 1, capped("verbs.json has an invalid jlpt level:", problems)
    problems = check_verb_ids(verbs_doc) + check_published_ids(verbs_doc, published_verbs)
    if problems:
        return 1, capped("verbs.json has invalid ids:", problems)
    problems = check_stable_ids("verbs", verbs_doc)
    if problems:
        return 1, capped("verbs.json has items without a valid stable id:", problems)
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
    problems = check_example_forms(verbs_doc)
    if problems:
        return 1, capped("verbs.json has examples with forms their verb lacks:", problems)
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
    counters_path = data_dir / "counters.json"
    try:
        counters_doc = (loads_without_duplicate_keys(counters_path.read_text(encoding="utf-8"))
                        if counters_path.exists() else None)
    except ValueError as error:
        return 1, [f"counters.json is invalid: {error}"]
    counters_bytes = None
    if counters_doc is not None:
        problems = check_stable_ids("counters", counters_doc)
        if problems:
            return 1, capped("counters.json has items without a valid stable id:", problems)
        problems = check_counters(counters_doc, readings) + check_reviews(counters_doc["counters"], COUNTER_GENERATED)
        if problems:
            return 1, capped("counters.json is invalid:", problems)
        apply_counter_readings(counters_doc)
        problems = check_counter_distractors(counters_doc)
        if problems:
            return 1, capped("counters.json has invalid distractors:", problems)
        problems = check_counted_runs(counters_doc, readings)
        if problems:
            return 1, capped("a counted word in counters.json does not read as its counter says:", problems)
        counters_bytes = dump_counters(counters_doc).encode("utf-8")
    extra_docs = [doc for doc in (words_doc, counters_doc) if doc]
    problems = check_coverage(verbs_doc, grammar_doc, readings, *extra_docs)
    if problems:
        return 1, capped("kanji without a reading in furigana.json:", problems)
    problems = check_verb_kanji(verbs_doc, readings)
    if problems:
        return 1, capped("a verb's kanji does not match its kana form:", problems)
    verbs_text = dump_verbs(verbs_doc)
    verbs_bytes = verbs_text.encode("utf-8")

    forms_path = data_dir / "forms.json"
    forms_bytes = dump_forms().encode("utf-8")

    existing = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest = build_manifest(
        existing, verbs_bytes, grammar_bytes, verbs_version, grammar_version,
        furigana_bytes=furigana_bytes, furigana_version=furigana_version, ref=ref,
        words_bytes=words_bytes, words_version=words_version,
        counters_bytes=counters_bytes, counters_version=counters_version,
        forms_bytes=forms_bytes, forms_version=forms_version,
    )
    manifest_text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
    # The bundled copy's entry: version and hash only (no ref), since the app never fetches it.
    bundled_entry = {"version": manifest["forms"]["version"], "sha256": manifest["forms"]["sha256"]}
    bundled_manifest_bytes = (json.dumps(bundled_entry, indent=2) + "\n").encode("utf-8")

    def differs(path, data):
        return not path.exists() or path.read_bytes() != data

    stale = []
    if verbs_path.read_bytes() != verbs_bytes:
        stale.append("data/verbs.json")
    if words_bytes is not None and words_path.read_bytes() != words_bytes:
        stale.append("data/words.json")
    if differs(forms_path, forms_bytes):
        stale.append("data/forms.json")
    if bundled_forms_path is not None:
        bundled_forms_path = Path(bundled_forms_path)
        bundled_manifest_path = bundled_forms_manifest_path(bundled_forms_path)
        if differs(bundled_forms_path, forms_bytes) or differs(bundled_manifest_path, bundled_manifest_bytes):
            stale.append("the bundled forms.json")
    if counters_bytes is not None and counters_path.read_bytes() != counters_bytes:
        stale.append("data/counters.json")
    bundled_counters_manifest_bytes = None
    if bundled_counters_path is not None and counters_bytes is not None:
        bundled_counters_path = Path(bundled_counters_path)
        bundled_counters_sidecar = bundled_counters_manifest_path(bundled_counters_path)
        entry = {"version": manifest["counters"]["version"], "sha256": manifest["counters"]["sha256"]}
        bundled_counters_manifest_bytes = (json.dumps(entry, indent=2) + "\n").encode("utf-8")
        if (differs(bundled_counters_path, counters_bytes)
                or differs(bundled_counters_sidecar, bundled_counters_manifest_bytes)):
            stale.append("the bundled counters.json")
    bundled_data = {}
    if bundled_data_dir is not None:
        entries = {"verbs": ({"version": manifest["version"], "sha256": manifest["sha256"]}, verbs_bytes)}
        for name, content in (("grammar", grammar_bytes), ("furigana", furigana_bytes), ("words", words_bytes)):
            if name in manifest and content is not None:
                entries[name] = ({"version": manifest[name]["version"], "sha256": manifest[name]["sha256"]}, content)
        for name, (entry, content) in entries.items():
            path = Path(bundled_data_dir) / f"{name}.json"
            sidecar = path.with_name(f"{name}.manifest.json")
            sidecar_bytes = (json.dumps(entry, indent=2) + "\n").encode("utf-8")
            if differs(path, content) or differs(sidecar, sidecar_bytes):
                stale.append(f"the bundled {name}.json")
                bundled_data[name] = (path, content, sidecar, sidecar_bytes)
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
    if "data/counters.json" in stale:
        counters_path.write_bytes(counters_bytes)
        messages.append("updated data/counters.json")
    if "data/forms.json" in stale:
        forms_path.write_bytes(forms_bytes)
        messages.append("updated data/forms.json")
    for name, (path, content, sidecar, sidecar_bytes) in bundled_data.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        sidecar.write_bytes(sidecar_bytes)
        messages.append(f"updated the bundled copy ({path.name}, {sidecar.name})")
    if "the bundled counters.json" in stale:
        bundled_counters_path.parent.mkdir(parents=True, exist_ok=True)
        bundled_counters_path.write_bytes(counters_bytes)
        bundled_counters_sidecar.write_bytes(bundled_counters_manifest_bytes)
        messages.append(f"updated the bundled copy ({bundled_counters_path.name}, {bundled_counters_sidecar.name})")
    if "the bundled forms.json" in stale:
        bundled_forms_path.parent.mkdir(parents=True, exist_ok=True)
        bundled_forms_path.write_bytes(forms_bytes)
        bundled_manifest_path.write_bytes(bundled_manifest_bytes)
        messages.append(f"updated the bundled copy ({bundled_forms_path.name}, {bundled_manifest_path.name})")
    if "data/manifest.json" in stale:
        manifest_path.write_text(manifest_text, encoding="utf-8")
        messages.append(
            f"updated data/manifest.json (verbs {manifest['version']}, grammar {manifest['grammar']['version']}, "
            f"furigana {manifest['furigana']['version']}"
            + (f", words {manifest['words']['version']}" if "words" in manifest else "")
            + (f", counters {manifest['counters']['version']}" if "counters" in manifest else "")
            + f", forms {manifest['forms']['version']})"
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
    parser.add_argument("--counters-version", help="force the counters.json manifest version")
    parser.add_argument("--forms-version", help="force the forms.json manifest version")
    parser.add_argument("--bundled-forms-path", default=str(DEFAULT_BUNDLED_FORMS_PATH),
                        help="where to write the app's bundled copy of data/forms.json")
    parser.add_argument("--bundled-counters-path", default=str(DEFAULT_BUNDLED_COUNTERS_PATH),
                        help="where to write the app's bundled copy of data/counters.json")
    parser.add_argument("--bundled-data-dir", default=str(DEFAULT_BUNDLED_DATA_DIR),
                        help="where to write the app's bundled copies of verbs, grammar, furigana and words")
    parser.add_argument("--ref", type=valid_ref, help="release tag the app fetches the data files from (see docs/security/data-signing.md)")
    parser.add_argument("--published-ref", default=PUBLISHED_REF,
                        help="git ref of the published data that no verb id may disappear from "
                             f"(default {PUBLISHED_REF}; '' skips the check; skipped if the ref is not available)")
    args = parser.parse_args(argv)
    published = published_verbs_doc(args.published_ref) if args.published_ref else None
    code, messages = run(args.data_dir, args.check, args.verbs_version, args.grammar_version,
                         args.furigana_version, bundled_forms_path=args.bundled_forms_path, ref=args.ref,
                         bundled_counters_path=args.bundled_counters_path,
                         bundled_data_dir=args.bundled_data_dir,
                         words_version=args.words_version, counters_version=args.counters_version,
                         published_verbs=published, forms_version=args.forms_version)
    for line in messages:
        print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
