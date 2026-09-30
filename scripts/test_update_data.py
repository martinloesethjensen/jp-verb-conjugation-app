import copy
import json
import tempfile
import unittest
from pathlib import Path

import update_data as ud


def verb(dict_form, short_pos, short_neg, short_past, short_past_neg, vtype="ru"):
    return {
        "type": vtype,
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


def potential_verb(dict_form, vtype):
    return {"type": vtype, "dict": dict_form, "forms": {}}


class PotentialFormsTests(unittest.TestCase):
    def test_ru_verb_drops_ru_and_adds_rareru(self):
        self.assertEqual(ud.potential_base(potential_verb("たべる", "ru")), "たべられる")
        self.assertEqual(ud.potential_base(potential_verb("みる", "ru")), "みられる")

    def test_every_u_verb_ending_moves_to_the_e_row(self):
        # One verb per ending present in the data.
        expected = {
            "のむ": "のめる",      # む → め
            "かう": "かえる",      # う → え
            "かく": "かける",      # く → け
            "およぐ": "およげる",  # ぐ → げ
            "はなす": "はなせる",  # す → せ
            "まつ": "まてる",      # つ → て
            "しぬ": "しねる",      # ぬ → ね
            "あそぶ": "あそべる",  # ぶ → べ
            "とる": "とれる",      # る → れ
        }
        for dict_form, base in expected.items():
            with self.subTest(dict_form):
                self.assertEqual(ud.potential_base(potential_verb(dict_form, "u")), base)

    def test_irregular_verbs(self):
        self.assertEqual(ud.potential_base(potential_verb("する", "irr.")), "できる")
        self.assertEqual(ud.potential_base(potential_verb("くる", "irr.")), "こられる")

    def test_verbs_with_no_potential_return_none(self):
        self.assertIsNone(ud.potential_base(potential_verb("ある", "u")))
        self.assertEqual(ud.potential_forms(potential_verb("ある", "u")), {})

    def test_unknown_u_verb_ending_raises(self):
        with self.assertRaises(ValueError):
            ud.potential_base(potential_verb("いき", "u"))

    def test_unknown_irregular_raises(self):
        with self.assertRaises(ValueError):
            ud.potential_base(potential_verb("べんきょうする", "irr."))

    def test_unknown_verb_type_raises(self):
        with self.assertRaises(ValueError):
            ud.potential_base(potential_verb("たべる", "weird"))

    def test_full_grid_for_a_ru_verb(self):
        self.assertEqual(
            ud.potential_forms(potential_verb("たべる", "ru")),
            {
                "potential": "たべられる",
                "pot_masu_pos": "たべられます",
                "pot_masu_neg": "たべられません",
                "pot_masu_past": "たべられました",
                "pot_masu_past_neg": "たべられませんでした",
                "pot_te": "たべられて",
                "pot_short_neg": "たべられない",
                "pot_short_past": "たべられた",
                "pot_short_past_neg": "たべられなかった",
            },
        )

    def test_full_grid_for_a_u_verb(self):
        forms = ud.potential_forms(potential_verb("のむ", "u"))
        self.assertEqual(forms["potential"], "のめる")
        self.assertEqual(forms["pot_masu_neg"], "のめません")
        self.assertEqual(forms["pot_te"], "のめて")
        self.assertEqual(forms["pot_short_past_neg"], "のめなかった")

    def test_full_grid_for_suru_uses_dekiru(self):
        forms = ud.potential_forms(potential_verb("する", "irr."))
        self.assertEqual(forms["potential"], "できる")
        self.assertEqual(forms["pot_masu_past_neg"], "できませんでした")
        self.assertEqual(forms["pot_short_neg"], "できない")

    def test_full_grid_for_kuru(self):
        forms = ud.potential_forms(potential_verb("くる", "irr."))
        self.assertEqual(forms["potential"], "こられる")
        self.assertEqual(forms["pot_masu_pos"], "こられます")
        self.assertEqual(forms["pot_short_past"], "こられた")

    def test_apply_sets_all_nine_fields_and_is_idempotent(self):
        doc = {"verbs": [potential_verb("たべる", "ru")]}
        self.assertTrue(ud.apply_potential_forms(doc))
        self.assertEqual(set(doc["verbs"][0]["forms"]), set(ud.POTENTIAL_FIELDS))
        self.assertFalse(ud.apply_potential_forms(doc))

    def test_apply_repairs_a_wrong_value(self):
        doc = {"verbs": [potential_verb("たべる", "ru")]}
        ud.apply_potential_forms(doc)
        doc["verbs"][0]["forms"]["pot_te"] = "wrong"
        self.assertTrue(ud.apply_potential_forms(doc))
        self.assertEqual(doc["verbs"][0]["forms"]["pot_te"], "たべられて")

    def test_apply_removes_stale_fields_for_a_verb_with_no_potential(self):
        doc = {"verbs": [potential_verb("ある", "u")]}
        doc["verbs"][0]["forms"]["potential"] = "ありえる"
        doc["verbs"][0]["forms"]["pot_te"] = "ありえて"
        self.assertTrue(ud.apply_potential_forms(doc))
        self.assertEqual(doc["verbs"][0]["forms"], {})

    def test_apply_leaves_unrelated_forms_alone(self):
        doc = {"verbs": [potential_verb("たべる", "ru")]}
        doc["verbs"][0]["forms"]["te"] = "たべて"
        doc["verbs"][0]["forms"]["nd_pos"] = "たべるんです"
        ud.apply_potential_forms(doc)
        self.assertEqual(doc["verbs"][0]["forms"]["te"], "たべて")
        self.assertEqual(doc["verbs"][0]["forms"]["nd_pos"], "たべるんです")


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
            "verbs": [verb("する", "する", "しない", "した", "しなかった", vtype="irr.")],
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
        self.assertEqual(written["verbs"][0]["forms"]["potential"], "できる")
        self.assertEqual(written["verbs"][0]["forms"]["pot_masu_pos"], "できます")
        manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["sha256"], ud.sha256_hex((d / "verbs.json").read_bytes()))
        self.assertEqual(manifest["grammar"]["sha256"], ud.sha256_hex((d / "grammar.json").read_bytes()))

    def test_unknown_verb_class_fails_cleanly_and_writes_nothing(self):
        d = self.make_dir()
        doc = json.loads((d / "verbs.json").read_text(encoding="utf-8"))
        doc["verbs"][0]["type"] = "u"
        doc["verbs"][0]["dict"] = "いき"  # ends in き, which no u-verb ending maps
        (d / "verbs.json").write_text(ud.dump_verbs(doc), encoding="utf-8")
        before = (d / "verbs.json").read_bytes()
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertEqual((d / "verbs.json").read_bytes(), before)
        self.assertTrue(any("いき" in m for m in messages))

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
