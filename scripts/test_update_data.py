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
                "jlpt": "N5",
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


def valid_furigana():
    return {"version": "1.0.0", "description": "d", "readings": {"食": "た"}}


READINGS = {
    "食": "た", "日本語": "にほんご", "来": "く", "来ら": "こ", "来た": "き",
    "今日": "きょう", "毎日": "まいにち", "学校": "がっこう", "買": "か", "昨日": "きのう",
    "遅": "おそ", "遅れ": "おく",
}


def potential_verb(dict_form, vtype):
    return {"type": vtype, "dict": dict_form, "forms": {}}


def aux_verb(dict_form, te, masu_pos):
    return {"type": "u", "dict": dict_form, "forms": {"te": te, "masu_pos": masu_pos}}


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


class AuxiliaryFormsTests(unittest.TestCase):
    def test_masu_stem_drops_masu(self):
        self.assertEqual(ud.masu_stem(aux_verb("たべる", "たべて", "たべます")), "たべ")
        self.assertEqual(ud.masu_stem(aux_verb("のむ", "のんで", "のみます")), "のみ")
        self.assertEqual(ud.masu_stem(aux_verb("する", "して", "します")), "し")
        self.assertEqual(ud.masu_stem(aux_verb("くる", "きて", "きます")), "き")

    def test_masu_stem_rejects_a_missing_or_malformed_masu_pos(self):
        for masu in (None, "", "ます", "たべる"):
            with self.subTest(masu):
                verb = aux_verb("たべる", "たべて", "x")
                verb["forms"]["masu_pos"] = masu
                with self.assertRaises(ValueError):
                    ud.masu_stem(verb)

    def test_full_set_for_a_ru_verb(self):
        self.assertEqual(
            ud.auxiliary_forms(aux_verb("たべる", "たべて", "たべます")),
            {
                "teiru": "たべている",
                "teiru_neg": "たべていない",
                "teiru_past": "たべていた",
                "teiru_past_neg": "たべていなかった",
                "teiru_masu_pos": "たべています",
                "teiru_masu_neg": "たべていません",
                "teiru_masu_past": "たべていました",
                "teiru_masu_past_neg": "たべていませんでした",
                "teiru_te": "たべていて",
                "teshimau": "たべてしまう",
                "teshimau_polite": "たべてしまいます",
                "teoku": "たべておく",
                "teoku_polite": "たべておきます",
                "temiru": "たべてみる",
                "temiru_polite": "たべてみます",
                "sugiru": "たべすぎる",
                "sugiru_polite": "たべすぎます",
                "yasui": "たべやすい",
                "yasui_polite": "たべやすいです",
                "nikui": "たべにくい",
                "nikui_polite": "たべにくいです",
                "nagara": "たべながら",
            },
        )

    def test_u_verbs_use_their_te_form_and_stem(self):
        forms = ud.auxiliary_forms(aux_verb("のむ", "のんで", "のみます"))
        self.assertEqual(forms["teiru"], "のんでいる")
        self.assertEqual(forms["teshimau"], "のんでしまう")
        self.assertEqual(forms["sugiru"], "のみすぎる")
        self.assertEqual(forms["nagara"], "のみながら")
        forms = ud.auxiliary_forms(aux_verb("いく", "いって", "いきます"))
        self.assertEqual(forms["teiru"], "いっている")
        self.assertEqual(forms["nikui"], "いきにくい")

    def test_irregular_verbs_need_no_special_case(self):
        forms = ud.auxiliary_forms(aux_verb("する", "して", "します"))
        self.assertEqual(forms["teiru"], "している")
        self.assertEqual(forms["sugiru"], "しすぎる")
        forms = ud.auxiliary_forms(aux_verb("くる", "きて", "きます"))
        self.assertEqual(forms["teiru_masu_pos"], "きています")
        self.assertEqual(forms["sugiru"], "きすぎる")

    def test_a_verb_in_the_exception_list_keeps_only_the_stem_forms(self):
        forms = ud.auxiliary_forms(aux_verb("ある", "あって", "あります"))
        self.assertEqual(set(forms), set(ud.STEM_AUXILIARY_FIELDS))
        self.assertEqual(forms["sugiru"], "ありすぎる")
        self.assertEqual(forms["nagara"], "ありながら")

    def test_a_missing_te_form_raises(self):
        verb = aux_verb("たべる", "x", "たべます")
        del verb["forms"]["te"]
        with self.assertRaises(ValueError):
            ud.auxiliary_forms(verb)

    def test_an_excepted_verb_does_not_need_a_te_form(self):
        verb = aux_verb("ある", "x", "あります")
        del verb["forms"]["te"]
        self.assertIn("sugiru", ud.auxiliary_forms(verb))

    def test_apply_sets_all_22_fields_and_is_idempotent(self):
        doc = {"verbs": [aux_verb("たべる", "たべて", "たべます")]}
        self.assertEqual(len(ud.AUXILIARY_FIELDS), 22)
        self.assertTrue(ud.apply_auxiliary_forms(doc))
        self.assertTrue(set(ud.AUXILIARY_FIELDS) <= set(doc["verbs"][0]["forms"]))
        self.assertFalse(ud.apply_auxiliary_forms(doc))

    def test_apply_repairs_a_wrong_value(self):
        doc = {"verbs": [aux_verb("たべる", "たべて", "たべます")]}
        ud.apply_auxiliary_forms(doc)
        doc["verbs"][0]["forms"]["nagara"] = "wrong"
        self.assertTrue(ud.apply_auxiliary_forms(doc))
        self.assertEqual(doc["verbs"][0]["forms"]["nagara"], "たべながら")

    def test_apply_removes_stale_te_fields_for_an_excepted_verb(self):
        doc = {"verbs": [aux_verb("ある", "あって", "あります")]}
        doc["verbs"][0]["forms"]["teiru"] = "あっている"
        doc["verbs"][0]["forms"]["temiru"] = "あってみる"
        self.assertTrue(ud.apply_auxiliary_forms(doc))
        forms = doc["verbs"][0]["forms"]
        self.assertNotIn("teiru", forms)
        self.assertNotIn("temiru", forms)
        self.assertIn("sugiru", forms)

    def test_apply_leaves_unrelated_forms_alone(self):
        doc = {"verbs": [aux_verb("たべる", "たべて", "たべます")]}
        doc["verbs"][0]["forms"]["potential"] = "たべられる"
        ud.apply_auxiliary_forms(doc)
        self.assertEqual(doc["verbs"][0]["forms"]["te"], "たべて")
        self.assertEqual(doc["verbs"][0]["forms"]["potential"], "たべられる")


