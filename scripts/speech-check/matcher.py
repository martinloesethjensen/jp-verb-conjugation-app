"""Prototype verb matcher for the speech check (#143). Throwaway: #144/#145 replace it.

This is the "hybrid T" matcher from the Sentence lens research (#142), unchanged in
behaviour, so transcripts are scored with the same rules the typed baseline was:

1. CFStringTokenizer token starts gate where a match may begin, and the match must
   end on a token boundary.
2. The longest reverse-index surface (every form in data/verbs.json, kana plus the
   derived kanji spelling) says which verb and form it is.
3. Tail rules extend the match through stacked auxiliaries (呼ば+れました, 食べ+させられ+なかった).
4. A token-shape rule greys verbs the app lacks (降っ+たら).

match(text, tokens) takes tokens from `speechcheck tokenize` and returns
[(start, span, {(verb, form, script)}, chain)].
"""
import json
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
VERBS = json.loads((REPO / "data" / "verbs.json").read_text())["verbs"]

KANJI = lambda c: "一" <= c <= "鿿" or c == "々"


def vid(v):
    return v.get("id") or v["dict"]


def kanji_spelling(v, surface):
    """Kana surface -> kanji spelling, or None. 食べる/たべる: 食 replaces た."""
    kanji, dict_ = v.get("kanji"), v["dict"]
    if not kanji:
        return None
    n = 0
    while n < min(len(kanji), len(dict_)) and kanji[-1 - n] == dict_[-1 - n]:
        n += 1
    k_stem, r_stem = kanji[: len(kanji) - n], dict_[: len(dict_) - n]
    if surface.startswith(r_stem):
        return k_stem + surface[len(r_stem):]
    if v["type"] == "irr." and dict_ == "くる" and surface[0] in "きこ":
        return "来" + surface[1:]
    return None


def _build():
    index = defaultdict(set)  # surface -> {(verb, form, script)}
    for v in VERBS:
        items = dict(v["forms"])
        items.setdefault("short_pos", v["dict"])
        for fid, surface in items.items():
            if not surface:
                continue
            for s in surface.split("/"):
                s = s.strip()
                index[s].add((vid(v), fid, "kana"))
                k = kanji_spelling(v, s)
                if k and k != s:
                    index[k].add((vid(v), fid, "kanji"))
    return index


INDEX = _build()
MAXLEN = max(map(len, INDEX))

RU_TAIL = {
    "る": "plain", "ない": "plain neg", "なかった": "plain past neg", "た": "plain past",
    "ます": "polite", "ません": "polite neg", "ました": "polite past",
    "ませんでした": "polite past neg", "て": "te", "たい": "tai", "ないで": "neg te",
    "なくて": "nakute", "れば": "ba", "たら": "tara",
}
ADJ_TAIL = {"い": "", "くない": "neg", "かった": "past", "くなかった": "past neg",
            "いです": "polite", "くないです": "polite neg", "かったです": "polite past",
            "くて": "te", "くありません": "polite neg"}
AUX_AFTER_TE = {
    "しまいました": "てしまう·polite past", "しまった": "てしまう·past", "しまう": "てしまう",
    "しまいます": "てしまう·polite", "しまって": "てしまう·te",
    "いました": "ている·polite past", "います": "ている·polite", "いる": "ている",
    "いた": "ている·past", "いない": "ている·neg",
    "みたい": "てみる·tai", "みました": "てみる·polite past", "みた": "てみる·past",
    "みます": "てみる·polite", "みる": "てみる",
    "おきました": "ておく·polite past", "おいた": "ておく·past",
    "ください": "てください", "くれませんか": "てくれる·polite neg?", "くれる": "てくれる",
    "あげる": "てあげる", "もらう": "てもらう", "もいいですか": "てもいい·polite?",
    "もいいです": "てもいい·polite",
}
CONJ_TOKENS = {"た", "て", "たら", "ます", "まし", "ませ", "ない", "なかっ", "たり", "だ", "で", "ば", "う", "よう"}
DERIVED = ("passive", "causative", "causative_passive", "causative_passive_short", "potential")


def _candidates_at(text, i):
    for L in range(min(MAXLEN, len(text) - i), 0, -1):
        s = text[i:i + L]
        if s in INDEX:
            yield s, INDEX[s]


