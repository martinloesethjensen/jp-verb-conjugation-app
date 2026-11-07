#!/usr/bin/env python3
"""Pull accepted review work from the review site into a fresh data branch (owner only).

    make review-pull

1. Refuses when the working tree has uncommitted changes.
2. Reads the export batch from the site with the Access service token in your Keychain (service
   kotobatable-review-export, accounts client-id and client-secret). Read-only: the token can't change
   anything on the site.
3. Starts review-pull/<date> from origin/main, and checks that every file the batch touches is the one the
   site loaded (otherwise: load the published data on the site, then pull again).
4. Applies the batch (scripts/review_export.py), keeping grammar.json's and furigana.json's hand formatting,
   runs update_data.py, and commits everything it wrote.
5. Prints the PR summary. Push the branch and open a PR yourself. It's an ordinary data PR: not signed;
   `make data-release` signs merged batches. After it merges, mark the batch exported at /admin/export.
"""
import argparse
import datetime
import hashlib
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

import json_preserve
import review_export as rx
import update_data as ud

EXPORT_URL = "https://review.martinloeseth.dev/api/export"
KEYCHAIN_SERVICE = "kotobatable-review-export"
# Written with their update_data dump function; the others keep their hand formatting.
DUMPED = {"verbs": ud.dump_verbs, "words": ud.dump_words, "counters": ud.dump_counters}
PRESERVED = ("grammar", "furigana")


class Refused(Exception):
    pass


def git(repo, *args, check=True):
    result = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise Refused(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def keychain(account):
    result = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"],
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise Refused(f"no Keychain item {KEYCHAIN_SERVICE} / {account}: see review/README.md, Exporting")
    return result.stdout.strip()


def fetch_from_site():
    request = urllib.request.Request(EXPORT_URL, headers={
        "CF-Access-Client-Id": keychain("client-id"),
        "CF-Access-Client-Secret": keychain("client-secret"),
        "User-Agent": "kotobatable-review-pull",
    })
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as error:  # urllib raises several kinds; the message is what the owner needs
        raise Refused(f"couldn't read {EXPORT_URL}: {error}")


def touched_files(batch):
    names = {s["dataset"] for s in batch["suggestions"] if s["action"] != "note"}
    names |= {t["dataset"] for t in batch["stamps"]}
    if any(s.get("furigana") for s in batch["suggestions"]):
        names.add("furigana")
    return sorted(names)


def free_branch(repo, today):
    name, n = f"review-pull/{today}", 1
    while git(repo, "rev-parse", "--verify", "--quiet", f"refs/heads/{name}", check=False):
        n += 1
        name = f"review-pull/{today}-{n}"
    return name


def write_data(repo, batch, today):
    """Applies the batch to data/ and returns the report."""
    data = repo / "data"
    texts = {name: (data / f"{name}.json").read_text(encoding="utf-8") for name in (*DUMPED, *PRESERVED)}
    docs = {name: json.loads(text) for name, text in texts.items()}
    report = rx.apply_batch(batch, docs, today)
    for name in touched_files(batch):
        if name in DUMPED:
            text = DUMPED[name](docs[name])
        else:
            text = json_preserve.rewrite(texts[name], docs[name])
        if text != texts[name]:
            (data / f"{name}.json").write_text(text, encoding="utf-8")
    return report


def pull(repo, batch, today, base, commit):
    if git(repo, "status", "--porcelain"):
        raise Refused("commit or set aside your changes first")
    if not batch["suggestions"] and not batch["stamps"]:
        print("Nothing to export.")
        return None
    if base.startswith("origin/"):
        git(repo, "fetch", "--quiet", "origin")
    # On a detached HEAD (as in CI's pull request checkout) the way back is a commit, which
    # `git switch` only accepts with --detach.
    current = git(repo, "branch", "--show-current")
    start = [current] if current else ["--detach", git(repo, "rev-parse", "HEAD")]
    branch = free_branch(repo, today)
    git(repo, "switch", "--quiet", "-c", branch, base)
    for name in touched_files(batch):
        sha = hashlib.sha256((repo / "data" / f"{name}.json").read_bytes()).hexdigest()
        if sha != batch["files"].get(name):
            git(repo, "switch", "--quiet", *start)
            git(repo, "branch", "--quiet", "-D", branch)
            raise Refused(
                f"The site's copy of {name}.json is older than main: load the published data on the site, then "
                "pull again. If main has unreleased data changes, run make data-release first.")
    report = write_data(repo, batch, today)
    result = subprocess.run([sys.executable, str(repo / "scripts" / "update_data.py")], cwd=repo,
                            capture_output=True, text=True)
    if result.returncode != 0:
        ids = ", ".join(str(s["id"]) for s in batch["suggestions"])
        print(result.stdout + result.stderr, file=sys.stderr)
        print(f"update_data.py failed on {branch} (left as it is). The batch had suggestions {ids}; fix the "
              "data or decline the culprit on the site.", file=sys.stderr)
        return 2
    if commit:
        git(repo, "add", "-A")
        git(repo, "commit", "--quiet", "-m",
            f"Review pull {today}: {len(report.suggestion_ids)} suggestions, {len(report.stamp_ids)} stamps")
    return report, branch


def main(argv=None, fetch=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--from-file", help="read the batch from this file instead of the site")
    parser.add_argument("--summary", help="also write the PR summary to this file")
    parser.add_argument("--today", default=datetime.date.today().isoformat())
    parser.add_argument("--base", default="origin/main", help="what the branch starts from (default origin/main)")
    parser.add_argument("--no-commit", action="store_true", help="leave the changes uncommitted")
    args = parser.parse_args(argv)
    try:
        repo = Path(git(Path.cwd(), "rev-parse", "--show-toplevel"))
        if args.from_file:
            batch = json.loads(Path(args.from_file).read_text(encoding="utf-8"))
        else:
            batch = (fetch or fetch_from_site)()
        outcome = pull(repo, batch, args.today, args.base, not args.no_commit)
    except Refused as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if outcome is None:
        return 0
    if outcome == 2:
        return 2
    report, branch = outcome
    summary = rx.summary_markdown(report)
    print(summary)
    if args.summary:
        Path(args.summary).write_text(summary, encoding="utf-8")
    print(f"Next: git push -u origin {branch}, open a PR with the summary above, and after it merges mark "
          "the batch exported at /admin/export.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
