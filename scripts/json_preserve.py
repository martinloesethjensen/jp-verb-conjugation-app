"""Rewrite a JSON file with new content while keeping its hand formatting.

    text = json_preserve.rewrite(old_text, new_doc)

Every subtree whose value didn't change keeps its original bytes. A container that changed is rebuilt in the
layout it had: one line stays one line, several lines keep their indentation. Something new takes the style of
what it replaces or of its siblings: a new list item looks like the items before it; a new object is written
on one line when it holds only plain values, else over several lines with one-line list items. Objects keep
their key order (new keys go last), and list items are matched by their "id" when every item has one.

Used for data/grammar.json and data/furigana.json, which are hand-formatted; the other data files have
`dump_*` writers in update_data.py.
"""
import json
import re
from dataclasses import dataclass, field
from json.decoder import scanstring

_NUMBER = re.compile(r"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][-+]?\d+)?")
_SPACE = " \t\n\r"


@dataclass
class _Node:
    start: int
    end: int
    value: object
    # Objects: (key, offset where the member's key starts, offset where its value starts, child).
    members: list = field(default_factory=list)
    # Arrays: the item nodes.
    items: list = field(default_factory=list)


class _Parser:
    def __init__(self, text):
        self.text = text

    def skip(self, i):
        while i < len(self.text) and self.text[i] in _SPACE:
            i += 1
        return i

    def value(self, i):
        i = self.skip(i)
        c = self.text[i]
        if c == "{":
            return self.obj(i)
        if c == "[":
            return self.arr(i)
        if c == '"':
            s, end = scanstring(self.text, i + 1)
            return _Node(i, end, s)
        for word, v in (("true", True), ("false", False), ("null", None)):
            if self.text.startswith(word, i):
                return _Node(i, i + len(word), v)
        m = _NUMBER.match(self.text, i)
        if not m:
            raise ValueError(f"not JSON at offset {i}")
        return _Node(i, m.end(), json.loads(m.group()))

    def obj(self, start):
        node = _Node(start, start, {})
        i = self.skip(start + 1)
        if self.text[i] == "}":
            node.end = i + 1
            return node
        while True:
            key_start = i
            key, i = scanstring(self.text, i + 1)
            i = self.skip(i)
            assert self.text[i] == ":"
            child = self.value(i + 1)
            node.members.append((key, key_start, child.start, child))
            node.value[key] = child.value
            i = self.skip(child.end)
            if self.text[i] == "}":
                node.end = i + 1
                return node
            i = self.skip(i + 1)

    def arr(self, start):
        node = _Node(start, start, [])
        i = self.skip(start + 1)
        if self.text[i] == "]":
            node.end = i + 1
            return node
        while True:
            child = self.value(i)
            node.items.append(child)
            node.value.append(child.value)
            i = self.skip(child.end)
            if self.text[i] == "]":
                node.end = i + 1
                return node
            i = self.skip(i + 1)


