import copy
import json
import tempfile
import unittest
from pathlib import Path

import update_data as ud


def verb(dict_form, short_pos, short_neg, short_past, short_past_neg):
    return {
        "dict": dict_form,
        "forms": {
            "short_pos": short_pos,
            "short_neg": short_neg,
            "short_past": short_past,
            "short_past_neg": short_past_neg,
        },
    }


def valid_grammar():
    return {
        "version": "1.0.0",
        "description": "d",
        "grammar": [
            {
                "id": "n-desu",
                "title": "んです",
                "summary": "s",
                "level": "beginner",
                "usages": [
                    {"heading": "h", "explanation": "e", "examples": [{"jp": "あ", "en": "a"}]}
                ],
                "attachment": [
                    {"word_class": "verb", "pattern": "p", "example": "x"}
                ],
                "conjugations": [{"form": "んです", "register": "polite"}],
                "pitfalls": [{"heading": "h", "explanation": "e", "examples": []}],
                "related": [],
            }
        ],
    }


class NdFormsTests(unittest.TestCase):
    def test_regular_verb(self):
        v = verb("たべる", "たべる", "たべない", "たべた", "たべなかった")
        self.assertEqual(
            ud.nd_forms(v["forms"]),
            {
                "nd_pos": "たべるんです",
                "nd_neg": "たべないんです",
                "nd_past": "たべたんです",
                "nd_past_neg": "たべなかったんです",
                "nd_casual_pos": "たべるんだ",
                "nd_casual_neg": "たべないんだ",
                "nd_casual_past": "たべたんだ",
                "nd_casual_past_neg": "たべなかったんだ",
            },
        )

    def test_irregular_verb_uses_its_own_plain_forms(self):
        forms = verb("くる", "くる", "こない", "きた", "こなかった")["forms"]
        result = ud.nd_forms(forms)
        self.assertEqual(result["nd_neg"], "こないんです")
        self.assertEqual(result["nd_past"], "きたんです")

    def test_apply_is_idempotent(self):
        doc = {"verbs": [verb("する", "する", "しない", "した", "しなかった")]}
        self.assertTrue(ud.apply_nd_forms(doc))
        self.assertFalse(ud.apply_nd_forms(doc))

    def test_apply_repairs_a_stale_value(self):
        doc = {"verbs": [verb("する", "する", "しない", "した", "しなかった")]}
        ud.apply_nd_forms(doc)
        doc["verbs"][0]["forms"]["nd_pos"] = "wrong"
        self.assertTrue(ud.apply_nd_forms(doc))
        self.assertEqual(doc["verbs"][0]["forms"]["nd_pos"], "するんです")


class DumpTests(unittest.TestCase):
    def test_examples_stay_on_one_line_and_kana_is_not_escaped(self):
        doc = {"verbs": [{"examples": [{"form": "te", "jp": "たべて。", "en": "Eat."}]}]}
        text = ud.dump_verbs(doc)
        self.assertIn('{ "form": "te", "jp": "たべて。", "en": "Eat." }', text)
        self.assertTrue(text.endswith("\n"))


class ValidateGrammarTests(unittest.TestCase):
    def test_valid_document_has_no_errors(self):
        self.assertEqual(ud.validate_grammar(valid_grammar()), [])

    def test_bad_level(self):
        doc = valid_grammar()
        doc["grammar"][0]["level"] = "expert"
        self.assertTrue(any("level" in e for e in ud.validate_grammar(doc)))

    def test_bad_word_class(self):
        doc = valid_grammar()
        doc["grammar"][0]["attachment"][0]["word_class"] = "adverb"
        self.assertTrue(any("word_class" in e for e in ud.validate_grammar(doc)))

    def test_bad_register(self):
        doc = valid_grammar()
        doc["grammar"][0]["conjugations"][0]["register"] = "rude"
        self.assertTrue(any("register" in e for e in ud.validate_grammar(doc)))

    def test_duplicate_ids(self):
        doc = valid_grammar()
        doc["grammar"].append(copy.deepcopy(doc["grammar"][0]))
        self.assertTrue(any("duplicate id" in e for e in ud.validate_grammar(doc)))

    def test_dangling_related_id(self):
        doc = valid_grammar()
        doc["grammar"][0]["related"] = ["nope"]
        self.assertTrue(any("related" in e for e in ud.validate_grammar(doc)))

    def test_pitfall_without_explanation(self):
        doc = valid_grammar()
        doc["grammar"][0]["pitfalls"][0]["explanation"] = ""
        self.assertTrue(any("pitfall" in e for e in ud.validate_grammar(doc)))

    def test_usage_without_examples(self):
        doc = valid_grammar()
        doc["grammar"][0]["usages"][0]["examples"] = []
        self.assertTrue(any("example" in e for e in ud.validate_grammar(doc)))


