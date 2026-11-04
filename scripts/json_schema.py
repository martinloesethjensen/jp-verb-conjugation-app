"""A validator for the small subset of JSON Schema (2020-12) that schema/*.schema.json use.

update_data.py stays standard-library only, so it can't depend on the `jsonschema` package. The schemas keep
to the keywords in SUPPORTED, so every client that reads data/ (the review site's Rust Worker now, an Android
app later) can rely on the same small set. `check_schema` rejects anything outside it.
"""
import json
import re

SUPPORTED = frozenset({
    "$schema", "$id", "$defs", "$ref", "title", "description", "type", "enum", "const", "pattern",
    "minLength", "minimum", "required", "properties", "additionalProperties", "patternProperties",
    "propertyNames", "items", "minItems", "uniqueItems",
})

_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_LOCAL_REF = re.compile(r"^#/\$defs/([^/]+)$")


def _member(path, name):
    return f"{path}.{name}" if _NAME.match(name) else f"{path}[{name!r}]"


def _json_type(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    return "object"


def _has_type(value, name):
    actual = _json_type(value)
    return actual == name or (name == "number" and actual == "integer")


def check_schema(schema):
    """Problems with `schema` itself: keywords outside SUPPORTED and refs that aren't '#/$defs/<name>'."""
    problems = []

    def walk(node, path):
        if not isinstance(node, dict):
            return
        problems.extend(f"{path}: unsupported keyword '{key}'" for key in node if key not in SUPPORTED)
        if "$ref" in node and not _LOCAL_REF.match(str(node["$ref"])):
            problems.append(f"{path}: only '#/$defs/<name>' refs are supported")
        for key in ("properties", "patternProperties", "$defs"):
            for name, sub in (node.get(key) or {}).items():
                walk(sub, _member(f"{path}.{key}", name))
        for key in ("additionalProperties", "items", "propertyNames"):
            if isinstance(node.get(key), dict):
                walk(node[key], f"{path}.{key}")

    walk(schema, "$")
    return problems


def validate(instance, schema):
    """Problems with `instance` against `schema`, each "<json path>: <message>". Never raises for bad instances."""
    defs = schema.get("$defs") or {}
    problems = []

    def check(value, node, path):
        if "$ref" in node:
            node = defs[_LOCAL_REF.match(node["$ref"]).group(1)]
        if "type" in node:
            names = node["type"] if isinstance(node["type"], list) else [node["type"]]
            if not any(_has_type(value, name) for name in names):
                problems.append(f"{path}: expected {' or '.join(names)}, got {_json_type(value)}")
                return
        if "const" in node and value != node["const"]:
            problems.append(f"{path}: {value!r} is not {node['const']!r}")
        if "enum" in node and value not in node["enum"]:
            problems.append(f"{path}: {value!r} is not one of {node['enum']!r}")
        if isinstance(value, str):
            if "pattern" in node and not re.search(node["pattern"], value):
                problems.append(f"{path}: {value!r} does not match {node['pattern']}")
            if "minLength" in node and len(value) < node["minLength"]:
                problems.append(f"{path}: shorter than {node['minLength']} character(s)")
        if _json_type(value) in ("integer", "number") and "minimum" in node and value < node["minimum"]:
            problems.append(f"{path}: less than {node['minimum']}")
        if isinstance(value, list):
            if "minItems" in node and len(value) < node["minItems"]:
                problems.append(f"{path}: expected at least {node['minItems']} item(s)")
            if node.get("uniqueItems"):
                seen = [json.dumps(item, sort_keys=True) for item in value]
                if len(set(seen)) != len(seen):
                    problems.append(f"{path}: items are not unique")
            if isinstance(node.get("items"), dict):
                for index, item in enumerate(value):
                    check(item, node["items"], f"{path}[{index}]")
        if isinstance(value, dict):
            check_object(value, node, path)

    def check_object(value, node, path):
        problems.extend(f"{path}: missing required property '{name}'"
                        for name in node.get("required") or [] if name not in value)
        properties = node.get("properties") or {}
        patterns = node.get("patternProperties") or {}
        names = node.get("propertyNames")
        extra = node.get("additionalProperties", True)
        for name, member in value.items():
            member_path = _member(path, name)
            if names is not None:
                if "pattern" in names and not re.search(names["pattern"], name):
                    problems.append(f"{path}: property name {name!r} does not match {names['pattern']}")
                if "enum" in names and name not in names["enum"]:
                    problems.append(f"{path}: property name {name!r} is not one of {names['enum']!r}")
            matched = False
            if name in properties:
                matched = True
                check(member, properties[name], member_path)
            for pattern, sub in patterns.items():
                if re.search(pattern, name):
                    matched = True
                    check(member, sub, member_path)
            if matched:
                continue
            if extra is False:
                problems.append(f"{path}: unexpected property '{name}'")
            elif isinstance(extra, dict):
                check(member, extra, member_path)

    check(instance, schema, "$")
    return problems
