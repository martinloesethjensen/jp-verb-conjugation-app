import tempfile
import unittest
from pathlib import Path

import generate_audio as ga


class SpokenTests(unittest.TestCase):
    def test_matches_swift_speech_text(self):
        self.assertEqual(ga.spoken("  たべる \n"), "たべる")
        self.assertEqual(ga.spoken("たべる / のむ"), "たべる、のむ")
        self.assertEqual(ga.spoken("~てしまう"), "てしまう")
        self.assertEqual(ga.spoken("頭が痛いんです。"), "頭が痛いんです。")
        self.assertIsNone(ga.spoken(" ~ / "))
        self.assertIsNone(ga.spoken("   "))

    def test_clip_name_matches_swift_vectors(self):
        # The same vectors as SpeechTextTests.testClipNameMatchesGeneratorScript.
        self.assertEqual(ga.clip_name("たべます"), "1a593dff4eea79de")
        self.assertEqual(ga.clip_name("頭が痛いんです。"), "da00c4fac207a253")


class CollectTests(unittest.TestCase):
    verbs = {"verbs": [
        {"dict": "みせる", "kanji": "見せる", "forms": {"masu_pos": "みせます", "te": "みせて", "x": None},
         "examples": [{"jp": "しゃしんをみせます。", "en": "x"}]},
        {"dict": "ある", "kanji": None, "forms": {"masu_pos": "あります", "te": "みせて"}},
    ]}
    grammar = {"grammar": [{
        "usages": [{"examples": [{"jp": "すみません。", "en": "x"}]}],
        "pitfalls": [{"examples": [{"jp": "すみません。", "en": "x"}, {"jp": "~/", "en": "x"}]}],
    }]}

    def test_collects_cleans_and_deduplicates(self):
        texts = ga.collect_texts(self.verbs, self.grammar)
        self.assertEqual(texts, ["見せる", "みせます", "みせて", "しゃしんをみせます。", "ある", "あります", "すみません。"])

    def test_dictionary_form_falls_back_to_kana(self):
        self.assertIn("ある", ga.collect_texts(self.verbs, self.grammar))

    def test_real_data_is_collectable(self):
        texts = ga.load_texts()
        self.assertTrue(texts)
        self.assertEqual(len(texts), len(set(texts)))
        self.assertEqual(len({ga.clip_name(t) for t in texts}), len(texts), "clip names must not collide")


class FilesTests(unittest.TestCase):
    def test_missing_and_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            (out / f"{ga.clip_name('あ')}.mp3").write_bytes(b"x")
            (out / "old.mp3").write_bytes(b"x")
            self.assertEqual(ga.missing_clips(["あ", "い"], out), ["い"])
            self.assertEqual([p.name for p in ga.stale_clips(["あ", "い"], out)], ["old.mp3"])

    def test_check_flags_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(ga.main(["--check", "--out", tmp]), 1)

    def test_dry_run_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(ga.main(["--dry-run", "--out", tmp]), 0)
            self.assertEqual(list(Path(tmp).iterdir()), [])


class RetryTests(unittest.TestCase):
    def test_retryable(self):
        import urllib.error
        self.assertTrue(ga.is_retryable(urllib.error.HTTPError("u", 429, "m", {}, None)))
        self.assertFalse(ga.is_retryable(urllib.error.HTTPError("u", 403, "m", {}, None)))
        self.assertFalse(ga.is_retryable(ValueError("bad")))


if __name__ == "__main__":
    unittest.main()
