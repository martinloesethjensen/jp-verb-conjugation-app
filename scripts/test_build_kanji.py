import gzip
import json
import tempfile
import unittest
from pathlib import Path

import build_kanji

KANJIVG = """<?xml version="1.0" encoding="UTF-8"?>
<kanjivg xmlns:kvg='http://kanjivg.tagaini.net'>
<kanji id="kvg:kanji_098df">
<g id="kvg:098df" kvg:element="食">
\t<g id="kvg:098df-g1">
\t\t<path id="kvg:098df-s1" d="M52.75,10.5c0.11,0.98-0.19,2.67-0.97,3.93"/>
\t\t<path id="kvg:098df-s2" d="M52.75,16.25c5.09,4.8,25.71,19.61,33.7,24.9"/>
\t</g>
\t<path id="kvg:098df-s3" d="M52.25,29.25c1,1,1.5,2.25,1.5,3.5"/>
</g>
</kanji>
<kanji id="kvg:kanji_098df-Kaisho">
<g id="kvg:098df-Kaisho"><path id="kvg:098df-Kaisho-s1" d="M1,1c1,1,1,1,1,1"/></g>
</kanji>
<kanji id="kvg:kanji_04eba">
<g id="kvg:04eba"><path id="kvg:04eba-s1" d="M54,10c0,0,0,1,0,2"/><path id="kvg:04eba-s2" d="M55,40c1,1,2,2,3,3"/></g>
</kanji>
<kanji id="kvg:kanji_08d70">
<g id="kvg:08d70"><path id="kvg:08d70-s1" d="M10,10c1,1,1,1,1,1"/></g>
</kanji>
<kanji id="kvg:kanji_051dc">
<g id="kvg:051dc"><path id="kvg:051dc-s1" d="M20,20c1,1,1,1,1,1"/></g>
</kanji>
</kanjivg>
"""

KANJIDIC = """<?xml version="1.0" encoding="UTF-8"?>
<kanjidic2>
<header><file_version>4</file_version><database_version>2026-311</database_version><date_of_creation>2026-11-07</date_of_creation></header>
<character><literal>食</literal>
<misc><grade>2</grade><stroke_count>9</stroke_count><jlpt>4</jlpt></misc>
<reading_meaning><rmgroup>
<reading r_type="pinyin">shi2</reading>
<reading r_type="ja_on">ショク</reading><reading r_type="ja_on">ジキ</reading>
<reading r_type="ja_kun">く.う</reading><reading r_type="ja_kun">く.らう</reading><reading r_type="ja_kun">た.べる</reading>
<meaning>eat</meaning><meaning>food</meaning><meaning m_lang="fr">manger</meaning><meaning>meal</meaning><meaning>fourth</meaning>
</rmgroup></reading_meaning>
</character>
<character><literal>人</literal>
<misc><grade>1</grade><stroke_count>2</stroke_count></misc>
<reading_meaning><rmgroup><reading r_type="ja_on">ジン</reading><reading r_type="ja_kun">ひと</reading><reading r_type="ja_kun">パーソン</reading><meaning>person</meaning></rmgroup></reading_meaning>
</character>
<character><literal>走</literal>
<misc><grade>2</grade><stroke_count>7</stroke_count></misc>
<reading_meaning><rmgroup><reading r_type="ja_kun">はし.る</reading><meaning>run</meaning></rmgroup></reading_meaning>
</character>
<character><literal>鰯</literal>
<misc><grade>9</grade><stroke_count>21</stroke_count></misc>
<reading_meaning><rmgroup><meaning>rare</meaning></rmgroup></reading_meaning>
</character>
<character><literal>凜</literal>
<misc><grade>9</grade><stroke_count>15</stroke_count></misc>
<reading_meaning><rmgroup><reading r_type="ja_on">リン</reading><meaning>cold</meaning></rmgroup></reading_meaning>
</character>
</kanjidic2>
"""


class BuildKanjiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.kanjivg = self.dir / "kanjivg-20260714.xml.gz"
        self.kanjivg.write_bytes(gzip.compress(KANJIVG.encode("utf-8")))
        self.kanjidic = self.dir / "kanjidic2.xml"
        self.kanjidic.write_text(KANJIDIC, encoding="utf-8")
        self.data = self.dir / "data"
        self.data.mkdir()
        # App data uses 人, 々, 食 and the grade-9 凜; 走 is jōyō but unused; 鰯 is grade 9 and unused.
        (self.data / "verbs.json").write_text(json.dumps({"verbs": [{"jp": "人々が食べる"}]}, ensure_ascii=False),
                                              encoding="utf-8")
        (self.data / "words.json").write_text(json.dumps({"words": ["凜"]}, ensure_ascii=False), encoding="utf-8")

    def tearDown(self):
        self.tmp.cleanup()

    def test_reads_only_base_kanji_ids(self):
        strokes = build_kanji.read_kanjivg(self.kanjivg)
        self.assertEqual(strokes["食"], [
            "M52.75,10.5c0.11,0.98-0.19,2.67-0.97,3.93",
            "M52.75,16.25c5.09,4.8,25.71,19.61,33.7,24.9",
            "M52.25,29.25c1,1,1.5,2.25,1.5,3.5",
        ])
        self.assertEqual(set(strokes), {"食", "人", "走", "凜"})

    def test_kanjidic_entry_fields(self):
        created, entries = build_kanji.read_kanjidic(self.kanjidic)
        self.assertEqual(created, "2026-11-07")
        self.assertEqual(entries["食"], {
            "grade": 2, "on": ["ショク", "ジキ"], "kun": ["く.う", "く.らう", "た.べる"],
            "meanings": ["eat", "food", "meal"],
        })
        self.assertNotIn("grade", entries["凜"])

    def test_selection_is_joyo_plus_app_kanji_without_repeat_mark(self):
        doc = build_kanji.build(self.kanjivg, self.kanjidic, self.data)
        self.assertEqual(set(doc["kanji"]), {"人", "食", "走", "凜"})
        self.assertEqual(doc["kanji"]["人"], {"strokes": ["M54,10c0,0,0,1,0,2", "M55,40c1,1,2,2,3,3"], "grade": 1,
                                              "on": ["ジン"], "kun": ["ひと"], "meanings": ["person"]})
        self.assertNotIn("grade", doc["kanji"]["凜"])

    def test_katakana_loan_readings_are_not_kun(self):
        _, entries = build_kanji.read_kanjidic(self.kanjidic)
        self.assertEqual(entries["人"]["kun"], ["ひと"])

    def test_missing_source_entry_fails_naming_kanji(self):
        self.kanjivg.write_bytes(gzip.compress(KANJIVG.replace("kvg:kanji_08d70", "kvg:kanji_08d70-Kaisho").encode()))
        with self.assertRaises(SystemExit) as raised:
            build_kanji.build(self.kanjivg, self.kanjidic, self.data)
        self.assertIn("走", str(raised.exception))

    def test_app_kanji_ignores_the_kanji_file_itself(self):
        (self.data / "kanji.json").write_text(json.dumps({"kanji": {"鬱": {}}}, ensure_ascii=False), encoding="utf-8")
        self.assertNotIn("鬱", build_kanji.app_kanji(self.data))
        self.assertEqual(build_kanji.app_kanji(self.data), {"人", "食", "凜"})

    def test_output_is_code_point_ordered_and_deterministic(self):
        first = build_kanji.build(self.kanjivg, self.kanjidic, self.data)
        second = build_kanji.build(self.kanjivg, self.kanjidic, self.data)
        self.assertEqual(build_kanji.dumps(first), build_kanji.dumps(second))
        self.assertEqual(list(first["kanji"]), sorted(first["kanji"]))
        self.assertEqual(first["schema"], 1)
        self.assertEqual(first["sources"], {"kanjivg": "20260714", "kanjidic2": "2026-11-07"})
        self.assertIn("CC BY-SA 3.0", first["license"])
        self.assertIn("CC BY-SA 4.0", first["license"])


if __name__ == "__main__":
    unittest.main()
