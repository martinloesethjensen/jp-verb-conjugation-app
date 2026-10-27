import copy
import argparse
import json
import tempfile
import unittest
from pathlib import Path

import stable_ids
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


def with_ids(dataset, doc):
    """`doc` with a stable id on every item that needs one, the way assign_ids.py leaves real data."""
    taken = set()
    for _, item in stable_ids.id_slots(dataset, doc):
        item.setdefault("id", stable_ids.new_id(taken))
    return doc


def valid_grammar():
    return with_ids("grammar", {
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
    })


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


    def test_an_example_with_an_id_stays_on_one_line(self):
        doc = {"verbs": [{"examples": [{"id": "abcdef", "form": "te", "jp": "たべて。", "en": "Eat."}]}]}
        self.assertIn('{ "id": "abcdef", "form": "te", "jp": "たべて。", "en": "Eat." }', ud.dump_verbs(doc))


class BooksTests(unittest.TestCase):
    def doc(self, books=None, taught_in=None):
        doc = valid_grammar()
        doc["grammar"][0]["id"] = "p"
        if books is not None:
            doc["books"] = books
        if taught_in is not None:
            doc["grammar"][0]["taught_in"] = taught_in
        return doc

    def books(self):
        return [
            {"id": "genki-1", "title": "Genki I", "edition": "3rd", "lessons": 12},
            {"id": "genki-2", "title": "Genki II", "edition": "3rd", "first_lesson": 13, "lessons": 23},
        ]

    def ref(self, book="genki-1", lesson=12, reviewed=False):
        return {"book": book, "lesson": lesson, "reviewed": reviewed}

    def test_books_must_have_unique_ids(self):
        books = [self.books()[0], self.books()[0]]
        self.assertEqual(ud.validate_grammar(self.doc(books=books)), ["books: duplicate id genki-1"])

    def test_book_needs_title_and_lesson_range(self):
        books = self.books()
        del books[0]["title"]
        self.assertEqual(ud.validate_grammar(self.doc(books=books)), ["books: genki-1 title missing"])
        books = self.books()
        books[0]["first_lesson"] = 13
        self.assertEqual(ud.validate_grammar(self.doc(books=books)),
                         ["books: genki-1 lessons must be >= first_lesson"])

    def test_book_edition_is_optional_but_not_empty(self):
        books = self.books()
        del books[0]["edition"]
        self.assertEqual(ud.validate_grammar(self.doc(books=books)), [])
        books[0]["edition"] = ""
        self.assertEqual(ud.validate_grammar(self.doc(books=books)),
                         ["books: genki-1 edition must be a non-empty string when present"])

    def test_taught_in_book_must_exist(self):
        doc = self.doc(books=self.books(), taught_in=[self.ref("minna-1", 1)])
        self.assertEqual(ud.validate_grammar(doc), ["p: taught_in book 'minna-1' does not exist"])

    def test_taught_in_lesson_in_range(self):
        doc = self.doc(books=self.books(), taught_in=[self.ref("genki-2", 12)])
        self.assertEqual(ud.validate_grammar(doc), ["p: taught_in genki-2 lesson 12 is outside 13-23"])

    def test_taught_in_reviewed_is_bool(self):
        doc = self.doc(books=self.books(), taught_in=[self.ref(reviewed="no")])
        self.assertEqual(ud.validate_grammar(doc), ["p: taught_in reviewed must be true or false"])

    def test_taught_in_no_duplicates(self):
        doc = self.doc(books=self.books(), taught_in=[self.ref(), self.ref()])
        self.assertEqual(ud.validate_grammar(doc), ["p: taught_in lists genki-1 lesson 12 twice"])

    def test_books_and_taught_in_are_optional(self):
        self.assertEqual(ud.validate_grammar(valid_grammar()), [])
        doc = self.doc(books=self.books(), taught_in=[self.ref(), self.ref("genki-2", 20)])
        self.assertEqual(ud.validate_grammar(doc), [])


class ValidateGrammarTests(unittest.TestCase):
    def rule(self, **fields):
        doc = valid_grammar()
        doc["grammar"][0]["attachment"] = [dict({"word_class": "verb", "pattern": "p", "example": "x"}, **fields)]
        return ud.validate_grammar(doc)

    def test_valid_slot_rule(self):
        self.assertEqual(self.rule(slots=["plain", "plainPast"], then="ので"), [])
        self.assertEqual(self.rule(word_class="noun", slots=["plain"], da_to_na=True, then="ので"), [])
        self.assertEqual(self.rule(slots=["te"]), [])

    def test_slot_problems(self):
        self.assertTrue(self.rule(slots=["dictionary"]))
        self.assertTrue(self.rule(slots=[]))
        self.assertTrue(self.rule(word_class="noun", slots=["stem"], then="すぎる"))
        self.assertTrue(self.rule(slots=["plain"], da_to_na=True))
        self.assertTrue(self.rule(word_class="na-adjective", slots=["plainPast"], da_to_na=True))
        self.assertTrue(self.rule(then="ので"))
        self.assertTrue(self.rule(slots=["plain"], then=""))

    def test_contrasts(self):
        doc = valid_grammar()
        doc["grammar"][0]["contrasts"] = [{"pattern": "〜から", "explanation": "e",
                                           "examples": [{"jp": "あ", "en": "a"}]}]
        self.assertEqual(ud.validate_grammar(doc), [])
        doc["grammar"][0]["contrasts"] = [{"pattern": "", "explanation": "e", "id": "nope"}]
        problems = " ".join(ud.validate_grammar(doc))
        self.assertIn("contrast pattern", problems)
        self.assertIn("contrast id", problems)

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

    def test_pitfall_wrong_form_is_optional_but_not_blank(self):
        doc = valid_grammar()
        self.assertEqual(ud.validate_grammar(doc), [])
        doc["grammar"][0]["pitfalls"][0]["wrong"] = "静かだので"
        self.assertEqual(ud.validate_grammar(doc), [])
        for bad in ("", "  ", 3):
            doc["grammar"][0]["pitfalls"][0]["wrong"] = bad
            self.assertTrue(any("wrong" in e for e in ud.validate_grammar(doc)), bad)

    def test_usage_without_examples(self):
        doc = valid_grammar()
        doc["grammar"][0]["usages"][0]["examples"] = []
        self.assertTrue(any("example" in e for e in ud.validate_grammar(doc)))


