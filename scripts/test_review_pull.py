import contextlib
import hashlib
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import review_pull as rp

REPO = Path(__file__).resolve().parent.parent


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class PullTests(unittest.TestCase):
    """Each test runs in a fresh local clone, based on the clone's HEAD (this branch)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.clone = Path(self.tmp.name) / "repo"
        subprocess.run(["git", "clone", "--quiet", "--local", "--no-hardlinks", str(REPO), str(self.clone)],
                       check=True)
        git(self.clone, "config", "user.email", "test@example.com")
        git(self.clone, "config", "user.name", "Test")
        self.cwd = os.getcwd()
        os.chdir(self.clone)

    def tearDown(self):
        os.chdir(self.cwd)
        self.tmp.cleanup()

    def sha(self, name):
        return hashlib.sha256((self.clone / "data" / f"{name}.json").read_bytes()).hexdigest()

    def batch_file(self, batch):
        path = Path(self.tmp.name) / "batch.json"
        path.write_text(json.dumps(batch, ensure_ascii=False), encoding="utf-8")
        return str(path)

    def run_pull(self, batch, *extra):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = rp.main(["--from-file", self.batch_file(batch), "--today", "2026-11-07", "--base", "HEAD",
                            *extra])
        return code, out.getvalue(), err.getvalue()

    def example_change(self, files):
        grammar = json.loads((self.clone / "data" / "grammar.json").read_text(encoding="utf-8"))
        point = grammar["grammar"][0]
        example = point["usages"][0]["examples"][0]
        item = {**example, "en": "A reviewed English line."}
        return {"files": files, "stamps": [], "suggestions": [{
            "id": 41, "action": "change", "dataset": "grammar", "kind": "example", "item_id": example["id"],
            "entry_id": point["id"], "parent_kind": None, "parent_id": None, "item_title": example["jp"],
            "item": item, "editable": ["jp", "en", "particle_blanks"], "furigana": None, "comment": "",
            "credit": {"role": "teacher", "name": None}, "decided_at": "2026-11-06T10:00:00Z"}]}

    def test_pull_writes_a_branch_with_the_change(self):
        base = git(self.clone, "rev-parse", "HEAD")
        code, out, err = self.run_pull(self.example_change({"grammar": self.sha("grammar")}))
        self.assertEqual(code, 0, err)
        self.assertEqual(git(self.clone, "branch", "--show-current"), "review-pull/2026-11-07")
        self.assertEqual(git(self.clone, "rev-list", "--count", f"{base}..HEAD"), "1")
        diff = git(self.clone, "diff", base, "HEAD", "--", "data/grammar.json")
        changed = [l for l in diff.splitlines() if l.startswith(("+ ", "- ", "+\t", "-\t"))
                   or (l[:1] in "+-" and not l.startswith(("+++", "---")))]
        self.assertEqual(len(changed), 2, diff)
        self.assertIn("A reviewed English line.", changed[1])
        self.assertIn("a teacher", out)
        self.assertEqual(git(self.clone, "status", "--porcelain"), "")
        check = subprocess.run(["python3", "scripts/update_data.py", "--check"], cwd=self.clone,
                               capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)

    def test_refuses_when_main_is_ahead_of_the_site(self):
        before = (self.clone / "data" / "grammar.json").read_bytes()
        branch = git(self.clone, "branch", "--show-current")
        code, _, err = self.run_pull(self.example_change({"grammar": "0" * 64}))
        self.assertEqual(code, 1)
        self.assertIn("The site's copy of grammar.json is older than main", err)
        self.assertEqual(git(self.clone, "branch", "--show-current"), branch)
        self.assertEqual(git(self.clone, "branch", "--list", "review-pull/*"), "")
        self.assertEqual((self.clone / "data" / "grammar.json").read_bytes(), before)

    def test_refuses_a_dirty_tree(self):
        (self.clone / "README.md").write_text("changed\n", encoding="utf-8")
        code, _, err = self.run_pull(self.example_change({"grammar": self.sha("grammar")}))
        self.assertEqual(code, 1)
        self.assertIn("commit or set aside your changes first", err)

    def test_empty_batch_does_nothing(self):
        code, out, _ = self.run_pull({"files": {}, "suggestions": [], "stamps": []})
        self.assertEqual(code, 0)
        self.assertIn("Nothing to export.", out)
        self.assertEqual(git(self.clone, "branch", "--list", "review-pull/*"), "")


if __name__ == "__main__":
    unittest.main()
