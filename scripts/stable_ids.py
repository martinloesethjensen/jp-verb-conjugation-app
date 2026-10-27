"""Stable ids for the reviewable items inside entries: example sentences, grammar usages, pitfalls and counter
things. The review site points suggestions at these ids, so they must survive items being added, removed or
reordered. Verbs, words, counters and grammar points already have their own ids.

An id is 6 characters from ALPHABET (no l, o, 0 or 1), unique within its file, and the first key of its object.
`scripts/assign_ids.py` fills in missing ones; `scripts/update_data.py` fails while any is missing.
"""
import re
import secrets

ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789"
ID_PATTERN = re.compile(r"^[a-km-np-z2-9]{6}$")


def new_id(taken):
    """A fresh id not in `taken`; it is added to `taken`."""
    while True:
        candidate = "".join(secrets.choice(ALPHABET) for _ in range(6))
        if candidate not in taken:
            taken.add(candidate)
            return candidate


def _examples(owner, label):
    return [(f"{label} example {n}", example) for n, example in enumerate(owner.get("examples") or [], 1)]


def _sections(owner, key, noun, label):
    slots = []
    for n, section in enumerate(owner.get(key) or [], 1):
        section_label = f"{label} {noun} {n}"
        slots.append((section_label, section))
        slots.extend(_examples(section, section_label))
    return slots


def id_slots(dataset, doc):
    """(label, object) for every object in `doc` that must carry an id, in document order."""
    slots = []
    if dataset == "verbs":
        for verb in doc.get("verbs") or []:
            slots.extend(_examples(verb, verb.get("id") or verb.get("dict")))
    elif dataset == "counters":
        for counter in doc.get("counters") or []:
            name = counter.get("id")
            slots.extend((f"{name} thing {n}", thing) for n, thing in enumerate(counter.get("things") or [], 1))
            slots.extend(_examples(counter, name))
            slots.extend(_sections(counter, "pitfalls", "pitfall", name))
    elif dataset == "grammar":
        for point in doc.get("grammar") or []:
            name = point.get("id")
            slots.extend(_sections(point, "usages", "usage", name))
            slots.extend(_sections(point, "pitfalls", "pitfall", name))
    else:
        raise ValueError(f"no stable ids for dataset {dataset!r}")
    return slots


def check_stable_ids(dataset, doc):
    """Problems with the stable ids in `doc`: missing, malformed or used twice."""
    problems, seen = [], {}
    for label, item in id_slots(dataset, doc):
        if "id" not in item:
            problems.append(f"{label} has no id: run scripts/assign_ids.py")
            continue
        item_id = item["id"]
        if not isinstance(item_id, str) or not ID_PATTERN.match(item_id):
            problems.append(f"{label}: id {item_id!r} is not 6 characters from the id alphabet")
        elif item_id in seen:
            problems.append(f"{label}: id {item_id!r} is also used by {seen[item_id]}")
        else:
            seen[item_id] = label
    return problems