class FuriganaScanTests(unittest.TestCase):
    def test_a_kanji_gets_its_reading_and_okurigana_stays_plain(self):
        self.assertEqual(ud.scan("食べる", READINGS), [("食", "た"), ("べる", None)])

    def test_kana_after_the_kanji_can_select_the_reading(self):
        self.assertEqual(ud.scan("来る", READINGS), [("来", "く"), ("る", None)])
        self.assertEqual(ud.scan("来られる", READINGS), [("来", "こ"), ("られる", None)])
        self.assertEqual(ud.scan("来た", READINGS), [("来", "き"), ("た", None)])

    def test_the_longest_key_wins(self):
        self.assertEqual(ud.scan("遅れた", READINGS), [("遅", "おく"), ("れた", None)])
        self.assertEqual(ud.scan("遅い", READINGS), [("遅", "おそ"), ("い", None)])

    def test_a_compound_is_one_piece(self):
        self.assertEqual(ud.scan("今日は", READINGS), [("今日", "きょう"), ("は", None)])

    def test_words_written_back_to_back_split_at_their_boundaries(self):
        self.assertEqual(ud.scan("毎日学校", READINGS), [("毎日", "まいにち"), ("学校", "がっこう")])
        self.assertEqual(ud.scan("昨日買った", READINGS), [("昨日", "きのう"), ("買", "か"), ("った", None)])

    def test_an_unknown_kanji_is_its_own_unread_piece(self):
        self.assertEqual(
            ud.scan("猫が食べる", READINGS),
            [("猫", None), ("が", None), ("食", "た"), ("べる", None)],
        )

    def test_uncovered_kanji_lists_only_the_unread_ones(self):
        self.assertEqual(ud.uncovered_kanji("猫が食べる犬", READINGS), ["猫", "犬"])
        self.assertEqual(ud.uncovered_kanji("たべる", READINGS), [])
        self.assertEqual(ud.uncovered_kanji("Drop the 食", READINGS), [])

    def test_kana_reading_spells_the_text_in_kana(self):
        self.assertEqual(ud.kana_reading("食べる", READINGS), "たべる")
        self.assertEqual(ud.kana_reading("来られる", READINGS), "こられる")
        self.assertEqual(ud.kana_reading("日本語", READINGS), "にほんご")