class ManifestTests(unittest.TestCase):
    def test_ref_pins_every_entry(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": "x"}, b"v", b"g", furigana_bytes=b"f", ref="data-v1")
        self.assertEqual(result["ref"], "data-v1")
        self.assertEqual(result["grammar"]["ref"], "data-v1")
        self.assertEqual(result["furigana"]["ref"], "data-v1")

    def test_no_ref_means_no_ref_key(self):
        result = ud.build_manifest({"version": "1.0.0", "sha256": "x"}, b"v", b"g", furigana_bytes=b"f")
        self.assertNotIn("ref", result)
        self.assertNotIn("ref", result["grammar"])

    def test_an_old_ref_is_kept_only_while_the_file_is_unchanged(self):
        existing = {
            "version": "1.0.0", "sha256": ud.sha256_hex(b"v"), "ref": "data-v1",
            "grammar": {"version": "1.0.0", "sha256": "old", "ref": "data-v1"},
        }
        result = ud.build_manifest(existing, b"v", b"g")
        self.assertEqual(result["ref"], "data-v1")          # verbs unchanged: tag still has them
        self.assertNotIn("ref", result["grammar"])           # grammar changed: the tag is stale

    def test_valid_ref_rejects_anything_that_could_change_a_url(self):
        for bad in ["../x", "a/b", "a?b", "a#b", "-x", "", ".x", "a b", "a" * 65]:
            with self.assertRaises(argparse.ArgumentTypeError, msg=bad):
                ud.valid_ref(bad)
        self.assertEqual(ud.valid_ref("data-v1.2_3"), "data-v1.2_3")

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
        (d / "words.json").write_text(json.dumps({"version": "1.0.0", "description": "d", "words": []}) + "\n", encoding="utf-8")
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

    def with_example(self, form):
        d = self.make_dir()
        doc = json.loads((d / "verbs.json").read_text(encoding="utf-8"))
        doc["verbs"][0]["examples"] = [{"id": "abcdef", "form": form, "jp": "します。", "en": "I do."}]
        (d / "verbs.json").write_text(ud.dump_verbs(doc), encoding="utf-8")
        return d

    def test_a_verb_example_without_an_id_fails_the_run(self):
        d = self.with_example("tai")
        doc = json.loads((d / "verbs.json").read_text(encoding="utf-8"))
        del doc["verbs"][0]["examples"][0]["id"]
        (d / "verbs.json").write_text(ud.dump_verbs(doc), encoding="utf-8")
        code, messages = ud.run(d, check=True)
        self.assertEqual(code, 1)
        self.assertIn("verbs.json has items without a valid stable id:", messages[0])
        self.assertTrue(any("する example 1 has no id: run scripts/assign_ids.py" in m for m in messages), messages)

    def test_a_grammar_usage_without_an_id_fails_the_run(self):
        d = self.make_dir()
        doc = json.loads((d / "grammar.json").read_text(encoding="utf-8"))
        del doc["grammar"][0]["usages"][0]["id"]
        (d / "grammar.json").write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        code, messages = ud.run(d, check=True)
        self.assertEqual(code, 1)
        self.assertIn("grammar.json has items without a valid stable id:", messages[0])
        self.assertTrue(any("n-desu usage 1 has no id" in m for m in messages), messages)

    def test_an_example_may_use_a_generated_form(self):
        code, messages = ud.run(self.with_example("tai"))
        self.assertEqual(code, 0, messages)

    def test_an_example_with_a_form_the_verb_lacks_fails_and_writes_nothing(self):
        # Only godan verbs have the short causative-passive, so する has none.
        d = self.with_example("causative_passive_short")
        before = (d / "verbs.json").read_bytes()
        code, messages = ud.run(d, check=True)
        self.assertEqual(code, 1)
        self.assertIn("causative_passive_short", "\n".join(messages))
        code, _ = ud.run(d)
        self.assertEqual(code, 1)
        self.assertEqual((d / "verbs.json").read_bytes(), before)

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


class WordFormsTests(unittest.TestCase):
    def test_i_adjective(self):
        self.assertEqual(ud.word_forms({"class": "i-adjective", "dict": "たかい"}), {
            "short_pos": "たかい", "short_neg": "たかくない", "short_past": "たかかった",
            "short_past_neg": "たかくなかった", "stem": "たか", "te": "たかくて"})

    def test_ii_and_kakkoii_take_yo(self):
        f = ud.word_forms({"class": "i-adjective", "dict": "いい"})
        self.assertEqual((f["short_pos"], f["short_neg"], f["short_past"], f["stem"], f["te"]),
                         ("いい", "よくない", "よかった", "よ", "よくて"))
        self.assertEqual(ud.word_forms({"class": "i-adjective", "dict": "かっこいい"})["short_neg"], "かっこよくない")

    def test_kawaii_is_regular(self):
        self.assertEqual(ud.word_forms({"class": "i-adjective", "dict": "かわいい"})["short_neg"], "かわいくない")

    def test_na_adjective(self):
        self.assertEqual(ud.word_forms({"class": "na-adjective", "dict": "しずか"}), {
            "short_pos": "しずかだ", "short_neg": "しずかじゃない", "short_past": "しずかだった",
            "short_past_neg": "しずかじゃなかった", "stem": "しずか", "te": "しずかで"})

    def test_noun_has_no_stem(self):
        f = ud.word_forms({"class": "noun", "dict": "あめ"})
        self.assertNotIn("stem", f)
        self.assertEqual(f["short_pos"], "あめだ")
        self.assertEqual(f["te"], "あめで")

    def test_keys_follow_the_catalogue_order_then_stem(self):
        keys = list(ud.word_forms({"class": "i-adjective", "dict": "たかい"}))
        self.assertEqual(keys, ud.form_catalogue.ids("i-adjective") + ["stem"])

    def test_bad_input_raises(self):
        for word in ({"class": "i-adjective", "dict": "しずか"}, {"class": "verb", "dict": "たべる"},
                     {"class": "adverb", "dict": "とても"}, {"class": "noun", "dict": ""}):
            with self.assertRaises(ValueError):
                ud.word_forms(word)

    def test_apply_is_idempotent_and_overwrites_hand_edits(self):
        doc = {"words": [{"class": "noun", "dict": "あめ", "forms": {"short_pos": "x"}}]}
        self.assertTrue(ud.apply_word_forms(doc))
        self.assertEqual(doc["words"][0]["forms"]["short_pos"], "あめだ")
        self.assertFalse(ud.apply_word_forms(doc))


class CheckWordsTests(unittest.TestCase):
    readings = {"高": "たか", "雨": "あめ"}

    def test_valid(self):
        doc = {"words": [{"class": "i-adjective", "dict": "たかい", "kanji": "高い", "meaning": "expensive", "jlpt": "N5"}]}
        self.assertEqual(ud.check_words(doc, self.readings), [])

    def test_problems(self):
        doc = {"words": [
            {"class": "i-adjective", "dict": "たかい", "kanji": "雨い", "meaning": "x", "jlpt": "N5"},
            {"class": "noun", "dict": "あめ", "meaning": "", "jlpt": "N9"},
            {"class": "noun", "dict": "あめ", "meaning": "rain", "jlpt": "N5"},
        ]}
        problems = " ".join(ud.check_words(doc, self.readings))
        for fragment in ("kanji", "meaning", "jlpt", "duplicate"):
            self.assertIn(fragment, problems)


class WordsManifestTests(unittest.TestCase):
    def test_words_entry_starts_at_1_0_0_and_bumps_on_change(self):
        m = ud.build_manifest({}, b"v", b"g", furigana_bytes=b"f", words_bytes=b"w1")
        self.assertEqual(m["words"]["version"], "1.0.0")
        m2 = ud.build_manifest(m, b"v", b"g", furigana_bytes=b"f", words_bytes=b"w2")
        self.assertEqual(m2["words"]["version"], "1.1.0")
        m3 = ud.build_manifest(m2, b"v", b"g", furigana_bytes=b"f", words_bytes=b"w2")
        self.assertEqual(m3["words"]["version"], "1.1.0")

    def test_no_words_bytes_leaves_the_entry_out(self):
        self.assertNotIn("words", ud.build_manifest({}, b"v", b"g", furigana_bytes=b"f"))


class FormsManifestTests(unittest.TestCase):
    def test_forms_entry_starts_at_1_0_0_and_bumps_on_change(self):
        m = ud.build_manifest({}, b"v", b"g", forms_bytes=b"c1")
        self.assertEqual(m["forms"], {"version": "1.0.0", "sha256": ud.sha256_hex(b"c1")})
        m2 = ud.build_manifest(m, b"v", b"g", forms_bytes=b"c2")
        self.assertEqual(m2["forms"]["version"], "1.1.0")
        m3 = ud.build_manifest(m2, b"v", b"g", forms_bytes=b"c2")
        self.assertEqual(m3["forms"]["version"], "1.1.0")
        forced = ud.build_manifest(m3, b"v", b"g", forms_bytes=b"c2", forms_version="2.0.0")
        self.assertEqual(forced["forms"]["version"], "2.0.0")

    def test_a_ref_pins_the_forms_entry_until_it_changes(self):
        m = ud.build_manifest({}, b"v", b"g", forms_bytes=b"c1", ref="data-v1")
        self.assertEqual(m["forms"]["ref"], "data-v1")
        self.assertEqual(ud.build_manifest(m, b"v", b"g", forms_bytes=b"c1")["forms"]["ref"], "data-v1")
        self.assertNotIn("ref", ud.build_manifest(m, b"v", b"g", forms_bytes=b"c2")["forms"])


class PublishedFormsTests(unittest.TestCase):
    make_dir = RunTests.make_dir

    def test_run_publishes_forms_json_with_a_manifest_entry_and_the_bundled_copy(self):
        d = self.make_dir()
        bundled = d / "bundle" / "forms.json"
        code, messages = ud.run(d, check=True, bundled_forms_path=bundled)
        self.assertEqual(code, 1)
        self.assertTrue(any("data/forms.json" in m and "the bundled forms.json" in m for m in messages), messages)

        code, _ = ud.run(d, bundled_forms_path=bundled)
        self.assertEqual(code, 0)
        published = (d / "forms.json").read_bytes()
        self.assertEqual(published, ud.dump_forms().encode("utf-8"))
        self.assertEqual(bundled.read_bytes(), published)
        manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["forms"], {"version": "1.0.0", "sha256": ud.sha256_hex(published)})
        sidecar = json.loads(ud.bundled_forms_manifest_path(bundled).read_text(encoding="utf-8"))
        self.assertEqual(sidecar, manifest["forms"])
        self.assertEqual(ud.run(d, check=True, bundled_forms_path=bundled), (0, ["data is up to date"]))

    def test_check_fails_when_the_bundled_copy_drifts(self):
        d = self.make_dir()
        bundled = d / "bundle" / "forms.json"
        ud.run(d, bundled_forms_path=bundled)
        bundled.write_text("{}\n", encoding="utf-8")
        code, messages = ud.run(d, check=True, bundled_forms_path=bundled)
        self.assertEqual(code, 1)
        self.assertIn("the bundled forms.json", messages[0])
        self.assertNotIn("data/forms.json", messages[0])

    def test_check_fails_when_data_forms_json_is_edited_by_hand(self):
        d = self.make_dir()
        ud.run(d)
        (d / "forms.json").write_text("{}\n", encoding="utf-8")
        code, messages = ud.run(d, check=True)
        self.assertEqual(code, 1)
        self.assertIn("data/forms.json", messages[0])


