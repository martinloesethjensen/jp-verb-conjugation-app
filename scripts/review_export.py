"""Apply a review-site export batch (GET /api/export) to the parsed data files.

Pure: no files, no network. `scripts/review_pull.py` reads the files, calls `apply_batch`, writes them back
and prints `summary_markdown`. The batch format is documented in the review site spec ("Accepted additions")
and in review/api/src/export_routes.rs.

Order: requested stamps are checked against the data first; then changes, additions, readings and removals;
then stamps are written, and any existing stamp whose entry this batch changed is removed. Something that
can't be applied (its target or parent is gone, a reading clashes) is skipped and reported, never raised.
"""
import copy
from dataclasses import dataclass, field

import mark_reviewed as mr
import update_data as ud

# The top-level list each dataset keeps its entries in.
TOP = {"verbs": "verbs", "words": "words", "counters": "counters", "grammar": "grammar"}
# The list a part of each kind lives in, under its parent.
PART_LISTS = {"example": "examples", "collocation": "collocations", "usage": "usages", "pitfall": "pitfalls",
              "thing": "things"}
# Where examples can be: the entry's own list, and those of its usages, pitfalls and contrasts.
EXAMPLE_HOLDERS = ("usages", "pitfalls", "contrasts")
# What a stamp's hash leaves out, by dataset (an entry's stamp) or "example" (a verb example's own stamp).
STAMPED = ud.STAMP_GENERATED
CREDIT_ROLES = {"owner": "the owner", "teacher": "a teacher", "native": "a native speaker"}


@dataclass
class Line:
    text: str
    credit: str = ""
    section: str = ""


@dataclass
class Report:
    applied: list = field(default_factory=list)
    skipped: list = field(default_factory=list)
    notes: list = field(default_factory=list)
    stamps_written: list = field(default_factory=list)
    stamps_removed: list = field(default_factory=list)
    suggestion_ids: list = field(default_factory=list)
    stamp_ids: list = field(default_factory=list)


def credit_of(credit):
    """The public name, else the role's wording."""
    return credit.get("name") or CREDIT_ROLES.get(credit.get("role"), "a reviewer")


def entry_id(dataset, entry):
    if dataset == "verbs":
        return ud.verb_id(entry)
    if dataset == "words":
        return ud.word_id(entry)
    return entry["id"]


def entry_of(docs, dataset, wanted):
    """The entry with id `wanted`, or None."""
    for entry in docs[dataset][TOP[dataset]]:
        if entry_id(dataset, entry) == wanted:
            return entry
    return None


def locate(entry, kind, item_id):
    """`(list, index)` of the part `item_id` of `kind` under `entry`, or None."""
    lists = [entry.get(PART_LISTS[kind], [])]
    if kind == "example":
        lists += [holder.get("examples", []) for key in EXAMPLE_HOLDERS for holder in entry.get(key, [])]
    for items in lists:
        for index, item in enumerate(items):
            if isinstance(item, dict) and item.get("id") == item_id:
                return items, index
    return None


def _target(docs, s):
    """The object a change edits, or None when it's gone."""
    entry = entry_of(docs, s["dataset"], s["entry_id"])
    if entry is None or s["kind"] == "entry":
        return entry
    found = locate(entry, s["kind"], s["item_id"])
    return found[0][found[1]] if found else None


def _parent_list(docs, s):
    """The list an addition is appended to, or None when its parent is gone."""
    dataset = s["dataset"]
    if s["kind"] == "entry":
        return docs[dataset][TOP[dataset]]
    entry = entry_of(docs, dataset, s["entry_id"])
    if entry is None:
        return None
    if s["parent_kind"] in (None, "entry"):
        return entry.setdefault(PART_LISTS[s["kind"]], [])
    found = locate(entry, s["parent_kind"], s["parent_id"])
    return found[0][found[1]].setdefault(PART_LISTS[s["kind"]], []) if found else None


