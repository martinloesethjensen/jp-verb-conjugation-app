import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import data_merge  # noqa: E402

R = data_merge.BUNDLED_DIR


class ClassifyTests(unittest.TestCase):
    def test_generated_files(self):
        for path in ["data/manifest.json", "data/manifest.sig", "data/forms.json",
                     R + "verbs.json", R + "verbs.manifest.json", R + "forms.manifest.json",
                     R + "counters.json"]:
            self.assertTrue(data_merge.is_generated(path), path)

    def test_hand_authored_files(self):
        for path in ["data/verbs.json", "data/grammar.json", "data/furigana.json",
                     R + "dialects.json", "scripts/update_data.py", R + "nested/verbs.json"]:
            self.assertFalse(data_merge.is_generated(path), path)

    def test_split(self):
        generated, authored = data_merge.split_conflicts(
            ["data/verbs.json", "data/manifest.json", R + "verbs.json"])
        self.assertEqual(generated, [R + "verbs.json", "data/manifest.json"])
        self.assertEqual(authored, ["data/verbs.json"])


def run(cwd, *args):
    return subprocess.run(args, cwd=cwd, check=True, text=True, capture_output=True).stdout


# A stand-in for update_data.py: the "manifest" is the concatenation of the two source files.
REGENERATE = [sys.executable, "-c",
              "from pathlib import Path; d = Path('data');"
              "(d / 'manifest.json').write_text((d / 'verbs.json').read_text() + (d / 'grammar.json').read_text())"]


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        run(self.repo, "git", "init", "-q", "-b", "main")
        run(self.repo, "git", "config", "user.email", "t@example.com")
        run(self.repo, "git", "config", "user.name", "t")
        (self.repo / "data").mkdir()
        self.write(verbs="v0\n", grammar="g0\n")
        self.commit("base")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, verbs=None, grammar=None):
        d = self.repo / "data"
        if verbs is not None:
            (d / "verbs.json").write_text(verbs)
        if grammar is not None:
            (d / "grammar.json").write_text(grammar)
        subprocess.run(REGENERATE, cwd=self.repo, check=True)

    def commit(self, message):
        run(self.repo, "git", "add", "-A")
        run(self.repo, "git", "commit", "-q", "-m", message)

    def merge(self):
        return data_merge.merge(self.repo, base="main", fetch=False, regenerate=REGENERATE)

    def manifest(self):
        return (self.repo / "data/manifest.json").read_text()

    def test_conflicting_manifest_is_regenerated(self):
        run(self.repo, "git", "switch", "-q", "-c", "feature")
        self.write(verbs="v0\nv-feature\n")
        self.commit("feature")
        run(self.repo, "git", "switch", "-q", "main")
        self.write(grammar="g0\ng-main\n")
        self.commit("main")
        run(self.repo, "git", "switch", "-q", "feature")

        self.assertEqual(self.merge(), 0)
        self.assertEqual(self.manifest(), "v0\nv-feature\ng0\ng-main\n")
        self.assertEqual(run(self.repo, "git", "status", "--porcelain"), "")
        parents = run(self.repo, "git", "log", "-1", "--format=%P").split()
        self.assertEqual(len(parents), 2, "finishes the merge commit")

    def test_hand_authored_conflict_stops(self):
        run(self.repo, "git", "switch", "-q", "-c", "feature")
        self.write(verbs="v-feature\n")
        self.commit("feature")
        run(self.repo, "git", "switch", "-q", "main")
        self.write(verbs="v-main\n")
        self.commit("main")
        run(self.repo, "git", "switch", "-q", "feature")

        self.assertEqual(self.merge(), 1)
        conflicted = run(self.repo, "git", "diff", "--name-only", "--diff-filter=U").split()
        self.assertEqual(conflicted, ["data/verbs.json"])

    def test_refuses_main_and_dirty_tree(self):
        self.assertEqual(self.merge(), 1)
        run(self.repo, "git", "switch", "-q", "-c", "feature")
        (self.repo / "data/verbs.json").write_text("dirty\n")
        self.assertEqual(self.merge(), 1)


if __name__ == "__main__":
    unittest.main()