class BundledDataTests(unittest.TestCase):
    make_dir = RunTests.make_dir

    NAMES = ("verbs", "grammar", "furigana", "words")

    def entry(self, manifest, name):
        source = manifest if name == "verbs" else manifest[name]
        return {"version": source["version"], "sha256": source["sha256"]}

    def test_run_writes_a_bundled_copy_and_sidecar_for_each_data_file(self):
        d = self.make_dir()
        bundle = d / "bundle"
        code, messages = ud.run(d, check=True, bundled_data_dir=bundle)
        self.assertEqual(code, 1)
        for name in self.NAMES:
            self.assertTrue(any(f"the bundled {name}.json" in m for m in messages), (name, messages))
        self.assertEqual(ud.run(d, bundled_data_dir=bundle)[0], 0)
        manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        for name in self.NAMES:
            self.assertEqual((bundle / f"{name}.json").read_bytes(), (d / f"{name}.json").read_bytes(), name)
            sidecar = json.loads((bundle / f"{name}.manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(sidecar, self.entry(manifest, name), name)
        self.assertEqual(ud.run(d, check=True, bundled_data_dir=bundle), (0, ["data is up to date"]))

    def test_check_names_only_the_copy_that_drifted(self):
        d = self.make_dir()
        bundle = d / "bundle"
        ud.run(d, bundled_data_dir=bundle)
        (bundle / "grammar.json").write_text("{}\n", encoding="utf-8")
        code, messages = ud.run(d, check=True, bundled_data_dir=bundle)
        self.assertEqual(code, 1)
        self.assertIn("the bundled grammar.json", messages[0])
        for name in ("verbs", "furigana", "words"):
            self.assertNotIn(f"the bundled {name}.json", messages[0])

    def test_a_stale_sidecar_fails_check_and_run_fixes_it(self):
        d = self.make_dir()
        bundle = d / "bundle"
        ud.run(d, bundled_data_dir=bundle)
        (bundle / "verbs.manifest.json").write_text('{"version": "0.0.1", "sha256": "x"}\n', encoding="utf-8")
        self.assertEqual(ud.run(d, check=True, bundled_data_dir=bundle)[0], 1)
        self.assertEqual(ud.run(d, bundled_data_dir=bundle)[0], 0)
        self.assertEqual(ud.run(d, check=True, bundled_data_dir=bundle)[0], 0)

    def test_without_a_directory_nothing_is_written_or_checked(self):
        d = self.make_dir()
        ud.run(d)
        self.assertEqual(ud.run(d, check=True), (0, ["data is up to date"]))
        self.assertFalse((d / "bundle").exists())


class OtherFormsTests(unittest.TestCase):
    def forms(self, dict_form, vtype, short_past):
        return ud.other_forms({"type": vtype, "dict": dict_form, "forms": {"short_past": short_past}})

    def test_ru_verb(self):
        self.assertEqual(self.forms("たべる", "ru", "たべた"), {
            "volitional": "たべよう", "passive": "たべられる", "causative": "たべさせる",
            "causative_passive": "たべさせられる", "conditional_ba": "たべれば",
            "conditional_tara": "たべたら", "imperative": "たべろ", "tai": "たべたい",
        })

    def test_u_verbs(self):
        got = self.forms("のむ", "u", "のんだ")
        self.assertEqual(
            [got[f] for f in ud.BASE_OTHER_FIELDS],
            ["のもう", "のまれる", "のませる", "のませられる", "のめば", "のんだら", "のめ", "のみたい"],
        )
        got = self.forms("かう", "u", "かった")
        self.assertEqual(got["passive"], "かわれる")
        self.assertEqual(got["volitional"], "かおう")
        self.assertEqual(got["conditional_ba"], "かえば")
        got = self.forms("いく", "u", "いった")
        self.assertEqual((got["conditional_tara"], got["imperative"]), ("いったら", "いけ"))

    def test_irregular_verbs(self):
        self.assertEqual(self.forms("する", "irr.", "した")["causative_passive"], "させられる")
        self.assertEqual(self.forms("くる", "irr.", "きた")["imperative"], "こい")
        self.assertEqual(self.forms("くる", "irr.", "きた")["conditional_tara"], "きたら")

    def test_aru_only_has_some(self):
        self.assertEqual(self.forms("ある", "u", "あった"), {
            "volitional": "あろう", "conditional_ba": "あれば", "conditional_tara": "あったら", "tai": "ありたい",
        })

    def test_non_volitional_verbs_only_have_some(self):
        self.assertEqual(self.forms("わかる", "u", "わかった"), {
            "causative": "わからせる", "causative_passive": "わからせられる", "conditional_ba": "わかれば",
            "conditional_tara": "わかったら", "tai": "わかりたい",
        })
        self.assertEqual(self.forms("つかれる", "ru", "つかれた"), {
            "causative": "つかれさせる", "conditional_ba": "つかれれば", "conditional_tara": "つかれたら",
        })
        self.assertEqual(set(self.forms("しる", "u", "しった")),
                         {"passive", "causative", "conditional_ba", "conditional_tara", "tai"})
        self.assertNotIn("passive", self.forms("おわる", "u", "おわった"))
        for dict_form, kind in [("わかる", "u"), ("しる", "u"), ("つかれる", "ru")]:
            self.assertIsNone(ud.potential_base(potential_verb(dict_form, kind)))

    def test_kureru_has_an_irregular_imperative_and_little_else(self):
        self.assertEqual(self.forms("くれる", "ru", "くれた"), {
            "conditional_ba": "くれれば", "conditional_tara": "くれたら", "imperative": "くれ",
        })
        self.assertIsNone(ud.potential_base(potential_verb("くれる", "ru")))
        self.assertEqual(ud.IRREGULAR_IMPERATIVE, {"くれる": "くれ"})

    def test_the_core_batch_exclusions(self):
        self.assertEqual(self.forms("できる", "ru", "できた"),
                         {"conditional_ba": "できれば", "conditional_tara": "できたら"})
        self.assertNotIn("passive", self.forms("なる", "u", "なった"))
        self.assertEqual(self.forms("なる", "u", "なった")["imperative"], "なれ")
        self.assertEqual(set(self.forms("ふる", "u", "ふった")),
                         {"passive", "causative", "conditional_ba", "conditional_tara"})
        for dict_form, kind in [("できる", "ru"), ("みえる", "ru"), ("きこえる", "ru"), ("あく", "u"), ("ふる", "u")]:
            self.assertIsNone(ud.potential_base(potential_verb(dict_form, kind)))

    def test_partial_forms_name_real_verbs_and_forms(self):
        data = json.loads((Path(__file__).resolve().parent.parent / "data" / "verbs.json")
                          .read_text(encoding="utf-8"))
        self.assertTrue(set(ud.PARTIAL_OTHER_FORMS) <= {v["dict"] for v in data["verbs"]})
        self.assertTrue(set(ud.NO_POTENTIAL) <= {v["dict"] for v in data["verbs"]})
        for names in ud.PARTIAL_OTHER_FORMS.values():
            self.assertTrue(names <= set(ud.BASE_OTHER_FIELDS), names)

    def test_unknown_class_or_missing_past_fails(self):
        with self.assertRaises(ValueError):
            self.forms("たべる", "weird", "たべた")
        with self.assertRaises(ValueError):
            ud.other_forms({"type": "ru", "dict": "たべる", "forms": {}})
        with self.assertRaises(ValueError):
            self.forms("べんきょうする", "irr.", "した")

    def test_apply_is_idempotent_and_removes_stale_fields(self):
        doc = {"verbs": [{"type": "u", "dict": "ある", "forms": dict(
            short_past="あった", passive="x", masu_pos="あります", te="あって",
            short_pos="ある", short_neg="ない")}]}
        self.assertTrue(ud.apply_other_forms(doc))
        self.assertNotIn("passive", doc["verbs"][0]["forms"])
        self.assertFalse(ud.apply_other_forms(doc))


def everyday_verb(dict_form, vtype, **forms):
    return {"type": vtype, "dict": dict_form, "forms": forms}


NOMU = dict(masu_pos="のみます", te="のんで", short_pos="のむ", short_neg="のまない")
TABERU = dict(masu_pos="たべます", te="たべて", short_pos="たべる", short_neg="たべない")


class ExtraFormsTests(unittest.TestCase):
    ALL_BASE = {"volitional", "imperative", "causative"}

    def test_everyday_forms_of_a_godan_verb(self):
        got = ud.extra_forms(everyday_verb("のむ", "u", **NOMU), self.ALL_BASE)
        self.assertEqual(got, {
            "causative_passive_short": "のまされる", "masu_volitional": "のみましょう",
            "neg_te": "のまないで", "nakute": "のまなくて", "te_mo_ii": "のんでもいい",
            "te_wa_ikenai": "のんではいけない", "te_cha_dame": "のんじゃだめ",
            "nakereba_naranai": "のまなければならない", "nakute_wa_ikenai": "のまなくてはいけない",
            "nakya": "のまなきゃ", "nakucha": "のまなくちゃ", "nakute_mo_ii": "のまなくてもいい",
            "neg_imperative": "のむな", "nasai": "のみなさい", "conditional_to": "のむと",
            "conditional_nara": "のむなら",
        })

    def test_ru_verbs_and_irregulars_have_no_short_causative_passive(self):
        got = ud.extra_forms(everyday_verb("たべる", "ru", **TABERU), self.ALL_BASE)
        self.assertNotIn("causative_passive_short", got)
        self.assertEqual((got["te_cha_dame"], got["nasai"]), ("たべちゃだめ", "たべなさい"))
        got = ud.extra_forms(everyday_verb("する", "irr.", masu_pos="します", te="して",
                                           short_pos="する", short_neg="しない"), self.ALL_BASE)
        self.assertNotIn("causative_passive_short", got)
        self.assertEqual((got["neg_te"], got["nasai"], got["masu_volitional"]),
                         ("しないで", "しなさい", "しましょう"))
        got = ud.extra_forms(everyday_verb("くる", "irr.", masu_pos="きます", te="きて",
                                           short_pos="くる", short_neg="こない"), self.ALL_BASE)
        self.assertEqual((got["nakute"], got["nasai"]), ("こなくて", "きなさい"))

    def test_su_verbs_have_only_the_long_causative_passive(self):
        got = ud.extra_forms(everyday_verb("はなす", "u", masu_pos="はなします", te="はなして",
                                           short_pos="はなす", short_neg="はなさない"), self.ALL_BASE)
        self.assertNotIn("causative_passive_short", got)

    def test_voiced_te_forms_become_ja(self):
        got = ud.extra_forms(everyday_verb("およぐ", "u", masu_pos="およぎます", te="およいで",
                                           short_pos="およぐ", short_neg="およがない"), self.ALL_BASE)
        self.assertEqual(got["te_cha_dame"], "およいじゃだめ")
        self.assertEqual(got["causative_passive_short"], "およがされる")

    def test_aru_builds_its_negative_forms_from_nai(self):
        got = ud.extra_forms(everyday_verb("ある", "u", masu_pos="あります", te="あって",
                                           short_pos="ある", short_neg="ない"), {"volitional"})
        self.assertEqual((got["neg_te"], got["nakute"], got["nakya"]), ("ないで", "なくて", "なきゃ"))
        self.assertEqual(got["masu_volitional"], "ありましょう")
        self.assertNotIn("nasai", got)
        self.assertNotIn("neg_imperative", got)

    def test_forms_that_need_another_form_follow_it(self):
        verb = everyday_verb("のむ", "u", **NOMU)
        got = ud.extra_forms(verb, {"causative"})
        for name in ("masu_volitional", "nasai", "neg_imperative"):
            self.assertNotIn(name, got)
        self.assertIn("causative_passive_short", got)
        self.assertNotIn("causative_passive_short", ud.extra_forms(verb, {"volitional", "imperative"}))

    def test_missing_or_odd_source_forms_fail_loudly(self):
        with self.assertRaises(ValueError):
            ud.extra_forms(everyday_verb("のむ", "u", masu_pos="のみます"), set())
        with self.assertRaises(ValueError):
            ud.extra_forms(everyday_verb("のむ", "u", **dict(NOMU, short_neg="のまぬ")), set())
        with self.assertRaises(ValueError):
            ud.extra_forms(everyday_verb("のむ", "u", **dict(NOMU, te="のむ")), set())

    def test_exclusions_name_real_extra_forms_and_real_verbs(self):
        extras = {name for name in ud.OTHER_FORM_FIELDS if name not in ud.BASE_OTHER_FIELDS}
        for dict_form, names in ud.EXTRA_EXCLUDED.items():
            self.assertTrue(names <= extras, dict_form)
        data = json.loads((Path(__file__).resolve().parent.parent / "data" / "verbs.json")
                          .read_text(encoding="utf-8"))
        self.assertTrue(set(ud.EXTRA_EXCLUDED) <= {v["dict"] for v in data["verbs"]})

    def test_shinu_keeps_the_natural_forms_only(self):
        verb = everyday_verb("しぬ", "u", masu_pos="しにます", te="しんで",
                             short_pos="しぬ", short_neg="しなない")
        got = ud.extra_forms(verb, self.ALL_BASE)
        self.assertNotIn("nasai", got)
        self.assertNotIn("causative_passive_short", got)
        self.assertEqual((got["neg_imperative"], got["te_cha_dame"]), ("しぬな", "しんじゃだめ"))

    def test_owaru_keeps_mashou_but_not_nasai_or_na(self):
        verb = everyday_verb("おわる", "u", masu_pos="おわります", te="おわって",
                             short_pos="おわる", short_neg="おわらない")
        got = ud.extra_forms(verb, self.ALL_BASE)
        self.assertNotIn("nasai", got)
        self.assertNotIn("neg_imperative", got)
        self.assertEqual(got["masu_volitional"], "おわりましょう")

    def test_apply_puts_a_new_form_in_catalogue_order(self):
        verb = {"type": "u", "dict": "のむ", "forms": dict(NOMU, short_past="のんだ")}
        doc = {"verbs": [verb]}
        self.assertTrue(ud.apply_other_forms(doc))
        keys = [k for k in verb["forms"] if k in ud.OTHER_FORM_FIELDS]
        self.assertEqual(keys, sorted(keys, key=ud.OTHER_FORM_FIELDS.index))
        self.assertIn("causative_passive_short", keys)
        self.assertFalse(ud.apply_other_forms(doc))


def table(counter):
    readings = ud.counter_readings(counter)
    return [" / ".join(readings[key]) for key in ud.COUNTER_KEYS]


class CounterReadingTests(unittest.TestCase):
    def test_h_b(self):
        self.assertEqual(table({"reading": "ほん", "sound": "h-b"}), [
            "いっぽん", "にほん", "さんぼん", "よんほん", "ごほん", "ろっぽん", "ななほん",
            "はっぽん / はちほん", "きゅうほん", "じゅっぽん / じっぽん", "なんぼん"])

    def test_h_p(self):
        self.assertEqual(table({"reading": "ふん", "sound": "h-p"}), [
            "いっぷん", "にふん", "さんぷん", "よんぷん", "ごふん", "ろっぷん", "ななふん",
            "はっぷん / はちふん", "きゅうふん", "じゅっぷん / じっぷん", "なんぷん"])

    def test_k(self):
        self.assertEqual(table({"reading": "こ", "sound": "k"}), [
            "いっこ", "にこ", "さんこ", "よんこ", "ごこ", "ろっこ", "ななこ",
            "はっこ / はちこ", "きゅうこ", "じゅっこ / じっこ", "なんこ"])

    def test_s_keeps_rokuj_and_has_no_hachi(self):
        self.assertEqual(table({"reading": "さつ", "sound": "s"}), [
            "いっさつ", "にさつ", "さんさつ", "よんさつ", "ごさつ", "ろくさつ", "ななさつ",
            "はっさつ", "きゅうさつ", "じゅっさつ / じっさつ", "なんさつ"])

    def test_plain(self):
        self.assertEqual(table({"reading": "まい", "sound": "plain"}), [
            "いちまい", "にまい", "さんまい", "よんまい", "ごまい", "ろくまい", "ななまい",
            "はちまい", "きゅうまい", "じゅうまい", "なんまい"])

    def test_overrides_replace_generated_keys(self):
        readings = ud.counter_readings({"reading": "かい", "sound": "k",
                                        "overrides": {"3": ["さんがい", "さんかい"]}})
        self.assertEqual(readings["3"], ["さんがい", "さんかい"])
        self.assertEqual(readings["1"], ["いっかい"])

    def test_irregular_takes_overrides_only(self):
        overrides = {key: [f"x{key}"] for key in ud.COUNTER_KEYS}
        self.assertEqual(ud.counter_readings({"reading": "つ", "sound": "irregular", "overrides": overrides}),
                         overrides)

    def test_changed_compares_the_preferred_reading_with_the_plain_one(self):
        hon = {"reading": "ほん", "sound": "h-b"}
        self.assertEqual(ud.changed_keys(hon, ud.counter_readings(hon)), ["1", "3", "6", "8", "10", "what"])
        en = {"reading": "えん", "sound": "plain", "overrides": {"4": ["よえん"]}}
        self.assertEqual(ud.changed_keys(en, ud.counter_readings(en)), ["4"])
        mai = {"reading": "まい", "sound": "plain"}
        self.assertEqual(ud.changed_keys(mai, ud.counter_readings(mai)), [])
        tsu = {"reading": "つ", "sound": "irregular",
               "overrides": {key: [f"x{key}"] for key in ud.COUNTER_KEYS}}
        self.assertEqual(ud.changed_keys(tsu, ud.counter_readings(tsu)), [])


def counter(**fields):
    base = {"id": "hon", "counter": "本", "reading": "ほん", "meaning": "long, thin things",
            "jlpt": "N5", "sound": "h-b", "symbol": "pencil", "overrides": {},
            "things": [{"word": "傘", "kana": "かさ", "meaning": "umbrella", "fit": "primary"}],
            "examples": [], "pitfalls": [], "related": []}
    base.update(fields)
    return base


COUNTER_READINGS = {"本": "ほん", "傘": "かさ", "二本": "にほん", "三本": "さんぼん", "一日": "いちにち"}
COUNTER_GROUP = {"id": "long", "title": "Long things", "symbol": "pencil", "summary": "s",
                 "members": [{"counter": "hon", "note": "pencils"}]}


COUNTER_SECTION = {"id": "things", "title": "Things", "counters": ["hon"]}


def counters_doc(*counters, groups=None, sections=None):
    doc = {"counters": list(counters), "groups": [COUNTER_GROUP] if groups is None else groups}
    if sections is not None:
        doc["sections"] = sections
    return doc


class CheckCountersTests(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(ud.check_counters(counters_doc(counter()), COUNTER_READINGS), [])

    def test_group_problems(self):
        cases = {
            "member": [dict(COUNTER_GROUP, members=[{"counter": "nope"}])],
            "duplicate group": [COUNTER_GROUP, COUNTER_GROUP],
            "in no group": [],
        }
        for needle, groups in cases.items():
            problems = ud.check_counters(counters_doc(counter(), groups=groups), COUNTER_READINGS)
            self.assertTrue(any(needle in p for p in problems), (needle, problems))

    def test_section_problems(self):
        cases = {
            "duplicate section": [COUNTER_SECTION, COUNTER_SECTION],
            "not a counter": [dict(COUNTER_SECTION, counters=["nope"])],
            "listed twice": [dict(COUNTER_SECTION, counters=["hon", "hon"])],
            "in no section": [],
            "title": [dict(COUNTER_SECTION, title="")],
            "must be a list of counter ids": [{"id": "x", "title": "X"}],
            "must be a list of counter ids ": [dict(COUNTER_SECTION, counters="hon")],
            "must be a list of counter ids  ": [dict(COUNTER_SECTION, counters=[1])],
            "has no counters": [dict(COUNTER_SECTION, counters=[]), dict(COUNTER_SECTION, id="y", counters=["hon"])],
            "must be an object": ["hon"],
        }
        for needle, sections in cases.items():
            needle = needle.strip()
            problems = ud.check_counters(counters_doc(counter(), sections=sections), COUNTER_READINGS)
            self.assertTrue(any(needle in p for p in problems), (needle, problems))

    NIN_CORE = {"1": ["ひとり"], "2": ["ふたり"], "3": ["さんにん"], "4": ["よにん"], "5": ["ごにん"],
                "6": ["ろくにん"], "7": ["ななにん", "しちにん"], "8": ["はちにん"], "9": ["きゅうにん"],
                "10": ["じゅうにん"], "what": ["なんにん"]}

    def nin(self, **fields):
        return counter(id="nin", counter="人", reading="にん", sound="irregular", overrides=dict(self.NIN_CORE), **fields)

    def nin_doc(self, **fields):
        return counters_doc(self.nin(**fields), groups=[dict(COUNTER_GROUP, members=[{"counter": "nin"}])])

    def test_big_number_problems(self):
        cases = {
            "extent must be": [counter(extent=9), counter(extent=100), counter(extent="99"), counter(extent=True)],
            "extra must be": [counter(extent=99, extra="100"), counter(extent=99, extra=[50]),
                              counter(extent=99, extra=[200, 100]), counter(extent=99, extra=[100, 100])],
            "must override": [counter(extent=99, extra=[100, 200])],
            "compound must be": [counter(compound=["にん"]), counter(compound={"11": ["x"]}),
                                 counter(compound={"0": []}), counter(compound={"0": ["ニン"]})],
        }
        for needle, variants in cases.items():
            for variant in variants:
                problems = ud.check_counters(counters_doc(variant), COUNTER_READINGS)
                self.assertTrue(any(needle in p for p in problems), (needle, variant, problems))

    def test_an_irregular_counter_with_extent_needs_compound_or_overrides(self):
        problems = ud.check_counters(self.nin_doc(extent=24), COUNTER_READINGS)
        self.assertTrue(any("irregular" in p and "extent" in p for p in problems), problems)
        partial = self.nin_doc(extent=24, compound={"1": ["いちにん"]})   # no "0": round tens cannot compose
        self.assertTrue(any("irregular" in p and "extent" in p for p in ud.check_counters(partial, COUNTER_READINGS)))

    def test_an_override_key_must_be_one_the_counter_has(self):
        problems = ud.check_counters(counters_doc(counter(overrides={"14": ["じゅうよんほん"]})), COUNTER_READINGS)
        self.assertTrue(any("overrides key" in p for p in problems), problems)
        ok = counters_doc(counter(extent=99, overrides={"14": ["じゅうよんほん"]}))
        self.assertEqual(ud.check_counters(ok, COUNTER_READINGS), [])

    def test_a_valid_big_counter_passes(self):
        self.assertEqual(ud.check_counters(counters_doc(counter(extent=99, extra=[100])), COUNTER_READINGS), [])
        compound = {"1": ["いちにん"], "2": ["ににん"], "0": ["にん"]}
        self.assertEqual(ud.check_counters(self.nin_doc(extent=99, extra=[100], compound=compound), COUNTER_READINGS), [])

    def test_a_tsu_style_counter_with_extent_10_passes(self):
        self.assertEqual(ud.check_counters(self.nin_doc(extent=10), COUNTER_READINGS), [])
        self.assertEqual(ud.check_counters(self.nin_doc(), COUNTER_READINGS), [])

    def test_question_problems(self):
        good = {"jp": "何本ありますか。", "en": "How many?"}
        cases = {
            "questions must be a list": "何本",
            "question must be an object": ["何本"],
            "question jp": [dict(good, jp="")],
            "question en": [dict(good, en="")],
            "must contain 何本": [dict(good, jp="本があります。")],
        }
        for needle, questions in cases.items():
            problems = ud.check_counters(counters_doc(counter(questions=questions)), COUNTER_READINGS)
            self.assertTrue(any(needle in p for p in problems), (needle, problems))

    def test_a_duration_question_cannot_be_filed_under_the_point_in_time_counter(self):
        ji = counter(id="ji", counter="時", reading="じ", sound="plain",
                     questions=[{"jp": "毎日何時間寝ますか。", "en": "How many hours?"}])
        problems = ud.check_counters(counters_doc(ji), COUNTER_READINGS)
        self.assertTrue(any("must contain 何時" in p for p in problems), problems)
        jikan = counter(id="jikan", counter="時間", reading="じかん", sound="plain",
                        questions=[{"jp": "毎日何時間寝ますか。", "en": "How many hours?"}])
        doc = counters_doc(jikan, groups=[dict(COUNTER_GROUP, members=[{"counter": "jikan"}])])
        self.assertEqual(ud.check_counters(doc, COUNTER_READINGS), [])

    def test_a_valid_question_passes(self):
        doc = counters_doc(counter(questions=[{"jp": "何本ありますか。", "en": "How many?"}]))
        self.assertEqual(ud.check_counters(doc, COUNTER_READINGS), [])

    def test_sections_are_optional(self):
        self.assertEqual(ud.check_counters(counters_doc(counter()), COUNTER_READINGS), [])

    def test_a_counter_may_be_in_two_sections(self):
        sections = [COUNTER_SECTION, dict(COUNTER_SECTION, id="drinks", title="Drinks")]
        self.assertEqual(ud.check_counters(counters_doc(counter(), sections=sections), COUNTER_READINGS), [])

    def test_problems(self):
        cases = {
            "sound": counter(sound="x"),
            "jlpt": counter(jlpt="N9"),
            "fit": counter(things=[{"word": "傘", "kana": "かさ", "meaning": "umbrella", "fit": "maybe"}]),
            "overrides key": counter(overrides={"11": ["じゅういっぽん"]}),
            "hiragana": counter(overrides={"3": ["サンボン"]}),
            "irregular": counter(sound="irregular", overrides={"1": ["ひとつ"]}),
            "related": counter(related=["nope"]),
            "reading": counter(reading="ホン"),
        }
        for needle, bad in cases.items():
            problems = ud.check_counters(counters_doc(bad), COUNTER_READINGS)
            self.assertTrue(any(needle in p for p in problems), (needle, problems))

    def test_duplicate_ids(self):
        problems = ud.check_counters(counters_doc(counter(), counter()), COUNTER_READINGS)
        self.assertTrue(any("duplicate" in p for p in problems))

    def test_an_h_class_counter_must_start_on_the_ha_row(self):
        problems = ud.check_counters(counters_doc(counter(reading="まい")), COUNTER_READINGS)
        self.assertTrue(any("は-row" in p for p in problems))

    def test_a_things_kanji_must_read_as_its_kana(self):
        bad = counter(things=[{"word": "傘", "kana": "あめ", "meaning": "umbrella", "fit": "primary"}])
        problems = ud.check_counters(counters_doc(bad), COUNTER_READINGS)
        self.assertTrue(any("傘" in p for p in problems), problems)

    def test_example_readings_must_be_hiragana_and_cover_a_run_in_the_sentence(self):
        bad = counter(examples=[{"jp": "傘を三本ください。", "en": "…", "readings": {"二本": "にほん"}}])
        self.assertTrue(ud.check_counters(counters_doc(bad), COUNTER_READINGS))
        katakana = counter(examples=[{"jp": "傘を三本ください。", "en": "…", "readings": {"三本": "サンボン"}}])
        self.assertTrue(ud.check_counters(counters_doc(katakana), COUNTER_READINGS))

    def test_examples_and_pitfalls_need_their_text(self):
        bad = counter(examples=[{"jp": "", "en": "x"}], pitfalls=[{"heading": "h"}])
        problems = ud.check_counters(counters_doc(bad), COUNTER_READINGS)
        self.assertTrue(any("example" in p for p in problems), problems)
        self.assertTrue(any("pitfall" in p for p in problems), problems)

    def test_counter_pitfall_wrong_form_is_optional_but_not_blank(self):
        pitfall = {"heading": "h", "explanation": "e"}
        self.assertEqual(ud.check_counters(counters_doc(counter(pitfalls=[pitfall])), COUNTER_READINGS), [])
        ok = dict(pitfall, wrong="さんほん")
        self.assertEqual(ud.check_counters(counters_doc(counter(pitfalls=[ok])), COUNTER_READINGS), [])
        bad = dict(pitfall, wrong="")
        problems = ud.check_counters(counters_doc(counter(pitfalls=[bad])), COUNTER_READINGS)
        self.assertTrue(any("wrong" in p for p in problems), problems)


class CountedRunTests(unittest.TestCase):
    def test_counted_runs_must_read_as_the_counter_says(self):
        doc = counters_doc(counter(examples=[{"jp": "傘を三本ください。", "en": "…"}]))
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counted_runs(doc, COUNTER_READINGS), [])
        wrong = dict(COUNTER_READINGS, **{"三本": "さんほん"})
        self.assertTrue(ud.check_counted_runs(doc, wrong))
        missing = {k: v for k, v in COUNTER_READINGS.items() if k != "三本"}
        self.assertTrue(any("三本" in p for p in ud.check_counted_runs(doc, missing)))

    def test_pitfall_examples_are_checked_too(self):
        doc = counters_doc(counter(pitfalls=[{"heading": "h", "explanation": "e",
                                              "examples": [{"jp": "三本です。", "en": "…"}]}]))
        ud.apply_counter_readings(doc)
        wrong = dict(COUNTER_READINGS, **{"三本": "さんほん"})
        self.assertTrue(ud.check_counted_runs(doc, wrong))

    def test_a_longer_number_is_not_mistaken_for_its_last_digit(self):
        doc = counters_doc(counter(examples=[{"jp": "二十本あります。", "en": "…"}]))
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counted_runs(doc, COUNTER_READINGS), [])

    def test_a_counted_run_inside_a_longer_counter_is_not_checked(self):
        ji = counter(id="ji", counter="時", reading="じ", sound="plain",
                     examples=[{"jp": "三時間勉強しました。", "en": "…"}])
        doc = counters_doc(ji, groups=[dict(COUNTER_GROUP, members=[{"counter": "ji"}])])
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counted_runs(doc, COUNTER_READINGS), [])
        doc["counters"][0]["examples"] = [{"jp": "三時に起きます。", "en": "…"}]
        self.assertTrue(any("三時" in p for p in ud.check_counted_runs(doc, COUNTER_READINGS)))

    def test_a_counter_ending_in_kan_checks_its_own_runs(self):
        jikan = counter(id="jikan", counter="時間", reading="じかん", sound="plain",
                        examples=[{"jp": "三時間勉強しました。", "en": "…"}])
        doc = counters_doc(jikan, groups=[dict(COUNTER_GROUP, members=[{"counter": "jikan"}])])
        ud.apply_counter_readings(doc)
        self.assertTrue(ud.check_counted_runs(doc, dict(COUNTER_READINGS, **{"三時間": "さんじ"})))
        self.assertEqual(ud.check_counted_runs(doc, dict(COUNTER_READINGS, **{"三時間": "さんじかん"})), [])

    def test_parse_numeral(self):
        cases = {"十": 10, "十五": 15, "二十": 20, "九十九": 99, "百": 100, "三百": 300, "千": 1000,
                 "三千": 3000, "一万": 10000, "五": 5}
        for text, value in cases.items():
            self.assertEqual(ud.parse_numeral(text), value, text)
        for text in ("a", "", "二十二百", "一十", "一百", "一千", "百五十0"):
            self.assertIsNone(ud.parse_numeral(text), text)

    def test_a_compound_counted_run_is_checked(self):
        fun = counter(id="fun", counter="分", reading="ふん", sound="h-p", extent=59,
                      examples=[{"jp": "十五分です。", "en": "…"}])
        doc = counters_doc(fun, groups=[dict(COUNTER_GROUP, members=[{"counter": "fun"}])])
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counted_runs(doc, dict(COUNTER_READINGS, **{"十五分": "じゅうごふん"})), [])
        wrong = ud.check_counted_runs(doc, dict(COUNTER_READINGS, **{"十五分": "じゅうごぷん"}))
        self.assertTrue(any("十五分" in p for p in wrong), wrong)

    def test_nijuppon_is_no_longer_skipped(self):
        doc = counters_doc(counter(extent=20, examples=[{"jp": "二十本あります。", "en": "…"}]))
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counted_runs(doc, dict(COUNTER_READINGS, **{"二十本": "にじゅっぽん"})), [])
        self.assertEqual(ud.check_counted_runs(doc, dict(COUNTER_READINGS, **{"二十本": "にじっぽん"})), [])
        wrong = ud.check_counted_runs(doc, dict(COUNTER_READINGS, **{"二十本": "にじゅうほん"}))
        self.assertTrue(any("二十本" in p for p in wrong), wrong)

    def test_a_number_outside_the_counters_keys_is_not_checked(self):
        doc = counters_doc(counter(extent=99, extra=[100], examples=[{"jp": "百五十本あります。", "en": "…"}]))
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counted_runs(doc, COUNTER_READINGS), [])

    def test_pitfall_headings_and_explanations_are_checked_too(self):
        doc = counters_doc(counter(pitfalls=[
            {"heading": "三本 first", "explanation": "三本 is さんぼん.", "examples": []}]))
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counted_runs(doc, COUNTER_READINGS), [])
        wrong = dict(COUNTER_READINGS, **{"三本": "さんほん"})
        problems = ud.check_counted_runs(doc, wrong)
        self.assertTrue(any("heading" in p for p in problems), problems)
        self.assertTrue(any("explanation" in p for p in problems), problems)

    def test_question_runs_are_checked_like_examples(self):
        doc = counters_doc(counter(questions=[{"jp": "何本ありますか。", "en": "How many?"}]))
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counted_runs(doc, dict(COUNTER_READINGS, **{"何本": "なんぼん"})), [])
        self.assertTrue(ud.check_counted_runs(doc, dict(COUNTER_READINGS, **{"何本": "なんほん"})))

    def test_an_example_reading_wins_over_the_dictionary(self):
        tsu = {key: ["x"] for key in ud.COUNTER_KEYS}
        tsu["1"] = ["ついたち"]
        date = counter(id="nichi-date", counter="日", reading="にち", sound="irregular", overrides=tsu,
                       examples=[{"jp": "一日に会いましょう。", "en": "…", "readings": {"一日": "ついたち"}}])
        doc = counters_doc(date, groups=[dict(COUNTER_GROUP, members=[{"counter": "nichi-date"}])])
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counted_runs(doc, COUNTER_READINGS), [])   # the dictionary says いちにち


