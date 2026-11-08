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


class PublicStampTests(unittest.TestCase):
    def test_name_is_written_only_when_given(self):
        entry = counters_doc()["counters"][0]
        self.assertEqual(mr.stamp(entry, "native", "2026-11-07", name="Aiko")["name"], "Aiko")
        self.assertNotIn("name", mr.stamp(entry, "teacher", "2026-11-07"))
        self.assertEqual(mr.stamp(entry, "native", "2026-11-07")["by"], "native")


def verbs_doc():
    def one(dict_form, kanji, example_id, **extra):
        return {"type": "ru", "label": "Ru-verb", "dict": dict_form, "kanji": kanji, "meaning": "m",
                "description": "d", "forms": {"te": dict_form[:-1] + "て"},
                "examples": [{"id": example_id, "form": "te", "jp": kanji, "en": "e"}], "collocations": [], **extra}
    return {"version": "1.0.0", "description": "d",
            "verbs": [one("きる", "切る", "e1aaaa", id="きる:切る"), one("たべる", "食べる", "e2aaaa")]}


class StampVerbsWordsExamplesTests(unittest.TestCase):
    def test_stamps_a_verb_by_its_id_leaving_others_alone(self):
        doc = verbs_doc()
        mr.stamp_entries(doc["verbs"], ["きる:切る"], ud.verb_id, ud.VERB_GENERATED, "teacher", "2026-11-08",
                         noun="verb")
        cut, eat = doc["verbs"]
        self.assertEqual(ud.check_reviews([cut], ud.VERB_GENERATED, key=ud.verb_id), [])
        self.assertEqual(cut["review"]["by"], "teacher")
        self.assertNotIn("review", eat)
        self.assertNotIn("review", cut["examples"][0])

    def test_stamps_an_example_by_its_stable_id(self):
        doc = verbs_doc()
        examples = [ex for v in doc["verbs"] for ex in v["examples"]]
        mr.stamp_entries(examples, ["e2aaaa"], lambda e: e["id"], (), "native", "2026-11-08", name="Aiko",
                         noun="example")
        self.assertEqual(doc["verbs"][1]["examples"][0]["review"]["name"], "Aiko")
        self.assertNotIn("review", doc["verbs"][0]["examples"][0])
        self.assertNotIn("review", doc["verbs"][1])

    def test_stamps_a_word_by_class_and_dict(self):
        words = [{"class": "i-adjective", "dict": "たかい", "meaning": "tall", "forms": {"te": "たかくて"}}]
        mr.stamp_entries(words, ["i-adjective:たかい"], ud.word_id, ud.WORD_GENERATED, "owner", "2026-11-08",
                         noun="word")
        self.assertEqual(ud.check_reviews(words, ud.WORD_GENERATED, key=ud.word_id), [])

    def test_unknown_example_id_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "no example with id 'zzzzzz'"):
            mr.stamp_entries([], ["zzzzzz"], lambda e: e["id"], (), "teacher", "2026-11-08", noun="example")

    def test_main_writes_verbs_json_that_update_data_accepts(self):
        import tempfile
        from pathlib import Path
        d = Path(tempfile.mkdtemp())
        for f in mr.DATA_DIR.glob("*.json"):
            (d / f.name).write_bytes(f.read_bytes())
        first = json.loads((d / "verbs.json").read_text(encoding="utf-8"))["verbs"][0]
        self.assertEqual(mr.main(["examples", first["examples"][0]["id"], "--by", "teacher", "--on", "2026-11-08",
                                  "--data-dir", str(d)]), 0)
        self.assertEqual(mr.main(["verbs", ud.verb_id(first), "--by", "teacher", "--on", "2026-11-08",
                                  "--data-dir", str(d)]), 0)
        self.assertEqual(mr.main(["words", "i-adjective:いい", "--by", "teacher", "--on", "2026-11-08",
                                  "--data-dir", str(d)]), 0)
        before = (d / "verbs.json").read_text(encoding="utf-8")
        code, messages = ud.run(d)  # make data: only the manifest's hashes move
        self.assertEqual(code, 0, messages)
        self.assertEqual((d / "verbs.json").read_text(encoding="utf-8"), before)
