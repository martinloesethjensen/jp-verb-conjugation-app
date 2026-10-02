#!/usr/bin/env python3
"""Lightweight consistency checks for project.yml (no Xcode needed).

    python3 scripts/check_project.py

  1. MARKETING_VERSION and CURRENT_PROJECT_VERSION agree across every target.
  2. Local paths referenced by project.yml (sources, plists, entitlements,
     package paths) exist.

Standard library only; project.yml is scanned with regexes, not parsed.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
text = (ROOT / "project.yml").read_text(encoding="utf-8")
errors = []

for key in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
    values = set(re.findall(rf"^\s*{key}:\s*\"?([^\"\s#]+)\"?", text, re.M))
    if not values:
        errors.append(f"{key} not found in project.yml")
    elif len(values) > 1:
        errors.append(f"{key} differs between targets: {sorted(values)}")

paths = re.findall(r"^\s*(?:-\s+)?path:\s*\"?([^\"\s#]+)\"?", text, re.M)
paths += re.findall(r"^\s*CODE_SIGN_ENTITLEMENTS:\s*\"?([^\"\s#]+)\"?", text, re.M)
for rel in sorted(set(paths)):
    if not (ROOT / rel).exists():
        errors.append(f"project.yml references missing path: {rel}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print("project.yml is consistent")