class CountersFileTests(unittest.TestCase):
    def test_apply_fills_readings_and_changed_and_reports_staleness(self):
        doc = {"counters": [counter()]}
        self.assertTrue(ud.apply_counter_readings(doc))
        self.assertEqual(doc["counters"][0]["changed"], ["1", "3", "6", "8", "10", "what"])
        self.assertEqual(list(doc["counters"][0]["readings"]), ud.COUNTER_KEYS)
        self.assertFalse(ud.apply_counter_readings(doc))

    def test_dump_puts_each_counter_on_one_line_and_round_trips(self):
        doc = {"version": "1.0.0", "description": "d", "counters": [counter()]}
        text = ud.dump_counters(doc)
        self.assertEqual(json.loads(text), doc)
        self.assertEqual(text.count("\n    {"), 1)

    def test_dump_puts_each_group_on_one_line(self):
        doc = {"version": "1.0.0", "description": "d", "counters": [counter()], "groups": [COUNTER_GROUP]}
        text = ud.dump_counters(doc)
        self.assertEqual(json.loads(text), doc)
        self.assertEqual(text.count("\n    {"), 2)

    def test_dump_puts_each_section_on_one_line(self):
        doc = {"version": "1.0.0", "description": "d", "counters": [counter()], "groups": [COUNTER_GROUP],
               "sections": [COUNTER_SECTION]}
        text = ud.dump_counters(doc)
        self.assertEqual(json.loads(text), doc)
        self.assertEqual(text.count("\n    {"), 3)
        self.assertIn('    {"id": "things", "title": "Things", "counters": ["hon"]}', text)

    def test_manifest_entry_starts_at_1_0_0_and_bumps_on_change(self):
        m = ud.build_manifest({}, b"v", b"g", furigana_bytes=b"f", counters_bytes=b"c1")
        self.assertEqual(m["counters"]["version"], "1.0.0")
        m2 = ud.build_manifest(m, b"v", b"g", furigana_bytes=b"f", counters_bytes=b"c2")
        self.assertEqual(m2["counters"]["version"], "1.1.0")
        m3 = ud.build_manifest(m2, b"v", b"g", furigana_bytes=b"f", counters_bytes=b"c2")
        self.assertEqual(m3["counters"]["version"], "1.1.0")
        forced = ud.build_manifest(m3, b"v", b"g", furigana_bytes=b"f", counters_bytes=b"c2",
                                   counters_version="2.0.0")
        self.assertEqual(forced["counters"]["version"], "2.0.0")

    def test_no_counters_bytes_leaves_the_entry_out(self):
        self.assertNotIn("counters", ud.build_manifest({}, b"v", b"g", furigana_bytes=b"f"))