class ValidateFuriganaTests(unittest.TestCase):
    def test_a_valid_document_has_no_errors(self):
        self.assertEqual(ud.validate_furigana(valid_furigana()), [])

    def test_a_key_may_end_in_up_to_three_hiragana(self):
        doc = valid_furigana()
        doc["readings"] = {"来られ": "こ", "来": "く"}
        self.assertEqual(ud.validate_furigana(doc), [])

    def test_a_key_with_more_than_three_trailing_kana_is_rejected(self):
        doc = valid_furigana()
        doc["readings"] = {"来られるの": "こ"}
        self.assertTrue(any("来られるの" in e for e in ud.validate_furigana(doc)))

    def test_a_key_must_start_with_a_kanji(self):
        doc = valid_furigana()
        doc["readings"] = {"たべる": "たべる"}
        self.assertTrue(any("たべる" in e for e in ud.validate_furigana(doc)))

    def test_a_key_may_not_have_kanji_after_the_kana(self):
        doc = valid_furigana()
        doc["readings"] = {"来ら食": "こ"}
        self.assertTrue(any("来ら食" in e for e in ud.validate_furigana(doc)))

    def test_a_value_must_be_hiragana_only(self):
        for bad in ("タ", "食", "ta", "", "た べ"):
            with self.subTest(bad):
                doc = valid_furigana()
                doc["readings"] = {"食": bad}
                self.assertTrue(any("食" in e for e in ud.validate_furigana(doc)))

    def test_the_long_vowel_mark_is_allowed_in_a_value(self):
        doc = valid_furigana()
        doc["readings"] = {"食": "たー"}
        self.assertEqual(ud.validate_furigana(doc), [])

    def test_an_empty_dictionary_is_rejected(self):
        doc = valid_furigana()
        doc["readings"] = {}
        self.assertTrue(ud.validate_furigana(doc))

    def test_version_and_description_must_be_strings(self):
        doc = valid_furigana()
        doc["version"] = 1
        del doc["description"]
        errors = ud.validate_furigana(doc)
        self.assertTrue(any("version" in e for e in errors))
        self.assertTrue(any("description" in e for e in errors))


class CoverageTests(unittest.TestCase):
    def verbs_doc(self, kanji="食べる", dict_form="たべる", jp="食べた。"):
        verb_ = verb(dict_form, dict_form, "x", "x", "x")
        verb_["kanji"] = kanji
        verb_["description"] = "A verb."
        verb_["examples"] = [{"form": "short_past", "jp": jp, "en": "I ate."}]
        return {"verbs": [verb_]}

    def test_fully_covered_data_has_no_problems(self):
        self.assertEqual(ud.check_coverage(self.verbs_doc(), valid_grammar(), READINGS), [])

    def test_a_missing_reading_in_a_verb_example_is_reported_with_its_location(self):
        problems = ud.check_coverage(self.verbs_doc(jp="猫が食べた。"), valid_grammar(), READINGS)
        self.assertEqual(len(problems), 1)
        self.assertIn("猫", problems[0])
        self.assertIn("verbs", problems[0])
        self.assertIn("examples", problems[0])

    def test_a_missing_reading_in_the_kanji_field_is_reported(self):
        problems = ud.check_coverage(self.verbs_doc(kanji="猫", dict_form="ねこ"), valid_grammar(), READINGS)
        self.assertTrue(any("猫" in p and "kanji" in p for p in problems))

    def test_a_missing_reading_anywhere_in_a_lesson_is_reported(self):
        grammar = valid_grammar()
        grammar["grammar"][0]["usages"][0]["explanation"] = "Use it with 犬 only."
        problems = ud.check_coverage(self.verbs_doc(), grammar, READINGS)
        self.assertTrue(any("犬" in p and "grammar" in p and "explanation" in p for p in problems))

    def test_ids_and_other_ascii_keys_are_not_scanned_but_all_strings_are(self):
        grammar = valid_grammar()
        grammar["grammar"][0]["related"] = ["犬"]
        problems = ud.check_coverage(self.verbs_doc(), grammar, READINGS)
        self.assertTrue(any("犬" in p for p in problems))

    def test_each_verbs_kanji_must_spell_its_kana_form(self):
        self.assertEqual(ud.check_verb_kanji(self.verbs_doc(), READINGS), [])

    def test_a_reading_that_does_not_match_the_verb_is_reported(self):
        wrong = dict(READINGS, **{"食": "く"})
        problems = ud.check_verb_kanji(self.verbs_doc(), wrong)
        self.assertEqual(len(problems), 1)
        self.assertIn("たべる", problems[0])
        self.assertIn("くべる", problems[0])

    def test_verbs_without_kanji_are_skipped(self):
        doc = self.verbs_doc()
        doc["verbs"][0]["kanji"] = None
        self.assertEqual(ud.check_verb_kanji(doc, READINGS), [])