def _extend(text, i, s, t):
    """Continue past the index match with the tail grammar."""
    j = i + len(s)
    fids = {x[1] for x in t}
    rest = text[j:]
    for (_, f, _) in t:
        if f in DERIVED and s.endswith("る"):
            st = s[:-1]
            for tail in sorted(RU_TAIL, key=len, reverse=True):
                if text[i + len(st):].startswith(tail) and len(st) + len(tail) > len(s):
                    return s[:len(st)] + tail, f"{f} + {RU_TAIL[tail]}"
    if fids & {"tai", "short_neg"} and s.endswith("い"):
        for tail in sorted(ADJ_TAIL, key=len, reverse=True):
            if text[j - 1:].startswith(tail) and len(tail) > 1:
                return s[:-1] + tail, f"{'/'.join(sorted(fids))} + {ADJ_TAIL[tail] or 'plain'}"
    if "te" in fids or s.endswith(("て", "で")):
        for tail in sorted(AUX_AFTER_TE, key=len, reverse=True):
            if rest.startswith(tail):
                return s + tail, AUX_AFTER_TE[tail]
    for tail in ("ですか", "です"):
        if rest.startswith(tail) and s.endswith("い"):
            return s + tail, "+ です"
    return s, ""


MASU_STEMS = {}
DERIV = {}
for _v in VERBS:
    _surf = _v["forms"].get("masu_pos")
    if _surf and _surf.endswith("ます"):
        _stem = _surf[:-2]
        for _sp in {_stem, kanji_spelling(_v, _stem) or _stem}:
            MASU_STEMS.setdefault(_sp, set()).add((vid(_v), "stem", ""))
    for _fid, _surf in _v["forms"].items():
        if not _surf:
            continue
        _kinds = []
        if _fid in DERIVED and _surf.endswith("る"):
            _kinds.append(("ru", _surf[:-1]))
        if _fid in ("tai", "short_neg", "pot_short_neg") and _surf.endswith("い"):
            _kinds.append(("adj", _surf[:-1]))
        for _kind, _st in _kinds:
            for _sp in {_st, kanji_spelling(_v, _st) or _st}:
                DERIV.setdefault(_sp, set()).add((vid(_v), _fid, _kind))


def _deriv_at(text, i):
    best = None
    for L in range(min(14, len(text) - i), 1, -1):
        st = text[i:i + L]
        for (_, f, kind) in DERIV.get(st, ()):
            tails = RU_TAIL if kind == "ru" else {k: val for k, val in ADJ_TAIL.items() if len(k) > 1}
            for tail in sorted(tails, key=len, reverse=True):
                if text.startswith(tail, i + L):
                    span = st + tail
                    if best is None or len(span) > len(best[1]):
                        best = (i, span, DERIV[st], f"{f} + {tails[tail] or 'polite'}")
                    break
    return best


def match(text, toks):
    starts = {t["s"] for t in toks}
    bounds = starts | {t["s"] + len(t["w"]) for t in toks} | {len(text)}
    out, i = [], 0
    while i < len(text):
        hit = None
        if i in starts and text[max(0, i - 2):i] not in ("ては", "ても", "では", "でも"):
            cands = []
            d = _deriv_at(text, i)
            if d:
                cands.append(d)
            for s, t in _candidates_at(text, i):
                span, chain = _extend(text, i, s, t)
                if i + len(span) in bounds:
                    cands.append((i, span, t, chain))
            for st, t in MASU_STEMS.items():
                if text.startswith(st + "に", i) and i + len(st) in bounds:
                    cands.append((i, st, t, "stem + に (purpose)"))
            if cands:
                hit = max(cands, key=lambda c: len(c[1]))
            else:
                k = [t for t in toks if t["s"] == i][0]
                nxt = [t for t in toks if t["s"] == i + len(k["w"])]
                w = k["w"]
                verbish = KANJI(w[0]) and (len(w) == 1 or not KANJI(w[-1])) and not w.endswith(("かっ", "く", "しい"))
                lone_ok = len(w) > 1 or (nxt and nxt[0]["w"] not in ("で", "だ", "ば", "う"))
                if verbish and lone_ok and nxt and nxt[0]["w"] in CONJ_TOKENS:
                    j = i + len(w)
                    for t in toks:
                        if t["s"] == j and (t["w"] in CONJ_TOKENS or t["w"] in (
                                "い", "いる", "しまい", "しまっ", "は", "いけ", "ませ", "ん", "ください")):
                            j += len(t["w"])
                    hit = (i, text[i:j], {("?", "unknown", "")}, "not in the app yet")
        if hit:
            out.append(hit)
            i += len(hit[1])
        else:
            i += 1
    return out