def stamp_target(docs, t):
    """`(object, generated)` a stamp request is about, or None when it's gone or can't take a stamp: entries of
    the stamped datasets, and verb examples (grammar and counter examples are covered by their entry's stamp)."""
    dataset, kind = t["dataset"], t["kind"]
    if kind == "entry" and dataset in STAMPED:
        entry = entry_of(docs, dataset, t["item_id"])
        return (entry, STAMPED[dataset]) if entry is not None else None
    if kind == "example" and dataset == "verbs":
        entry = entry_of(docs, dataset, t["entry_id"])
        found = locate(entry, "example", t["item_id"]) if entry is not None else None
        return (found[0][found[1]], STAMPED["example"]) if found else None
    return None


def stampable(t):
    return (t["kind"] == "entry" and t["dataset"] in STAMPED) or (t["kind"], t["dataset"]) == ("example", "verbs")


def covers(t, part):
    """Whether a stamp request `t` vouches for the batch part `(dataset, entry id, kind, item id)`: an entry's
    stamp covers the whole entry, except a verb's examples, which carry their own."""
    dataset, entry, kind, item = part
    if dataset != t["dataset"]:
        return False
    if t["kind"] == "example":
        return kind == "example" and item == t["item_id"]
    return entry == t["item_id"] and not (dataset == "verbs" and kind == "example")


def stamped_parts(dataset, entry):
    """`(object, generated, kind, id)` for every stamp under `entry`: its own, and for a verb each example's."""
    out = [(entry, STAMPED[dataset], "entry", entry_id(dataset, entry))]
    if dataset == "verbs":
        out += [(ex, STAMPED["example"], "example", ex.get("id")) for ex in entry.get("examples", [])
                if isinstance(ex, dict)]
    return out


