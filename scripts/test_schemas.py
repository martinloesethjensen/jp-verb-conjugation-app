import copy
import json
import re
import unittest
from pathlib import Path

import json_schema
import stable_ids
import update_data

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_DIR = ROOT / "schema"
NAMES = ("verbs", "words", "counters", "grammar", "furigana", "forms", "kanji")


def load_schema(name):
    return json.loads((SCHEMA_DIR / f"{name}.schema.json").read_text(encoding="utf-8"))


def load_data(name):
    return stable_ids.loads((ROOT / "data" / f"{name}.json").read_text(encoding="utf-8"))


def first_slot_of_each_kind(dataset, doc):
    """(kind, label) for the first id slot of each kind: "たべる example 1" is an "example",
    "n-desu usage 1 example 2" a "usage example"."""
    seen = {}
    for label, _ in stable_ids.id_slots(dataset, doc):
        words = [w for w in label.split(" ")[1:] if not w.isdigit()]
        seen.setdefault(" ".join(words), label)
    return list(seen.items())


class SchemaTests(unittest.TestCase):
    def test_every_schema_uses_only_the_supported_subset(self):
        for name in NAMES:
            with self.subTest(name):
                self.assertEqual(json_schema.check_schema(load_schema(name)), [])

    def test_the_published_data_matches_its_schema(self):
        for name in NAMES:
            with self.subTest(name):
                self.assertEqual(json_schema.validate(load_data(name), load_schema(name)), [])

    def test_the_stable_id_pattern_is_the_one_the_pipeline_uses(self):
        for name in ("verbs", "counters", "grammar"):
            self.assertEqual(load_schema(name)["$defs"]["stableId"]["pattern"], stable_ids.ID_PATTERN.pattern)

    def test_review_stamp_reviewers_match_the_pipeline(self):
        for name in ("counters", "grammar"):
            self.assertEqual(load_schema(name)["$defs"]["reviewStamp"]["properties"]["by"]["enum"],
                             list(update_data.REVIEWERS))

    def test_every_kind_of_stable_id_slot_is_required_by_the_schema(self):
        for name in ("verbs", "counters", "grammar"):
            doc = load_data(name)
            kinds = first_slot_of_each_kind(name, doc)
            self.assertGreater(len(kinds), 0)
            for kind, label in kinds:
                with self.subTest(name=name, slot=label):
                    broken = copy.deepcopy(doc)
                    dict(stable_ids.id_slots(name, broken))[label].pop("id")
                    self.assertTrue(any("missing required property 'id'" in p
                                        for p in json_schema.validate(broken, load_schema(name))))

    def test_the_shared_invalid_fixtures_are_rejected_for_the_stated_reason(self):
        fixtures = json.loads((SCHEMA_DIR / "fixtures" / "invalid.json").read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(fixtures), 10)
        self.assertEqual(len({f["name"] for f in fixtures}), len(fixtures))
        for fixture in fixtures:
            with self.subTest(fixture["name"]):
                problems = json_schema.validate(fixture["doc"], load_schema(fixture["dataset"]))
                # Exactly one problem, so each fixture tests one rule (plan 3's Rust tests rely on that).
                self.assertEqual(len(problems), 1, problems)
                self.assertIn(fixture["error"], problems[0])


if __name__ == "__main__":
    unittest.main()
