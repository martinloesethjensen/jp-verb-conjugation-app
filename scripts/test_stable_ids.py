import unittest

import stable_ids


class StableIdTests(unittest.TestCase):
    def test_new_ids_match_the_pattern_and_are_unique(self):
        taken = set()
        ids = [stable_ids.new_id(taken) for _ in range(500)]
        self.assertEqual(len(set(ids)), 500)
        self.assertTrue(all(stable_ids.ID_PATTERN.match(i) for i in ids))
        self.assertEqual(taken, set(ids))

    def test_verb_slots_are_the_examples(self):
        doc = {"verbs": [{"dict": "たべる", "examples": [{"jp": "a"}, {"jp": "b"}]}]}
        self.assertEqual([label for label, _ in stable_ids.id_slots("verbs", doc)],
                         ["たべる example 1", "たべる example 2"])

    def test_a_verb_with_an_explicit_id_is_labelled_by_it(self):
        doc = {"verbs": [{"id": "きる:切る", "dict": "きる", "examples": [{"jp": "a"}]}]}
        self.assertEqual([label for label, _ in stable_ids.id_slots("verbs", doc)], ["きる:切る example 1"])

    def test_grammar_slots_cover_usages_pitfalls_and_their_examples(self):
        doc = {"grammar": [{"id": "n-desu",
                            "usages": [{"heading": "h", "examples": [{"jp": "a"}]}],
                            "pitfalls": [{"heading": "p", "examples": [{"jp": "b"}, {"jp": "c"}]}]}]}
        self.assertEqual([label for label, _ in stable_ids.id_slots("grammar", doc)],
                         ["n-desu usage 1", "n-desu usage 1 example 1", "n-desu pitfall 1",
                          "n-desu pitfall 1 example 1", "n-desu pitfall 1 example 2"])

    def test_grammar_contrast_examples_are_slots_but_the_contrast_is_not(self):
        doc = {"grammar": [{"id": "node", "contrasts": [{"id": "kara", "pattern": "から",
                                                        "examples": [{"jp": "a"}, {"jp": "b"}]}]}]}
        self.assertEqual([label for label, _ in stable_ids.id_slots("grammar", doc)],
                         ["node contrast 1 example 1", "node contrast 1 example 2"])

    def test_a_duplicate_key_is_rejected_when_parsing(self):
        with self.assertRaises(ValueError) as caught:
            stable_ids.loads('{"examples": [{"id": "abcdef", "jp": "a", "id": "bcdefg"}]}')
        self.assertIn("'id'", str(caught.exception))
        self.assertEqual(stable_ids.loads('{"a": {"id": "x"}, "b": {"id": "y"}}'), {"a": {"id": "x"}, "b": {"id": "y"}})

    def test_counter_slots_cover_things_examples_and_pitfalls(self):
        doc = {"counters": [{"id": "hon", "things": [{"word": "ペン"}], "examples": [{"jp": "a"}],
                             "pitfalls": [{"heading": "p", "examples": [{"jp": "b"}]}]}]}
        self.assertEqual([label for label, _ in stable_ids.id_slots("counters", doc)],
                         ["hon thing 1", "hon example 1", "hon pitfall 1", "hon pitfall 1 example 1"])

    def test_missing_duplicate_and_malformed_ids_are_reported(self):
        doc = {"verbs": [{"dict": "たべる", "examples": [
            {"id": "abcdef", "jp": "a"}, {"id": "abcdef", "jp": "b"}, {"jp": "c"}, {"id": "ABC", "jp": "d"}]}]}
        problems = stable_ids.check_stable_ids("verbs", doc)
        self.assertIn("たべる example 2: id 'abcdef' is also used by たべる example 1", problems)
        self.assertIn("たべる example 3 has no id: run scripts/assign_ids.py", problems)
        self.assertIn("たべる example 4: id 'ABC' is not 6 characters from the id alphabet", problems)
        self.assertEqual(len(problems), 3)

    def test_unknown_dataset_raises(self):
        with self.assertRaises(ValueError):
            stable_ids.id_slots("words", {})


if __name__ == "__main__":
    unittest.main()