def apply_batch(batch, docs, today):
    """Applies `batch` to `docs` (mutated) and reports what happened."""
    report = Report()
    suggestions = batch.get("suggestions", [])
    gone = "no longer in the data"

    def skip(s, why):
        report.skipped.append(Line(f"{s['item_title']} (suggestion {s['id']}): {why}", credit_of(s["credit"])))

    def done(s, verb, section):
        report.applied.append(Line(f"{verb} {s['item_title']}", credit_of(s["credit"]), section))
        report.suggestion_ids.append(s["id"])

    parts = {(s["dataset"], s["entry_id"], s["kind"], s["item_id"])
             for s in suggestions if s["action"] in ("change", "add", "delete")}
    touched = {(dataset, entry) for dataset, entry, _, _ in parts}

    # 1. Stamps vouch for what the reviewers saw: check them before anything changes.
    stamps = []
    for t in batch.get("stamps", []):
        title = f"{t['item_title']} (stamp {t['id']})"
        found = stamp_target(docs, t)
        if not stampable(t):
            report.skipped.append(Line(f"{title}: can't be stamped"))
        elif found is None:
            report.skipped.append(Line(f"{title}: {gone}"))
        elif ud.review_hash(*found) != t["content_hash"]:
            report.skipped.append(Line(f"{title}: changed since it was stamped"))
        elif any(covers(t, part) for part in parts):
            report.skipped.append(Line(f"{title}: this batch also changes it; stamp it again after the next load"))
        else:
            stamps.append(t)

    applied = []
    # 2. Changes. A change carries its whole form, built from the data it was accepted against, so only the
    # keys whose value differs from the data before this batch are written: two changes to different fields
    # of one item both land, and a later change can't put back what an earlier one replaced.
    pristine = copy.deepcopy(docs)
    missing = object()
    written = {}  # (dataset, kind, item id, key) -> the value an earlier change wrote
    for s in (s for s in suggestions if s["action"] == "change"):
        target, before = _target(docs, s), _target(pristine, s)
        if target is None or before is None:
            skip(s, gone)
            continue
        if s.get("stale"):
            skip(s, "the data changed since it was accepted; apply it by hand or suggest it again")
            continue
        edits = {key: s["item"].get(key, missing) for key in s["editable"] or []
                 if s["item"].get(key, missing) != before.get(key, missing)}
        where = (s["dataset"], s["kind"], s["item_id"])
        if any(written.get((*where, key), value) != value for key, value in edits.items()):
            skip(s, "another change in this batch set the same field differently; apply it by hand")
            continue
        for key, value in edits.items():
            written[(*where, key)] = value
            if value is missing:
                target.pop(key, None)
            else:
                target[key] = value
        done(s, "Changed", "Changes")
        applied.append(s)

    # 3. Additions, at the end of their parent's list (or of the file).
    for s in (s for s in suggestions if s["action"] == "add"):
        items = _parent_list(docs, s)
        if items is None:
            skip(s, gone)
            continue
        items.append(s["item"])
        done(s, "Added", "Added")
        applied.append(s)

    # 4. Readings for new kanji.
    readings = docs["furigana"]["readings"]
    for s in applied:
        for kanji, reading in (s.get("furigana") or {}).items():
            existing = readings.get(kanji)
            if existing is None:
                readings[kanji] = reading
            elif existing != reading:
                report.skipped.append(Line(
                    f"reading {kanji} = {reading} from {s['item_title']}: furigana.json already says {existing}",
                    credit_of(s["credit"])))

    # 5. Removals last, so a change to the same item can't resurrect it.
    for s in (s for s in suggestions if s["action"] == "delete"):
        dataset = s["dataset"]
        if s["kind"] == "entry":
            entry = entry_of(docs, dataset, s["entry_id"])
            if entry is None:
                skip(s, gone)
                continue
            docs[dataset][TOP[dataset]].remove(entry)
        else:
            entry = entry_of(docs, dataset, s["entry_id"])
            found = locate(entry, s["kind"], s["item_id"]) if entry is not None else None
            if found is None:
                skip(s, gone)
                continue
            found[0].pop(found[1])
        done(s, "Removed", "Removed")

    for s in (s for s in suggestions if s["action"] == "note"):
        report.notes.append(Line(f"{s['item_title']}: {s['comment']}", credit_of(s["credit"])))
        report.suggestion_ids.append(s["id"])

    # 6. Stamps: write the requested ones; drop old ones this batch made stale.
    for t in stamps:
        target, generated = stamp_target(docs, t)
        target["review"] = mr.stamp(target, t["by"], today, generated, t.get("name"))
        report.stamps_written.append(Line(t["item_title"], credit_of({"role": t["by"], "name": t.get("name")})))
        report.stamp_ids.append(t["id"])
    for dataset, wanted in sorted(touched):
        entry = entry_of(docs, dataset, wanted) if dataset in STAMPED else None
        if entry is None:
            continue
        for obj, generated, kind, item_id in stamped_parts(dataset, entry):
            if "review" in obj and obj["review"].get("sha256") != ud.review_hash(obj, generated):
                title = next((s["item_title"] for s in suggestions if s["dataset"] == dataset
                              and s["kind"] == kind and s["item_id"] == item_id), item_id)
                del obj["review"]
                report.stamps_removed.append(Line(f"{title}: changed, needs a new review"))
    report.suggestion_ids.sort()
    return report


def summary_markdown(report):
    """The PR body: what changed and who to credit (public names or roles only)."""
    out = ["## Review pull", ""]

    def section(title, lines):
        if lines:
            out.extend([f"### {title}", ""])
            out.extend(f"- {line.text} ({line.credit})" if line.credit else f"- {line.text}" for line in lines)
            out.append("")

    for name in ("Changes", "Added", "Removed"):
        section(name, [line for line in report.applied if line.section == name])
    section("Stamps", report.stamps_written + report.stamps_removed)
    section("Skipped", report.skipped)
    section("Notes for you", report.notes)
    ids = ", ".join(str(i) for i in report.suggestion_ids) or "none"
    stamp_ids = ", ".join(str(i) for i in report.stamp_ids) or "none"
    out.append(f"Site suggestion ids: {ids}. Stamp ids: {stamp_ids}.")
    return "\n".join(out) + "\n"