class CountersRunTests(unittest.TestCase):
    make_dir = RunTests.make_dir

    def counters_dir(self):
        d = self.make_dir()
        furigana = {"version": "1.0.0", "description": "d",
                    "readings": {"食": "た", "本": "ほん", "三本": "さんぼん", "傘": "かさ"}}
        (d / "furigana.json").write_text(json.dumps(furigana, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        doc = with_ids("counters", counters_doc(counter(examples=[{"jp": "傘を三本ください。", "en": "Three umbrellas."}])))
        doc.update(version="1.0.0", description="d")
        (d / "counters.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
        return d

    def test_a_counter_thing_without_an_id_fails_the_run(self):
        d = self.counters_dir()
        doc = json.loads((d / "counters.json").read_text(encoding="utf-8"))
        del doc["counters"][0]["things"][0]["id"]
        (d / "counters.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
        code, messages = ud.run(d, check=True)
        self.assertEqual(code, 1)
        self.assertIn("counters.json has items without a valid stable id:", messages[0])
        self.assertTrue(any("hon thing 1 has no id" in m for m in messages), messages)

    def test_a_stale_counters_file_fails_check_then_run_fixes_it(self):
        d = self.counters_dir()
        code, messages = ud.run(d, check=True)
        self.assertEqual(code, 1)
        self.assertTrue(any("data/counters.json" in m for m in messages), messages)
        code, _ = ud.run(d)
        self.assertEqual(code, 0)
        code, _ = ud.run(d, check=True)
        self.assertEqual(code, 0)
        written = json.loads((d / "counters.json").read_text(encoding="utf-8"))
        self.assertEqual(written["counters"][0]["readings"]["3"], ["さんぼん"])
        manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["counters"]["sha256"], ud.sha256_hex((d / "counters.json").read_bytes()))

    def test_run_writes_the_bundled_counters_copy_and_its_manifest_entry(self):
        d = self.counters_dir()
        bundled = d / "bundle" / "counters.json"
        code, messages = ud.run(d, check=True, bundled_counters_path=bundled)
        self.assertEqual(code, 1)
        self.assertTrue(any("the bundled counters.json" in m for m in messages), messages)
        self.assertEqual(ud.run(d, bundled_counters_path=bundled)[0], 0)
        published = (d / "counters.json").read_bytes()
        self.assertEqual(bundled.read_bytes(), published)
        manifest = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        sidecar = json.loads(ud.bundled_counters_manifest_path(bundled).read_text(encoding="utf-8"))
        self.assertEqual(sidecar, {"version": manifest["counters"]["version"], "sha256": ud.sha256_hex(published)})
        self.assertEqual(ud.run(d, check=True, bundled_counters_path=bundled), (0, ["data is up to date"]))

    def test_check_fails_when_the_bundled_counters_copy_drifts(self):
        d = self.counters_dir()
        bundled = d / "bundle" / "counters.json"
        ud.run(d, bundled_counters_path=bundled)
        bundled.write_text("{}\n", encoding="utf-8")
        code, messages = ud.run(d, check=True, bundled_counters_path=bundled)
        self.assertEqual(code, 1)
        self.assertIn("the bundled counters.json", messages[0])
        self.assertNotIn("data/counters.json", messages[0])

    def test_without_a_bundled_path_nothing_is_written_or_checked(self):
        d = self.counters_dir()
        ud.run(d)
        self.assertEqual(ud.run(d, check=True), (0, ["data is up to date"]))
        self.assertFalse((d / "bundle").exists())

    def test_an_invalid_counters_file_blocks_everything_and_writes_nothing(self):
        d = self.counters_dir()
        doc = json.loads((d / "counters.json").read_text(encoding="utf-8"))
        doc["counters"][0]["sound"] = "x"
        (d / "counters.json").write_text(json.dumps(doc, ensure_ascii=False), encoding="utf-8")
        before = {n: (d / n).read_bytes() for n in ("verbs.json", "manifest.json", "counters.json")}
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertTrue(any("sound" in m for m in messages), messages)
        for name, content in before.items():
            self.assertEqual((d / name).read_bytes(), content)

    def test_a_dictionary_misreading_of_a_counted_run_fails_the_run(self):
        d = self.counters_dir()
        furigana = json.loads((d / "furigana.json").read_text(encoding="utf-8"))
        furigana["readings"]["三本"] = "さんほん"
        (d / "furigana.json").write_text(json.dumps(furigana, ensure_ascii=False), encoding="utf-8")
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertTrue(any("三本" in m for m in messages), messages)


def id_doc(*verbs):
    return {"verbs": [dict(v) for v in verbs]}


class VerbIdTests(unittest.TestCase):
    KIRU = {"dict": "きる", "kanji": "着る"}
    KIRU_CUT = {"dict": "きる", "kanji": "切る", "id": "きる:切る"}

    def test_the_id_is_the_dict_unless_there_is_an_explicit_one(self):
        self.assertEqual(ud.verb_id(self.KIRU), "きる")
        self.assertEqual(ud.verb_id(self.KIRU_CUT), "きる:切る")

    def test_distinct_ids_are_fine(self):
        self.assertEqual(ud.check_verb_ids(id_doc(self.KIRU, self.KIRU_CUT, {"dict": "たべる"})), [])

    def test_a_homophone_without_an_explicit_id_is_rejected_with_a_suggestion(self):
        problems = ud.check_verb_ids(id_doc(self.KIRU, {"dict": "きる", "kanji": "切る"}))
        self.assertEqual(len(problems), 1)
        self.assertIn("'きる' is already used", problems[0])
        self.assertIn("きる:<kanji>", problems[0])

    def test_an_explicit_id_cannot_repeat_either(self):
        self.assertEqual(len(ud.check_verb_ids(id_doc(self.KIRU_CUT, dict(self.KIRU_CUT)))), 1)

    def test_malformed_explicit_ids_are_rejected(self):
        for bad in ("切る", "きる:", ":切る", "きる:切る/x", "かる:切る", "kiru:切る", "きる 切る", "", None, 3):
            problems = ud.check_verb_ids(id_doc({"dict": "きる", "id": bad}))
            self.assertEqual(len(problems), 1, repr(bad))
            self.assertIn("must be the verb's kana", problems[0])

    def test_the_real_data_has_valid_unique_ids(self):
        data = json.loads((Path(__file__).resolve().parent.parent / "data" / "verbs.json")
                          .read_text(encoding="utf-8"))
        self.assertEqual(ud.check_verb_ids(data), [])

    def test_a_published_id_that_disappears_is_reported(self):
        published = id_doc({"dict": "たべる"}, self.KIRU, self.KIRU_CUT)
        problems = ud.check_published_ids(id_doc({"dict": "たべる"}, self.KIRU), published)
        self.assertEqual(len(problems), 1)
        self.assertIn("きる:切る", problems[0])

    def test_a_published_id_that_is_renamed_is_reported(self):
        published = id_doc(self.KIRU_CUT)
        renamed = id_doc({"dict": "きる", "id": "きる:斬る"})
        self.assertEqual(len(ud.check_published_ids(renamed, published)), 1)

    def test_new_verbs_and_unchanged_ids_pass(self):
        published = id_doc(self.KIRU)
        self.assertEqual(ud.check_published_ids(id_doc(self.KIRU, self.KIRU_CUT), published), [])

    def test_nothing_to_compare_against_passes(self):
        self.assertEqual(ud.check_published_ids(id_doc(self.KIRU), None), [])

    def test_published_verbs_doc_reads_git_and_gives_none_when_unavailable(self):
        import subprocess
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(ud.published_verbs_doc("origin/main", repo=tmp))  # not a git repo
            run = lambda *args: subprocess.run(["git", *args], cwd=tmp, check=True, capture_output=True)
            run("init", "-q", "-b", "main")
            (Path(tmp) / "data").mkdir()
            (Path(tmp) / "data" / "verbs.json").write_text('{"verbs": [{"dict": "たべる"}]}', encoding="utf-8")
            run("add", "-A")
            run("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "x")
            self.assertEqual(ud.published_verbs_doc("main", repo=tmp), {"verbs": [{"dict": "たべる"}]})
            self.assertIsNone(ud.published_verbs_doc("origin/main", repo=tmp))  # ref does not exist

    def test_run_fails_when_a_published_id_is_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            data_dir = Path(tmp)
            for name in ("verbs.json", "grammar.json", "furigana.json", "manifest.json", "words.json",
                         "counters.json", "forms.json"):
                (data_dir / name).write_bytes((Path(__file__).resolve().parent.parent / "data" / name).read_bytes())
            published = json.loads((data_dir / "verbs.json").read_text(encoding="utf-8"))
            published["verbs"].append({"dict": "ぬく", "id": "ぬく:抜く"})
            code, messages = ud.run(data_dir, check=True, published_verbs=published)
            self.assertEqual(code, 1)
            self.assertIn("ぬく:抜く", "\n".join(messages))
            self.assertEqual(ud.run(data_dir, check=True)[0], 0)  # no published data: skipped


class CounterDistractorTests(unittest.TestCase):
    def distractors(self, counter, key):
        return ud.counter_distractors(counter, ud.counter_readings(counter))[key]

    def test_h_b_gets_unchanged_neighbour_and_misplaced_small_tsu(self):
        hon = {"reading": "ほん", "sound": "h-b"}
        self.assertEqual(self.distractors(hon, "3"), ["さんほん", "さんぽん", "さっぽん"])

    def test_a_candidate_equal_to_an_accepted_reading_is_dropped(self):
        hon = {"reading": "ほん", "sound": "h-b"}
        # いっぽん is right at 1, so the misplaced-っ candidate disappears.
        self.assertEqual(self.distractors(hon, "1"), ["いちほん", "いっぼん"])

    def test_a_plain_preferred_h_reading_gets_the_class_sound_as_its_neighbour(self):
        hon = {"reading": "ほん", "sound": "h-b"}
        # 2 is にほん; にっぽん would put a small っ after a one-kana number, so it is skipped.
        self.assertEqual(self.distractors(hon, "2"), ["にぼん"])

    def test_h_p(self):
        fun = {"reading": "ふん", "sound": "h-p"}
        self.assertEqual(self.distractors(fun, "3"), ["さんふん", "さんぶん", "さっぷん"])

    def test_non_h_class_gets_unchanged_and_the_geminated_wrong_form(self):
        mai = {"reading": "まい", "sound": "plain"}
        # さんまい is the right reading for a plain counter, so only the geminated form is left.
        self.assertEqual(self.distractors(mai, "3"), ["さっまい"])
        kai = {"reading": "かい", "sound": "k", "overrides": {"3": ["さんがい", "さんかい"]}}
        self.assertEqual(self.distractors(kai, "3"), ["さっかい"])

    def test_irregular_counters_get_only_the_unchanged_form(self):
        overrides = {key: [f"x{key}"] for key in ud.COUNTER_KEYS}
        overrides.update({"3": ["さんにん"], "4": ["よにん"]})
        nin = {"reading": "にん", "sound": "irregular", "overrides": overrides}
        self.assertEqual(self.distractors(nin, "4"), ["よんにん"])
        self.assertEqual(self.distractors(nin, "3"), [])

    def test_no_distractor_ever_equals_an_accepted_reading_for_any_class(self):
        for sound, reading in (("plain", "まい"), ("k", "こ"), ("s", "さつ"), ("h-b", "ほん"), ("h-p", "ふん")):
            counter = {"reading": reading, "sound": sound}
            readings = ud.counter_readings(counter)
            for key, wrong in ud.counter_distractors(counter, readings).items():
                self.assertLessEqual(len(wrong), 3, (sound, key))
                self.assertEqual(len(wrong), len(set(wrong)), (sound, key))
                self.assertFalse(set(wrong) & set(readings[key]), (sound, key))

    def test_apply_sets_distractors_and_reports_staleness(self):
        doc = {"counters": [counter()]}
        self.assertTrue(ud.apply_counter_readings(doc))
        self.assertEqual(doc["counters"][0]["distractors"]["3"], ["さんほん", "さんぽん", "さっぽん"])
        self.assertEqual(list(doc["counters"][0]["distractors"]), ud.COUNTER_KEYS)
        self.assertFalse(ud.apply_counter_readings(doc))
        del doc["counters"][0]["distractors"]
        self.assertTrue(ud.apply_counter_readings(doc))

    def test_counts_objects_is_an_optional_boolean(self):
        ok = ud.check_counters(counters_doc(counter(countsObjects=False)), COUNTER_READINGS)
        self.assertEqual(ok, [])
        self.assertEqual(ud.check_counters(counters_doc(counter(countsObjects=True)), COUNTER_READINGS), [])
        for bad in ("no", 0, None):
            problems = ud.check_counters(counters_doc(counter(countsObjects=bad)), COUNTER_READINGS)
            self.assertTrue(any("countsObjects" in p for p in problems), (bad, problems))
        # apply_counter_readings leaves the hand-written flag alone.
        doc = {"counters": [counter(countsObjects=False)]}
        ud.apply_counter_readings(doc)
        self.assertIs(doc["counters"][0]["countsObjects"], False)

    def test_the_check_flags_a_distractor_that_is_not_hiragana_or_is_right(self):
        doc = {"counters": [counter()]}
        ud.apply_counter_readings(doc)
        self.assertEqual(ud.check_counter_distractors(doc), [])
        doc["counters"][0]["distractors"]["3"] = ["サンボン"]
        self.assertTrue(any("hiragana" in p for p in ud.check_counter_distractors(doc)))
        doc["counters"][0]["distractors"]["3"] = ["さんぼん"]
        self.assertTrue(any("accepted" in p for p in ud.check_counter_distractors(doc)))


class CounterKeyTests(unittest.TestCase):
    def test_plain_number(self):
        cases = {5: "ご", 11: "じゅういち", 14: "じゅうよん", 20: "にじゅう", 70: "ななじゅう",
                 99: "きゅうじゅうきゅう", 100: "ひゃく", 300: "さんびゃく", 600: "ろっぴゃく",
                 800: "はっぴゃく", 1000: "せん", 3000: "さんぜん", 8000: "はっせん", 10000: "いちまん"}
        for number, expected in cases.items():
            self.assertEqual(ud.plain_number(number), expected, number)

    def test_a_counter_opts_in_to_bigger_numbers(self):
        self.assertEqual(ud.counter_keys({}), ud.COUNTER_KEYS)
        keys = ud.counter_keys({"extent": 99})
        self.assertEqual(keys[:11], ud.COUNTER_KEYS)
        self.assertEqual(keys[11:], [str(n) for n in range(11, 100)])
        self.assertEqual(len(keys), 100)

    def test_extent_and_extra(self):
        self.assertEqual(ud.counter_keys({"extent": 24})[-1], "24")
        self.assertEqual(ud.counter_keys({"extent": 10}), ud.COUNTER_KEYS)
        keys = ud.counter_keys({"extent": 59, "extra": [100]})
        self.assertEqual(keys[-2:], ["59", "100"])


class ComposeTests(unittest.TestCase):
    """Expected readings are written by hand, one counter per sound class."""

    def check(self, c, table):
        core = ud.counter_readings(c)
        for n, expected in table.items():
            self.assertEqual(ud.compose_readings(c, n, core), expected, (c["id"], n))

    def test_h_b_class_hon(self):
        self.check(counter(), {
            11: ["じゅういっぽん"], 13: ["じゅうさんぼん"], 14: ["じゅうよんほん"],
            18: ["じゅうはっぽん", "じゅうはちほん"], 20: ["にじゅっぽん", "にじっぽん"],
            30: ["さんじゅっぽん", "さんじっぽん"], 40: ["よんじゅっぽん", "よんじっぽん"], 100: ["ひゃっぽん"]})

    def test_h_p_class_fun(self):
        self.check(counter(id="fun", counter="分", reading="ふん", sound="h-p"), {
            11: ["じゅういっぷん"], 14: ["じゅうよんぷん"], 18: ["じゅうはっぷん", "じゅうはちふん"],
            20: ["にじゅっぷん", "にじっぷん"], 100: ["ひゃっぷん"]})

    def test_k_class_ko(self):
        self.check(counter(id="ko", counter="個", reading="こ", sound="k"), {
            11: ["じゅういっこ"], 14: ["じゅうよんこ"], 18: ["じゅうはっこ", "じゅうはちこ"],
            20: ["にじゅっこ", "にじっこ"], 100: ["ひゃっこ"]})

    def test_s_class_satsu(self):
        self.check(counter(id="satsu", counter="冊", reading="さつ", sound="s"), {
            11: ["じゅういっさつ"], 14: ["じゅうよんさつ"], 18: ["じゅうはっさつ"],
            20: ["にじゅっさつ", "にじっさつ"], 100: ["ひゃくさつ"]})

    def test_plain_class_mai(self):
        self.check(counter(id="mai", counter="枚", reading="まい", sound="plain"), {
            11: ["じゅういちまい"], 14: ["じゅうよんまい"], 18: ["じゅうはちまい"], 20: ["にじゅうまい"],
            70: ["ななじゅうまい"], 100: ["ひゃくまい"]})

    def irregular_nin(self, **fields):
        core = {"1": ["ひとり"], "2": ["ふたり"], "3": ["さんにん"], "4": ["よにん"], "5": ["ごにん"],
                "6": ["ろくにん"], "7": ["ななにん", "しちにん"], "8": ["はちにん"], "9": ["きゅうにん"],
                "10": ["じゅうにん"], "what": ["なんにん"]}
        return counter(id="nin", counter="人", reading="にん", sound="irregular", overrides=core, **fields)

    def test_irregular_counter_composes_through_compound(self):
        c = self.irregular_nin(compound={"1": ["いちにん"], "2": ["ににん"], "0": ["にん"]})
        self.check(c, {11: ["じゅういちにん"], 12: ["じゅうににん"], 13: ["じゅうさんにん"],
                       14: ["じゅうよにん"], 17: ["じゅうななにん", "じゅうしちにん"],
                       20: ["にじゅうにん"], 100: ["ひゃくにん"]})

    def test_irregular_counter_without_compound_cannot_compose(self):
        c = self.irregular_nin()
        self.assertIsNone(ud.compose_readings(c, 11, ud.counter_readings(c)))
        self.assertIsNone(ud.compose_readings(c, 20, ud.counter_readings(c)))

    def test_numbers_it_cannot_compose_are_none_and_core_numbers_pass_through(self):
        c = counter()
        core = ud.counter_readings(c)
        self.assertIsNone(ud.compose_readings(c, 300, core))
        self.assertEqual(ud.compose_readings(c, 3, core), ["さんぼん"])


class ExtendedReadingsTests(unittest.TestCase):
    def doc(self, *counters):
        return {"counters": list(counters)}

    def test_extended_readings_are_generated_in_key_order(self):
        readings = ud.counter_readings(counter(extent=99))
        self.assertEqual(list(readings), ud.counter_keys(counter(extent=99)))
        self.assertEqual(readings["20"], ["にじゅっぽん", "にじっぽん"])
        self.assertEqual(readings["15"], ["じゅうごほん"])
        self.assertEqual(readings["99"], ["きゅうじゅうきゅうほん"])

    def test_an_override_beats_composition(self):
        readings = ud.counter_readings(counter(extent=99, overrides={"14": ["じゅうよっぽん"]}))
        self.assertEqual(readings["14"], ["じゅうよっぽん"])
        self.assertEqual(readings["13"], ["じゅうさんぼん"])

    def test_the_old_keys_are_unchanged(self):
        hon = ud.counter_readings(counter())
        self.assertEqual(hon["1"], ["いっぽん"])
        self.assertEqual(hon["3"], ["さんぼん"])
        self.assertEqual(hon["8"], ["はっぽん", "はちほん"])
        self.assertEqual(hon["10"], ["じゅっぽん", "じっぽん"])
        self.assertEqual(hon["what"], ["なんぼん"])
        fun = ud.counter_readings(counter(id="fun", counter="分", reading="ふん", sound="h-p"))
        self.assertEqual(fun["4"], ["よんぷん"])
        mai = ud.counter_readings(counter(id="mai", counter="枚", reading="まい", sound="plain"))
        self.assertEqual(mai["4"], ["よんまい"])

    def test_changed_includes_extended_numbers(self):
        doc = self.doc(counter(extent=99), counter(id="mai", counter="枚", reading="まい", sound="plain", extent=99))
        ud.apply_counter_readings(doc)
        hon, mai = doc["counters"]
        self.assertIn("11", hon["changed"])
        self.assertIn("20", hon["changed"])
        self.assertNotIn("15", hon["changed"])
        self.assertEqual([k for k in mai["changed"] if int(k) > 10 if k != "what"], [])

    def test_distractors_cover_changed_extended_keys_only(self):
        doc = self.doc(counter(extent=99))
        ud.apply_counter_readings(doc)
        hon = doc["counters"][0]
        changed = set(hon["changed"])
        self.assertEqual(list(hon["distractors"]),
                         [k for k in ud.counter_keys(hon) if k in ud.COUNTER_KEYS or k in changed])
        self.assertIn("にじゅうほん", hon["distractors"]["20"])
        for key, wrong in hon["distractors"].items():
            self.assertTrue(set(wrong).isdisjoint(hon["readings"][key]), key)
        self.assertNotIn("15", hon["distractors"])      # unchanged: no key at all, which keeps the file small

    def test_no_impossible_small_tsu_distractor_for_a_vowel_or_voiced_counter(self):
        en = counter(id="en", counter="円", reading="えん", sound="plain", extent=99, extra=[100, 200],
                     overrides={"4": ["よえん"], "200": ["にひゃくえん"]})
        hon = counter(extent=99)
        doc = self.doc(en, hon)
        ud.apply_counter_readings(doc)
        for key, wrong in doc["counters"][0]["distractors"].items():
            if key not in ud.COUNTER_KEYS:
                self.assertFalse([w for w in wrong if "っえ" in w], (key, wrong))
        self.assertIn("200", doc["counters"][0]["distractors"])     # authored, so it has distractors
        self.assertIn("じゅういちほん", doc["counters"][1]["distractors"]["11"])

    def test_stale_detection_sees_the_new_keys(self):
        doc = self.doc(counter(extent=99))
        ud.apply_counter_readings(doc)
        self.assertFalse(ud.apply_counter_readings(doc))
        core_only = counter(extent=99, readings={k: v for k, v in doc["counters"][0]["readings"].items() if k in ud.COUNTER_KEYS})
        stale = self.doc(core_only)
        self.assertTrue(ud.apply_counter_readings(stale))


if __name__ == "__main__":
    unittest.main()


class ReviewStampTests(unittest.TestCase):
    make_dir = RunTests.make_dir

    def stamped(self, entry, generated=(), **stamp):
        review = {"by": "teacher", "on": "2026-10-24", "sha256": ud.review_hash(entry, generated)}
        review.update(stamp)
        return {**entry, "review": review}

    def test_review_hash_ignores_generated_fields_key_order_and_the_stamp(self):
        a = counter(readings={"1": ["いっぽん"]}, changed=["1"])
        b = {key: a[key] for key in reversed(list(a))}
        b["readings"] = {"1": ["different"]}
        b["review"] = {"by": "owner", "on": "2026-01-01", "sha256": "x"}
        generated = ("readings", "changed", "distractors")
        self.assertEqual(ud.review_hash(a, generated), ud.review_hash(b, generated))
        self.assertNotEqual(ud.review_hash(a), ud.review_hash(b))

    def test_review_hash_changes_with_the_text(self):
        a = counter(examples=[{"jp": "傘を三本ください。", "en": "Three umbrellas."}])
        b = counter(examples=[{"jp": "傘を二本ください。", "en": "Two umbrellas."}])
        self.assertNotEqual(ud.review_hash(a), ud.review_hash(b))

    def test_a_valid_stamp_and_no_stamp_pass(self):
        entry = counter()
        self.assertEqual(ud.check_reviews([entry, self.stamped(counter(id="hai"))]), [])

    def test_an_edit_after_review_is_reported_with_the_entry_and_date(self):
        entry = self.stamped(counter())
        entry["meaning"] = "pencils and such"
        problems = ud.check_reviews([entry])
        self.assertEqual(len(problems), 1)
        self.assertIn("hon was edited after review on 2026-10-24", problems[0])
        self.assertIn("mark_reviewed.py", problems[0])

    def test_a_bad_reviewer_or_date_is_reported(self):
        problems = ud.check_reviews([self.stamped(counter(), by="nobody"), self.stamped(counter(id="b"), on="24/10/2026"),
                                     {**counter(id="c"), "review": "yes"}])
        self.assertEqual(len(problems), 3, problems)
        self.assertTrue(any("by" in p for p in problems))
        self.assertTrue(any("on" in p for p in problems))

    def test_regenerating_counters_keeps_a_stamp_valid(self):
        d = self.make_dir()
        furigana = {"version": "1.0.0", "description": "d", "readings": {"本": "ほん", "傘": "かさ"}}
        (d / "furigana.json").write_text(json.dumps(furigana, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        with_stable_ids = with_ids("counters", {"counters": [counter()]})["counters"][0]
        doc = counters_doc(self.stamped(with_stable_ids, ud.COUNTER_GENERATED))
        doc.update(version="1.0.0", description="d")
        (d / "counters.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
        self.assertEqual(ud.run(d)[0], 0)
        first = (d / "counters.json").read_bytes()
        self.assertEqual(ud.run(d)[0], 0)
        self.assertEqual((d / "counters.json").read_bytes(), first)
        self.assertEqual(ud.run(d, check=True)[0], 0)
        written = json.loads(first)["counters"][0]
        self.assertEqual(written["review"]["by"], "teacher")
        written["meaning"] = "edited"
        doc2 = counters_doc(written)
        doc2.update(version="1.0.0", description="d")
        (d / "counters.json").write_text(json.dumps(doc2, ensure_ascii=False) + "\n", encoding="utf-8")
        code, messages = ud.run(d)
        self.assertEqual(code, 1)
        self.assertTrue(any("hon was edited after review" in m for m in messages), messages)
