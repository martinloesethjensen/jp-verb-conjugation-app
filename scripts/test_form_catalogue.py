import json
import re
import unittest
from pathlib import Path

import form_catalogue as fc
import update_data as ud

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
FORMS_JSON = ud.DEFAULT_FORMS_PATH
QUIZ_FORM_SWIFT = ROOT / "Packages/VerbKit/Sources/VerbKit/Quiz/QuizForm.swift"


class CatalogueInvariantTests(unittest.TestCase):
    def test_catalogue_is_sound(self):
        self.assertEqual(fc.problems(), [])

    def test_ids_are_unique(self):
        ids = [s.id for s in fc.FORMS]
        self.assertEqual(len(ids), len(set(ids)))

    def test_every_family_has_forms(self):
        used = {s.family for s in fc.FORMS}
        self.assertEqual(used, {family_id for family_id, _ in fc.FAMILIES})

    def test_a_problem_is_reported_for_an_unknown_family(self):
        bad = fc.FormSpec(id="x", family="nope")
        original = fc.FORMS
        try:
            fc.FORMS = original + (bad,)
            self.assertTrue(any("unknown family" in p for p in fc.problems()))
        finally:
            fc.FORMS = original

    def test_only_the_nine_core_forms_are_authored_and_searchable(self):
        core = ["masu_pos", "masu_neg", "masu_past", "masu_past_neg", "te",
                "short_pos", "short_neg", "short_past", "short_past_neg"]
        self.assertEqual(fc.ids("verb", source="authored"), core)
        self.assertEqual([s.id for s in fc.FORMS if s.search], core)

    def test_labels_are_built_from_facets(self):
        self.assertEqual(fc.spec("masu_past").label, "Polite · past")
        self.assertEqual(fc.spec("te").label, "て-form")
        self.assertEqual(fc.spec("short_past_neg").label, "Plain · past · negative")
        self.assertEqual(fc.spec("pot_masu_past_neg").label, "Potential · polite · past · negative")
        self.assertEqual(fc.spec("teiru_te").label, "ている · て-form")
        self.assertEqual(fc.spec("nd_casual_neg").label, "んです · casual · negative")
        self.assertEqual(fc.spec("nagara").label, "ながら")

    def test_published_json_leaves_out_unset_facets(self):
        published = fc.spec("te").to_json()
        self.assertNotIn("polarity", published)
        self.assertNotIn("grammar", published)
        self.assertEqual(published["role"], "connective")


class CatalogueMatchesRulesTests(unittest.TestCase):
    """The script's tables hold endings; the catalogue holds ids and order."""

    def test_nd_tables_cover_exactly_the_nd_family(self):
        self.assertEqual([name for name, _, _ in ud.ND_FIELDS], fc.ids("verb", family="nd"))

    def test_potential_tables_cover_exactly_the_potential_family(self):
        self.assertEqual(ud.POTENTIAL_FIELDS[0], "potential")
        self.assertEqual(
            [name for name, _ in ud.POTENTIAL_CONJUGATIONS], ud.POTENTIAL_FIELDS[1:]
        )

    def test_auxiliary_tables_cover_exactly_the_auxiliary_family(self):
        table = ud.TE_AUXILIARY_FIELDS + ud.STEM_AUXILIARY_FIELDS
        self.assertEqual(table, fc.ids("verb", family="auxiliary"))

    def test_every_derived_form_has_a_rule(self):
        covered = (
            [name for name, _, _ in ud.ND_FIELDS] + ud.POTENTIAL_FIELDS + ud.AUXILIARY_FIELDS
        )
        self.assertEqual(sorted(covered), sorted(fc.ids("verb", source="derived")))


class CheckVerbFormsTests(unittest.TestCase):
    def doc(self, forms=None, example_form="te"):
        return {"verbs": [{
            "dict": "たべる",
            "forms": forms or {"te": "たべて"},
            "examples": [{"form": example_form, "jp": "x", "en": "y"}],
        }]}

    def test_known_forms_pass(self):
        self.assertEqual(ud.check_verb_forms(self.doc()), [])

    def test_an_unknown_form_is_reported(self):
        problems = ud.check_verb_forms(self.doc(forms={"te": "たべて", "tei": "x"}))
        self.assertEqual(len(problems), 1)
        self.assertIn("unknown form 'tei'", problems[0])

    def test_an_example_with_an_unknown_form_is_reported(self):
        problems = ud.check_verb_forms(self.doc(example_form="nope"))
        self.assertIn("example uses unknown form 'nope'", problems[0])

    def test_an_example_may_use_any_verb_form(self):
        self.assertEqual(ud.check_verb_forms(self.doc(example_form="pot_masu_neg")), [])


class RealDataTests(unittest.TestCase):
    def test_data_is_up_to_date(self):
        """The golden check: regenerating the repo's data changes nothing."""
        code, messages = ud.run(DATA, check=True, forms_path=FORMS_JSON)
        self.assertEqual((code, messages), (0, ["data is up to date"]))

    def test_forms_json_is_the_generated_catalogue(self):
        self.assertEqual(FORMS_JSON.read_text(encoding="utf-8"), ud.dump_forms())

    def test_every_verb_key_is_known_and_in_catalogue_order(self):
        verbs = json.loads((DATA / "verbs.json").read_text(encoding="utf-8"))["verbs"]
        order = [s.id for s in fc.FORMS]
        for verb in verbs:
            keys = list(verb["forms"])
            self.assertEqual(keys, sorted(keys, key=order.index), verb["dict"])

    def test_every_verb_has_the_nine_core_forms(self):
        verbs = json.loads((DATA / "verbs.json").read_text(encoding="utf-8"))["verbs"]
        for verb in verbs:
            for key in fc.ids("verb", source="authored"):
                self.assertTrue(verb["forms"].get(key), f"{verb['dict']}: {key}")

    def test_every_grammar_link_is_a_lesson(self):
        grammar = json.loads((DATA / "grammar.json").read_text(encoding="utf-8"))["grammar"]
        lessons = {point["id"] for point in grammar}
        for s in fc.FORMS:
            if s.grammar is not None:
                self.assertIn(s.grammar, lessons, s.id)


@unittest.skipUnless(QUIZ_FORM_SWIFT.exists(), "QuizForm.swift not present")
class MatchesTheQuizTests(unittest.TestCase):
    """Until the quiz reads the catalogue, the two must agree on id, order
    within a family and label. Delete with `QuizForm.all`."""

    PATTERN = re.compile(
        r'make\("(\w+)", \.(\w+), name: (nil|"[^"]*"), register: (nil|"[^"]*")(.*?)\) \{'
    )

    def swift_forms(self):
        text = QUIZ_FORM_SWIFT.read_text(encoding="utf-8")
        forms = []
        for m in self.PATTERN.finditer(text):
            form_id, _topic, name, register, rest = m.groups()
            name = None if name == "nil" else name.strip('"')
            register = None if register == "nil" else register.strip('"')
            label = " · ".join(part for part in [
                name, register,
                "past" if "past: true" in rest else None,
                "negative" if "negative: true" in rest else None,
            ] if part)
            forms.append((form_id, label))
        return forms

    def test_same_forms_and_labels(self):
        swift = self.swift_forms()
        self.assertEqual(len(swift), len(fc.FORMS))
        for form_id, label in swift:
            spec = fc.spec(form_id)
            self.assertIsNotNone(spec, form_id)
            self.assertEqual(spec.label, label, form_id)


if __name__ == "__main__":
    unittest.main()
