import json
import re
import unittest

import assign_ids
import stable_ids

GRAMMAR = '''{
  "grammar": [
    {
      "id": "n-desu",
      "usages": [
        {
          "heading": "h",
          "examples": [
            { "jp": "あ。", "en": "a" }
          ]
        }
      ],
      "pitfalls": []
    }
  ]
}
'''

AN_ID = r"[a-km-np-z2-9]{6}"


class AssignIdsTests(unittest.TestCase):
    def test_grammar_gets_ids_and_is_otherwise_unchanged(self):
        text, added = assign_ids.assign_grammar_text(GRAMMAR)
        self.assertEqual(added, 2)
        self.assertEqual(stable_ids.check_stable_ids("grammar", json.loads(text)), [])
        stripped = re.sub(rf'"id": "{AN_ID}",\s*', "", text)
        self.assertEqual(re.sub(r"\s+", "", stripped), re.sub(r"\s+", "", GRAMMAR))
        self.assertRegex(text, rf'\n        \{{\n          "id": "{AN_ID}",\n          "heading": "h",')
        self.assertRegex(text, rf'\{{ "id": "{AN_ID}", "jp": "あ。", "en": "a" \}}')

    def test_running_twice_changes_nothing(self):
        once, _ = assign_ids.assign_grammar_text(GRAMMAR)
        twice, added = assign_ids.assign_grammar_text(once)
        self.assertEqual((twice, added), (once, 0))

    def test_an_unrecognised_layout_raises_instead_of_writing(self):
        odd = GRAMMAR.replace('{ "jp": "あ。", "en": "a" }', '{ "en": "a", "jp": "あ。" }')
        with self.assertRaises(ValueError):
            assign_ids.assign_grammar_text(odd)

    def test_json_assignment_keeps_existing_ids_and_puts_new_ones_first(self):
        doc = {"verbs": [{"dict": "たべる", "examples": [{"id": "abcdef", "jp": "a"}, {"form": "te", "jp": "b"}]}]}
        self.assertEqual(assign_ids.assign_json("verbs", doc), 1)
        examples = doc["verbs"][0]["examples"]
        self.assertEqual(examples[0]["id"], "abcdef")
        self.assertEqual(list(examples[1])[0], "id")
        self.assertNotEqual(examples[1]["id"], "abcdef")


if __name__ == "__main__":
    unittest.main()
