import copy
import json
import unittest
from pathlib import Path

import json_preserve as jp

DATA = Path(__file__).resolve().parent.parent / "data"


def changed_lines(old, new):
    """Lines of `new` that aren't at the same place in `old`, after lining up the shared start and end."""
    a, b = old.splitlines(), new.splitlines()
    start = 0
    while start < min(len(a), len(b)) and a[start] == b[start]:
        start += 1
    end = 0
    while end < min(len(a), len(b)) - start and a[-1 - end] == b[-1 - end]:
        end += 1
    return a[start:len(a) - end], b[start:len(b) - end]


class RoundTripTests(unittest.TestCase):
    def test_unchanged_grammar_round_trips(self):
        for name in ("grammar", "furigana"):
            text = (DATA / f"{name}.json").read_text(encoding="utf-8")
            self.assertEqual(jp.rewrite(text, json.loads(text)), text, name)


class EditTests(unittest.TestCase):
    def setUp(self):
        self.text = (DATA / "grammar.json").read_text(encoding="utf-8")
        self.doc = json.loads(self.text)
        self.usage = self.doc["grammar"][0]["usages"][0]

    def rewrite(self):
        result = jp.rewrite(self.text, self.doc)
        self.assertEqual(json.loads(result), self.doc)
        return result

    def test_one_example_edit_changes_one_line(self):
        before = self.usage["examples"][0]["en"]
        self.usage["examples"][0]["en"] = "Something else entirely."
        old, new = changed_lines(self.text, self.rewrite())
        self.assertEqual(len(old), 1)
        self.assertEqual(new, [old[0].replace(json.dumps(before, ensure_ascii=False),
                                              '"Something else entirely."')])

    def test_new_example_matches_its_siblings(self):
        examples = self.usage["examples"]
        examples.append({"id": "zzzzz2", "jp": "新しい文です。", "en": "A new sentence."})
        old, new = changed_lines(self.text, self.rewrite())
        self.assertEqual(old, [old[0]])
        self.assertEqual(new[0], old[0] + ",")
        indent = old[0][:len(old[0]) - len(old[0].lstrip())]
        self.assertEqual(new[1], indent + '{ "id": "zzzzz2", "jp": "新しい文です。", "en": "A new sentence." }')
        self.assertEqual(len(new), 2)

    def test_removed_item_takes_its_comma_with_it(self):
        examples = self.usage["examples"]
        removed = examples.pop()
        result = self.rewrite()
        old, new = changed_lines(self.text, result)
        self.assertEqual(len(old), 2)
        self.assertIn(removed["id"], old[1])
        self.assertEqual(new, [old[0].rstrip(",")])

    def test_new_usage_is_multi_line(self):
        usages = self.doc["grammar"][0]["usages"]
        usages.append({"id": "zzzzz3", "heading": "H", "explanation": "E",
                       "examples": [{"id": "zzzzz4", "jp": "文。", "en": "S.",
                                     "particle_blanks": [{"particle": "は", "at": 0}]}]})
        old, new = changed_lines(self.text, self.rewrite())
        self.assertEqual(old, [])  # the new block sits between the old last usage and the shared closing lines
        indent = new[0][:len(new[0]) - len(new[0].lstrip())]
        self.assertEqual(new, [
            indent + "},",
            indent + "{",
            indent + '  "id": "zzzzz3",',
            indent + '  "heading": "H",',
            indent + '  "explanation": "E",',
            indent + '  "examples": [',
            indent + '    { "id": "zzzzz4", "jp": "文。", "en": "S.", "particle_blanks": [{ "particle": "は", "at": 0 }] }',
            indent + "  ]",
        ])

    def test_new_key_and_removed_key(self):
        point = self.doc["grammar"][0]
        point["review"] = {"by": "native", "on": "2026-11-07", "sha256": "a" * 64}
        with_review = self.rewrite()
        self.assertIn('"review": { "by": "native", "on": "2026-11-07", "sha256": "' + "a" * 64 + '" }',
                      with_review)
        del point["review"]
        self.assertEqual(jp.rewrite(with_review, point_doc := copy.deepcopy(self.doc)), self.text)
        self.assertEqual(point_doc, json.loads(self.text))

    def test_types_are_compared_strictly(self):
        doc = {"a": 1, "b": [1, 2]}
        text = '{\n  "a": 1,\n  "b": [1, 2]\n}\n'
        self.assertEqual(jp.rewrite(text, {"a": True, "b": [1, 2]}), '{\n  "a": true,\n  "b": [1, 2]\n}\n')
        self.assertEqual(jp.rewrite(text, doc), text)


if __name__ == "__main__":
    unittest.main()