class ManifestTests(unittest.TestCase):
    def test_unchanged_files_keep_versions(self):
        existing = {
            "version": "1.2.0",
            "sha256": ud.sha256_hex(b"v"),
            "grammar": {"version": "3.0.0", "sha256": ud.sha256_hex(b"g")},
        }
        result = ud.build_manifest(existing, b"v", b"g")
        self.assertEqual(result["version"], "1.2.0")
        self.assertEqual(result["grammar"]["version"], "3.0.0")

    def test_changed_files_bump_minor(self):
        existing = {
            "version": "1.2.0",
            "sha256": "old",
            "grammar": {"version": "3.0.0", "sha256": "old"},
        }
        result = ud.build_manifest(existing, b"v", b"g")
        self.assertEqual(result["version"], "1.3.0")
        self.assertEqual(result["grammar"]["version"], "3.1.0")
        self.assertEqual(result["sha256"], ud.sha256_hex(b"v"))

    def test_missing_grammar_block_starts_at_1_0_0(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": ud.sha256_hex(b"v")}, b"v", b"g")
        self.assertEqual(result["version"], "1.0.0")
        self.assertEqual(result["grammar"], {"version": "1.0.0", "sha256": ud.sha256_hex(b"g")})

    def test_explicit_versions_win(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": "old"}, b"v", b"g", "2.0.0", "9.9.9")
        self.assertEqual(result["version"], "2.0.0")
        self.assertEqual(result["grammar"]["version"], "9.9.9")


class RunTests(unittest.TestCase):
    def make_dir(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        d = Path(tmp.name)
        verbs = {
            "version": "1.0.0",
            "description": "d",
            "verbs": [verb("する", "する", "しない", "した", "しなかった")],
        }
        (d / "verbs.json").write_text(ud.dump_verbs(verbs), encoding="utf-8")
        (d / "grammar.json").write_text(json.dumps(valid_grammar(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (d / "manifest.json").write_text(json.dumps({"version": "1.0.0", "sha256": "x"}) + "\n", encoding="utf-8")
        return d

    def test_check_reports_stale_then_run_fixes_then_check_passes(self):
        d = self.make_dir()
        code, _ = ud.run(d, check=True)
        self.assertEqual(code, 1)
        code, _ = ud.run(d)
        self.assertEqual(code, 0)
        code, _ = ud.run(d, check=True)
        self.assertEqual(code, 0)
        written = json.loads((d / "verbs.json").read_text(encoding="utf-8"))
        self.assertEqual(written["verbs"][0]["forms"]["nd_pos"], "するんです")
        manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["sha256"], ud.sha256_hex((d / "verbs.json").read_bytes()))
        self.assertEqual(manifest["grammar"]["sha256"], ud.sha256_hex((d / "grammar.json").read_bytes()))

    def test_invalid_grammar_blocks_everything_and_writes_nothing(self):
        d = self.make_dir()
        bad = valid_grammar()
        bad["grammar"][0]["level"] = "expert"
        (d / "grammar.json").write_text(json.dumps(bad), encoding="utf-8")
        before = (d / "verbs.json").read_bytes()
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertEqual((d / "verbs.json").read_bytes(), before)
        self.assertTrue(any("level" in m for m in messages))


if __name__ == "__main__":
    unittest.main()
