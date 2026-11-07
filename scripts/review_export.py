"""Apply a review-site export batch (GET /api/export) to the parsed data files.

Pure: no files, no network. `scripts/review_pull.py` reads the files, calls `apply_batch`, writes them back
and prints `summary_markdown`. The batch format is documented in the review site spec ("Accepted additions")
and in review/api/src/export_routes.rs.

Order: requested stamps are checked against the data first; then changes, additions, readings and removals;
then stamps are written, and any existing stamp whose entry this batch changed is removed. Something that
can't be applied (its target or parent is gone, a reading clashes) is skipped and reported, never raised.
"""
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
# The files the pipeline stamps, and the fields each stamp's hash leaves out.
STAMPED = {"counters": ud.COUNTER_GENERATED, "grammar": ()}
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
        return entry.get("id") or entry["dict"]
    if dataset == "words":
        return f"{entry['class']}:{entry['dict']}"
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


def apply_batch(batch, docs, today):
    """Applies `batch` to `docs` (mutated) and reports what happened."""
    report = Report()
    suggestions = batch.get("suggestions", [])
    gone = "no longer in the data"

    def skip(s, why):
        report.skipped.append(Line(f"{s['item_title']}: {why}", credit_of(s["credit"])))

    def done(s, verb, section):
        report.applied.append(Line(f"{verb} {s['item_title']}", credit_of(s["credit"]), section))
        report.suggestion_ids.append(s["id"])

    touched = {(s["dataset"], s["entry_id"]) for s in suggestions if s["action"] in ("change", "add", "delete")}

    # 1. Stamps vouch for what the reviewers saw: check them before anything changes.
    stamps = []
    for t in batch.get("stamps", []):
        entry = entry_of(docs, t["dataset"], t["item_id"])
        title = t["item_title"]
        if entry is None:
            report.skipped.append(Line(f"{title}: {gone}"))
        elif ud.review_hash(entry, STAMPED[t["dataset"]]) != t["content_hash"]:
            report.skipped.append(Line(f"{title}: changed since it was stamped"))
        elif (t["dataset"], t["item_id"]) in touched:
            report.skipped.append(Line(f"{title}: this batch also changes it; stamp it again after the next load"))
        else:
            stamps.append(t)

    applied = []
    # 2. Changes: only the keys the change's form edits.
    for s in (s for s in suggestions if s["action"] == "change"):
        target = _target(docs, s)
        if target is None:
            skip(s, gone)
            continue
        for key in s["editable"] or []:
            if key in s["item"]:
                target[key] = s["item"][key]
            else:
                target.pop(key, None)
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
        dataset = t["dataset"]
        entry = entry_of(docs, dataset, t["item_id"])
        entry["review"] = mr.stamp(entry, t["by"], today, STAMPED[dataset], t.get("name"))
        report.stamps_written.append(Line(t["item_title"], credit_of({"role": t["by"], "name": t.get("name")})))
        report.stamp_ids.append(t["id"])
    for dataset, wanted in sorted(touched):
        if dataset not in STAMPED:
            continue
        entry = entry_of(docs, dataset, wanted)
        if entry is not None and "review" in entry \
                and entry["review"].get("sha256") != ud.review_hash(entry, STAMPED[dataset]):
            title = next((s["item_title"] for s in suggestions
                          if s["dataset"] == dataset and s["entry_id"] == wanted and s["kind"] == "entry"), wanted)
            del entry["review"]
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
