import json
import unittest

import mark_reviewed as mr
import update_data as ud

GRAMMAR_TEXT = """{
  "version": "1.0.0",
  "description": "d",
  "grammar": [
    {
      "id": "n-desu",
      "title": "んです",
      "summary": "s",
      "jlpt": "N5",
      "related": []
    },
    {
      "id": "hou-ga-ii",
      "title": "ほうがいい",
      "summary": "s",
      "jlpt": "N4",
      "related": []
    }
  ]
}
"""


def counters_doc():
    base = {"counter": "本", "reading": "ほん", "meaning": "m", "jlpt": "N5", "sound": "h-b", "symbol": "pencil",
            "overrides": {}, "things": [], "examples": [], "pitfalls": [], "related": []}
    return {"counters": [{"id": "hon", **base}, {"id": "hai", **base}], "groups": []}


class StampCountersTests(unittest.TestCase):
    def test_stamp_counters_sets_a_valid_stamp_on_the_named_entries_only(self):
        doc = counters_doc()
        mr.stamp_counters(doc, ["hon"], "teacher", "2026-10-24")
        hon, hai = doc["counters"]
        self.assertEqual(hon["review"]["by"], "teacher")
        self.assertEqual(hon["review"]["on"], "2026-10-24")
        self.assertNotIn("review", hai)
        self.assertEqual(ud.check_reviews(doc["counters"], ud.COUNTER_GENERATED), [])

    def test_restamping_after_an_edit_makes_it_valid_again(self):
        doc = counters_doc()
        mr.stamp_counters(doc, ["hon"], "teacher", "2026-10-24")
        doc["counters"][0]["meaning"] = "edited"
        self.assertNotEqual(ud.check_reviews(doc["counters"], ud.COUNTER_GENERATED), [])
        mr.stamp_counters(doc, ["hon"], "owner", "2026-10-25")
        self.assertEqual(ud.check_reviews(doc["counters"], ud.COUNTER_GENERATED), [])
        self.assertEqual(doc["counters"][0]["review"]["by"], "owner")

    def test_unknown_id_is_an_error(self):
        with self.assertRaises(ValueError):
            mr.stamp_counters(counters_doc(), ["nope"], "teacher", "2026-10-24")

    def test_bad_reviewer_or_date_is_an_error(self):
        with self.assertRaises(ValueError):
            mr.stamp_counters(counters_doc(), ["hon"], "nobody", "2026-10-24")
        with self.assertRaises(ValueError):
            mr.stamp_counters(counters_doc(), ["hon"], "owner", "yesterday")


class StampGrammarTextTests(unittest.TestCase):
    def test_inserts_after_the_id_line_and_keeps_the_rest_byte_for_byte(self):
        new = mr.stamp_grammar_text(GRAMMAR_TEXT, ["hou-ga-ii"], "teacher", "2026-10-24")
        lines = new.split("\n")
        i = lines.index('      "id": "hou-ga-ii",')
        self.assertTrue(lines[i + 1].startswith('      "review": { "by": "teacher", "on": "2026-10-24", "sha256": "'))
        self.assertTrue(lines[i + 1].endswith('" },'))
        removed = "\n".join(lines[:i + 1] + lines[i + 2:])
        self.assertEqual(removed, GRAMMAR_TEXT)
        doc = json.loads(new)
        self.assertEqual(ud.check_reviews(doc["grammar"]), [])
        self.assertNotIn("review", doc["grammar"][0])

    def test_restamping_replaces_the_line(self):
        once = mr.stamp_grammar_text(GRAMMAR_TEXT, ["n-desu"], "teacher", "2026-10-24")
        twice = mr.stamp_grammar_text(once, ["n-desu"], "owner", "2026-10-25")
        self.assertEqual(twice.count('"review"'), 1)
        self.assertEqual(json.loads(twice)["grammar"][0]["review"]["by"], "owner")

    def test_unknown_id_is_an_error(self):
        with self.assertRaises(ValueError):
            mr.stamp_grammar_text(GRAMMAR_TEXT, ["nope"], "teacher", "2026-10-24")


if __name__ == "__main__":
    unittest.main()