def _same(a, b):
    """Equal values of the same JSON types (Python's == says True == 1)."""
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return a.keys() == b.keys() and list(a) == list(b) and all(_same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(_same(x, y) for x, y in zip(a, b))
    return a == b


def _dumps(value):
    return json.dumps(value, ensure_ascii=False)


def _inline(value):
    if isinstance(value, dict):
        if not value:
            return "{}"
        return "{ " + ", ".join(f"{_dumps(k)}: {_inline(v)}" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "[" + ", ".join(_inline(v) for v in value) + "]"
    return _dumps(value)


def _plain(value):
    return not isinstance(value, (dict, list))


def _flat(value):
    """A dict that reads on one line: plain values, lists of plain values, lists of plain dicts."""
    def ok(v):
        if _plain(v):
            return True
        if isinstance(v, list):
            return all(_plain(x) or (isinstance(x, dict) and all(_plain(y) for y in x.values())) for x in v)
        return False
    return isinstance(value, dict) and all(ok(v) for v in value.values())


def _fresh(value, indent, multiline=None):
    """Text for a new value whose first line is already at `indent` (the closing bracket goes there too)."""
    if _plain(value):
        return _dumps(value)
    if multiline is None:
        multiline = not (_flat(value) if isinstance(value, dict) else all(_plain(v) for v in value))
    if not multiline or not value:
        return _inline(value)
    inner = indent + "  "
    if isinstance(value, dict):
        lines = [f"{inner}{_dumps(k)}: {_fresh(v, inner)}" for k, v in value.items()]
        return "{\n" + ",\n".join(lines) + f"\n{indent}}}"
    lines = [inner + _fresh(v, inner, multiline=not _flat(v) if isinstance(v, dict) else None) for v in value]
    return "[\n" + ",\n".join(lines) + f"\n{indent}]"


class _Writer:
    def __init__(self, text):
        self.text = text

    def line_indent(self, offset):
        line_start = self.text.rfind("\n", 0, offset) + 1
        line = self.text[line_start:offset]
        return line[:len(line) - len(line.lstrip(" \t"))]

    def render(self, node, new):
        if _same(node.value, new):
            return self.text[node.start:node.end]
        old = node.value
        if isinstance(old, dict) and isinstance(new, dict):
            return self.obj(node, new)
        if isinstance(old, list) and isinstance(new, list):
            return self.arr(node, new)
        return _fresh(new, self.line_indent(node.start), "\n" in self.text[node.start:node.end] or None)

    def layout(self, node, first_child_start):
        """(multi-line, child indent, closing indent, open text, close text) of a container."""
        span = self.text[node.start:node.end]
        close_indent = self.line_indent(node.end - 1)
        if "\n" in span:
            child = self.line_indent(first_child_start) if first_child_start is not None else close_indent + "  "
            return True, child, close_indent
        return False, "", close_indent

    def obj(self, node, new):
        first = node.members[0][1] if node.members else None
        multiline, child_indent, close_indent = self.layout(node, first)
        if not node.members:
            return _fresh(new, close_indent)
        old = {key: (key_start, value_start, child) for key, key_start, value_start, child in node.members}
        parts = []
        for key, value in new.items():
            if key in old:
                key_start, value_start, child = old[key]
                parts.append(self.text[key_start:value_start] + self.render(child, value))
            elif multiline:
                parts.append(f"{_dumps(key)}: {_fresh(value, child_indent)}")
            else:
                parts.append(f"{_dumps(key)}: {_inline(value)}")
        if multiline:
            return "{\n" + ",\n".join(child_indent + p for p in parts) + f"\n{close_indent}}}"
        opening = self.text[node.start + 1:first]
        closing = self.text[node.members[-1][3].end:node.end - 1]
        return "{" + opening + ", ".join(parts) + closing + "}"

    def arr(self, node, new):
        first = node.items[0].start if node.items else None
        multiline, child_indent, close_indent = self.layout(node, first)
        if not node.items:
            return _fresh(new, close_indent)
        by_id = all(isinstance(v, dict) and "id" in v for v in node.value) and \
            all(isinstance(v, dict) and "id" in v for v in new)
        olds = {item.value["id"]: item for item in node.items} if by_id else {}
        last = node.items[-1]
        last_multiline = "\n" in self.text[last.start:last.end]
        parts = []
        for index, value in enumerate(new):
            match = olds.get(value["id"]) if by_id else (node.items[index] if index < len(node.items) else None)
            if match is not None:
                parts.append(self.render(match, value))
            elif multiline:
                parts.append(_fresh(value, child_indent, last_multiline if not _plain(value) else None))
            else:
                parts.append(_inline(value))
        if multiline:
            return "[\n" + ",\n".join(child_indent + p for p in parts) + f"\n{close_indent}]"
        opening = self.text[node.start + 1:first]
        closing = self.text[last.end:node.end - 1]
        return "[" + opening + ", ".join(parts) + closing + "]"


def rewrite(old_text, new_doc):
    """`new_doc` as JSON text in `old_text`'s formatting (see the module docstring)."""
    root = _Parser(old_text).value(0)
    result = old_text[:root.start] + _Writer(old_text).render(root, new_doc) + old_text[root.end:]
    if not _same(json.loads(result), new_doc):
        raise ValueError("rewrite produced different JSON")
    return result