class DumpTests(unittest.TestCase):
    def test_examples_stay_on_one_line_and_kana_is_not_escaped(self):
        doc = {"verbs": [{"examples": [{"form": "te", "jp": "たべて。", "en": "Eat."}]}]}
        text = ud.dump_verbs(doc)
        self.assertIn('{ "form": "te", "jp": "たべて。", "en": "Eat." }', text)
        self.assertTrue(text.endswith("\n"))


class ValidateGrammarTests(unittest.TestCase):
    def test_valid_document_has_no_errors(self):
        self.assertEqual(ud.validate_grammar(valid_grammar()), [])

    def test_bad_jlpt(self):
        doc = valid_grammar()
        doc["grammar"][0]["jlpt"] = "expert"
        self.assertTrue(any("jlpt" in e for e in ud.validate_grammar(doc)))

    def test_missing_jlpt(self):
        doc = valid_grammar()
        del doc["grammar"][0]["jlpt"]
        self.assertTrue(any("jlpt" in e for e in ud.validate_grammar(doc)))

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

    def _two_lessons(self, a_related, b_related):
        doc = valid_grammar()
        second = copy.deepcopy(doc["grammar"][0])
        second["id"] = "other"
        doc["grammar"][0]["related"] = a_related
        second["related"] = b_related
        doc["grammar"].append(second)
        return doc

    def test_related_links_must_be_mutual(self):
        doc = self._two_lessons(["other"], [])
        errors = ud.validate_grammar(doc)
        self.assertEqual(len(errors), 1)
        self.assertIn("n-desu", errors[0])
        self.assertIn("other", errors[0])
        self.assertIn("mutual", errors[0])

    def test_mutual_related_links_pass(self):
        self.assertEqual(ud.validate_grammar(self._two_lessons(["other"], ["n-desu"])), [])

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


