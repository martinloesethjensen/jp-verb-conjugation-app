import unittest

import json_schema

SCHEMA = {
    "$defs": {"id": {"type": "string", "pattern": "^[a-km-np-z2-9]{6}$"}},
    "type": "object", "required": ["items"], "additionalProperties": False,
    "properties": {
        "level": {"enum": ["N5", "N4", "N3", "N2", "N1"]},
        "kanji": {"type": ["string", "null"]},
        "count": {"type": "integer", "minimum": 0},
        "forms": {"type": "object", "propertyNames": {"pattern": "^[a-z_]+$"},
                  "additionalProperties": {"type": "string", "minLength": 1}},
        "items": {"type": "array", "minItems": 1, "uniqueItems": True,
                  "items": {"type": "object", "required": ["id", "jp"], "additionalProperties": False,
                            "properties": {"id": {"$ref": "#/$defs/id"}, "jp": {"type": "string"}}}},
    },
}

ONE_ITEM = [{"id": "abcdef", "jp": "a"}]


class JsonSchemaTests(unittest.TestCase):
    def test_a_valid_instance_has_no_problems(self):
        doc = {"level": "N5", "kanji": None, "count": 0, "forms": {"te": "して"}, "items": ONE_ITEM}
        self.assertEqual(json_schema.validate(doc, SCHEMA), [])

    def test_problems_name_the_json_path(self):
        doc = {"level": "N6", "items": [{"id": "ABC"}, {"id": "abcdef", "jp": "b", "x": 1}], "extra": True}
        self.assertEqual(sorted(json_schema.validate(doc, SCHEMA)), sorted([
            "$.level: 'N6' is not one of ['N5', 'N4', 'N3', 'N2', 'N1']",
            "$.items[0].id: 'ABC' does not match ^[a-km-np-z2-9]{6}$",
            "$.items[0]: missing required property 'jp'",
            "$.items[1]: unexpected property 'x'",
            "$: unexpected property 'extra'",
        ]))

    def test_a_boolean_is_not_an_integer(self):
        self.assertEqual(json_schema.validate({"count": True, "items": ONE_ITEM}, SCHEMA),
                         ["$.count: expected integer, got boolean"])

    def test_type_lists_name_every_type(self):
        self.assertIn("$.kanji: expected string or null, got integer",
                      json_schema.validate({"kanji": 3, "items": ONE_ITEM}, SCHEMA))

    def test_map_keys_and_values_are_checked(self):
        problems = json_schema.validate({"forms": {"x y": ""}, "items": ONE_ITEM}, SCHEMA)
        self.assertIn("$.forms: property name 'x y' does not match ^[a-z_]+$", problems)
        self.assertIn("$.forms['x y']: shorter than 1 character(s)", problems)

    def test_array_and_number_rules(self):
        self.assertIn("$.items: expected at least 1 item(s)", json_schema.validate({"items": []}, SCHEMA))
        dup = {"id": "abcdef", "jp": "a"}
        self.assertIn("$.items: items are not unique", json_schema.validate({"items": [dup, dup]}, SCHEMA))
        self.assertIn("$.count: less than 0", json_schema.validate({"count": -1, "items": ONE_ITEM}, SCHEMA))

    def test_unsupported_keywords_are_reported_at_any_depth(self):
        self.assertEqual(json_schema.check_schema({"properties": {"a": {"oneOf": []}}, "$defs": {"b": {"format": "date"}}}),
                         ["$.properties.a: unsupported keyword 'oneOf'", "$.$defs.b: unsupported keyword 'format'"])
        self.assertEqual(json_schema.check_schema(SCHEMA), [])

    def test_only_local_refs_are_allowed(self):
        self.assertEqual(json_schema.check_schema({"$ref": "https://example.com/x.json"}),
                         ["$: only '#/$defs/<name>' refs are supported"])


if __name__ == "__main__":
    unittest.main()
