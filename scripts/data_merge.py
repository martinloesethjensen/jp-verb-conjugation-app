#!/usr/bin/env python3
"""Brings main into a data branch without hand-resolving generated files.

    python3 scripts/data_merge.py            # merge origin/main into the current branch
    python3 scripts/data_merge.py --no-fetch # use the origin/main you already have

Two data pull requests that both touch data/ always clash on the files update_data.py writes:
data/manifest.json, data/manifest.sig, data/forms.json and the bundled copies (plus their
*.manifest.json sidecars) in Packages/VerbKit/Sources/VerbKit/Resources. None of those is ever
edited by hand, so this script:

  1. fetches and merges origin/main into the current branch;
  2. takes main's side of every conflict in a generated file;
  3. stops, leaving the merge in progress, if a hand-authored file (data/verbs.json, ...)
     conflicts, because two pull requests editing the same entry need a person to decide;
  4. reruns update_data.py, so the generated files match the merged sources, and commits.

It needs no signing key: feature branches are not signed. The owner signs once per batch of
merged pull requests with `make data-release` (see docs/security/data-signing.md).
Standard library only.
"""
import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLED_DIR = "Packages/VerbKit/Sources/VerbKit/Resources/"
GENERATED_FILES = {"data/manifest.json", "data/manifest.sig", "data/forms.json"}
# Bundled copies that update_data.py writes. dialects.json lives there too but is hand-authored.
BUNDLED_NAMES = {"verbs", "grammar", "furigana", "words", "counters", "forms", "kanji"}


def is_generated(path):
    """True for a file update_data.py (or signing) rewrites, so main's copy can be taken."""
    if path in GENERATED_FILES:
        return True
    if path.startswith(BUNDLED_DIR):
        name = path[len(BUNDLED_DIR):]
        for stem in BUNDLED_NAMES:
            if name in (f"{stem}.json", f"{stem}.manifest.json"):
                return True
    return False


def split_conflicts(paths):
    """Splits conflicted paths into (generated, hand_authored), each sorted."""
    generated = sorted(p for p in paths if is_generated(p))
    authored = sorted(p for p in paths if not is_generated(p))
    return generated, authored


def git(*args, cwd, check=True, capture=True):
    return subprocess.run(["git", *args], cwd=cwd, check=check, text=True,
                          capture_output=capture)


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    return 1


def merge(repo, base="origin/main", fetch=True, regenerate=None):
    """Merges `base` into the current branch of `repo`; returns an exit code."""
    regenerate = regenerate or [sys.executable, str(Path(repo) / "scripts/update_data.py")]

    branch = git("symbolic-ref", "--short", "-q", "HEAD", cwd=repo, check=False).stdout.strip()
    if not branch:
        return fail("detached HEAD; check out your branch first")
    if branch in ("main", "master"):
        return fail(f"you are on {branch}; run this on the pull request's branch")
    if git("status", "--porcelain", "--untracked-files=no", cwd=repo).stdout.strip():
        return fail("uncommitted changes; commit or stash them first")

    if fetch:
        remote, _, ref = base.partition("/")
        print(f"==> fetching {base}")
        git("fetch", "--no-tags", remote, f"+refs/heads/{ref}:refs/remotes/{base}", cwd=repo, capture=False)

    print(f"==> merging {base} into {branch}")
    merged = git("merge", "--no-edit", base, cwd=repo, check=False)
    in_merge = merged.returncode != 0
    if in_merge:
        conflicted = git("diff", "--name-only", "--diff-filter=U", cwd=repo).stdout.split()
        if not conflicted:
            print(merged.stdout + merged.stderr, file=sys.stderr)
            return fail("git merge failed")
        generated, authored = split_conflicts(conflicted)
        for path in generated:
            git("checkout", "--theirs", "--", path, cwd=repo)
            git("add", "--", path, cwd=repo)
            print(f"    took {base}'s {path}")
        if authored:
            listing = "\n".join(f"    {p}" for p in authored)
            return fail(
                "these hand-authored files conflict and need a person:\n" + listing +
                "\nResolve them, `git add` them, then run `make data` and `git commit` to finish "
                "the merge (or `git merge --abort` to undo).")

    print("==> regenerating (update_data.py)")
    if subprocess.run(regenerate, cwd=repo).returncode != 0:
        state = "the merge is still in progress" if in_merge else "the merge is committed"
        return fail(f"update_data.py failed after the merge ({state}); fix the data, "
                    "run `make data` and commit")

    git("add", "-A", "--", *(p for p in ("data", BUNDLED_DIR) if (Path(repo) / p).exists()), cwd=repo)
    if in_merge:
        git("commit", "--no-edit", cwd=repo)
    elif git("status", "--porcelain", "--untracked-files=no", cwd=repo).stdout.strip():
        git("commit", "-m", f"data: regenerate after merging {base}", cwd=repo)
    print(f"done: {git('log', '--oneline', '-1', cwd=repo).stdout.strip()}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", default="origin/main", help="branch to merge in (default origin/main)")
    parser.add_argument("--no-fetch", action="store_true", help="do not fetch the base first")
    args = parser.parse_args(argv)
    return merge(ROOT, base=args.base, fetch=not args.no_fetch)


if __name__ == "__main__":
    sys.exit(main())