class FuriganaManifestTests(unittest.TestCase):
    def test_the_block_is_omitted_when_no_furigana_bytes_are_given(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": "x"}, b"v", b"g")
        self.assertNotIn("furigana", result)

    def test_a_missing_furigana_block_starts_at_1_0_0(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": "x"}, b"v", b"g", furigana_bytes=b"f")
        self.assertEqual(result["furigana"], {"version": "1.0.0", "sha256": ud.sha256_hex(b"f")})

    def test_an_unchanged_furigana_file_keeps_its_version(self):
        existing = {"version": "1.0.0", "sha256": "x", "furigana": {"version": "2.0.0", "sha256": ud.sha256_hex(b"f")}}
        result = ud.build_manifest(existing, b"v", b"g", furigana_bytes=b"f")
        self.assertEqual(result["furigana"]["version"], "2.0.0")

    def test_a_changed_furigana_file_bumps_minor(self):
        existing = {"version": "1.0.0", "sha256": "x", "furigana": {"version": "2.0.0", "sha256": "old"}}
        result = ud.build_manifest(existing, b"v", b"g", furigana_bytes=b"f")
        self.assertEqual(result["furigana"]["version"], "2.1.0")

    def test_an_explicit_furigana_version_wins(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": "x"}, b"v", b"g", furigana_bytes=b"f", furigana_version="7.7.7")
        self.assertEqual(result["furigana"]["version"], "7.7.7")

    def test_the_other_blocks_are_unaffected(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": "x"}, b"v", b"g", furigana_bytes=b"f")
        self.assertEqual(result["sha256"], ud.sha256_hex(b"v"))
        self.assertEqual(result["grammar"]["sha256"], ud.sha256_hex(b"g"))


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
        verbs["verbs"][0]["forms"].update({"te": "して", "masu_pos": "します"})
        (d / "verbs.json").write_text(ud.dump_verbs(verbs), encoding="utf-8")
        (d / "grammar.json").write_text(json.dumps(valid_grammar(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (d / "furigana.json").write_text(json.dumps(valid_furigana(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
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
        self.assertEqual(written["verbs"][0]["forms"]["teiru"], "している")
        self.assertEqual(written["verbs"][0]["forms"]["sugiru"], "しすぎる")
        manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["sha256"], ud.sha256_hex((d / "verbs.json").read_bytes()))
        self.assertEqual(manifest["grammar"]["sha256"], ud.sha256_hex((d / "grammar.json").read_bytes()))
        self.assertEqual(manifest["furigana"]["sha256"], ud.sha256_hex((d / "furigana.json").read_bytes()))

    def test_a_missing_reading_fails_cleanly_and_writes_nothing(self):
        d = self.make_dir()
        bad = valid_grammar()
        bad["grammar"][0]["summary"] = "About the 猫."
        (d / "grammar.json").write_text(json.dumps(bad, ensure_ascii=False), encoding="utf-8")
        before = {n: (d / n).read_bytes() for n in ("verbs.json", "manifest.json")}
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertTrue(any("猫" in m for m in messages))
        for name, content in before.items():
            self.assertEqual((d / name).read_bytes(), content)

    def test_a_verb_without_a_te_form_fails_cleanly_and_writes_nothing(self):
        d = self.make_dir()
        doc = json.loads((d / "verbs.json").read_text(encoding="utf-8"))
        del doc["verbs"][0]["forms"]["te"]
        (d / "verbs.json").write_text(ud.dump_verbs(doc), encoding="utf-8")
        before = {n: (d / n).read_bytes() for n in ("verbs.json", "manifest.json")}
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertTrue(any("auxiliary" in m and "する" in m for m in messages))
        for name, content in before.items():
            self.assertEqual((d / name).read_bytes(), content)

    def test_a_verb_whose_kanji_does_not_match_its_kana_fails_cleanly(self):
        d = self.make_dir()
        doc = json.loads((d / "verbs.json").read_text(encoding="utf-8"))
        doc["verbs"][0]["kanji"] = "食べる"   # the fixture verb is する, not たべる
        (d / "verbs.json").write_text(ud.dump_verbs(doc), encoding="utf-8")
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertTrue(any("する" in m and "たべる" in m for m in messages))

    def test_an_invalid_furigana_file_blocks_everything(self):
        d = self.make_dir()
        (d / "furigana.json").write_text(json.dumps({"version": "1", "description": "d", "readings": {"食": "タ"}}, ensure_ascii=False), encoding="utf-8")
        before = (d / "verbs.json").read_bytes()
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertEqual((d / "verbs.json").read_bytes(), before)
        self.assertTrue(any("食" in m for m in messages))

    def test_a_long_list_of_problems_is_capped(self):
        d = self.make_dir()
        bad = valid_grammar()
        bad["grammar"][0]["summary"] = "".join(chr(0x4E00 + i) for i in range(40))
        (d / "grammar.json").write_text(json.dumps(bad, ensure_ascii=False), encoding="utf-8")
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertLessEqual(len(messages), 25)
        self.assertTrue(any("more" in m for m in messages))

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

    def test_invalid_verb_jlpt_blocks_everything_and_writes_nothing(self):
        d = self.make_dir()
        doc = json.loads((d / "verbs.json").read_text(encoding="utf-8"))
        doc["verbs"][0]["jlpt"] = "expert"
        (d / "verbs.json").write_text(ud.dump_verbs(doc), encoding="utf-8")
        before = (d / "verbs.json").read_bytes()
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertEqual((d / "verbs.json").read_bytes(), before)
        self.assertTrue(any("jlpt" in m for m in messages))

    def test_valid_verb_jlpt_is_accepted(self):
        d = self.make_dir()
        doc = json.loads((d / "verbs.json").read_text(encoding="utf-8"))
        doc["verbs"][0]["jlpt"] = "N4"
        (d / "verbs.json").write_text(ud.dump_verbs(doc), encoding="utf-8")
        code, _ = ud.run(d)
        self.assertEqual(code, 0)

    def test_invalid_grammar_blocks_everything_and_writes_nothing(self):
        d = self.make_dir()
        bad = valid_grammar()
        bad["grammar"][0]["jlpt"] = "expert"
        (d / "grammar.json").write_text(json.dumps(bad), encoding="utf-8")
        before = (d / "verbs.json").read_bytes()
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertEqual((d / "verbs.json").read_bytes(), before)
        self.assertTrue(any("jlpt" in m for m in messages))


if __name__ == "__main__":
    unittest.main()
