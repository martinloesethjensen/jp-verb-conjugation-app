import XCTest
@testable import VerbKit

/// Tests against the real published `data/furigana.json`. They read the files
/// straight from the repo checkout, so they fail when someone edits the data
/// and forgets `scripts/update_data.py`, or adds kanji with no reading.
final class RealFuriganaDataTests: XCTestCase {
    private func dataURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent(name)
    }

    private func loadDictionary() throws -> FuriganaDictionary {
        let data = try Data(contentsOf: dataURL("furigana.json"))
        return FuriganaDictionary(file: try JSONDecoder().decode(FuriganaDataFile.self, from: data))
    }

    private func loadVerbs() throws -> [Verb] {
        let data = try Data(contentsOf: dataURL("verbs.json"))
        return try JSONDecoder().decode(VerbDataFile.self, from: data).verbs
    }

    /// Every string value in a JSON document, with its location.
    private func strings(in json: Any, path: String = "") -> [(path: String, text: String)] {
        if let object = json as? [String: Any] {
            return object.flatMap { strings(in: $0.value, path: path.isEmpty ? $0.key : "\(path)/\($0.key)") }
        }
        if let array = json as? [Any] {
            return array.enumerated().flatMap { strings(in: $0.element, path: "\(path)[\($0.offset)]") }
        }
        if let text = json as? String { return [(path, text)] }
        return []
    }

    private func allDataStrings() throws -> [(path: String, text: String)] {
        try ["verbs.json", "grammar.json"].flatMap { name -> [(path: String, text: String)] in
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dataURL(name)))
            return strings(in: json, path: name)
        }
    }

    func testTheFileDecodes() throws {
        let file = try JSONDecoder().decode(FuriganaDataFile.self, from: Data(contentsOf: dataURL("furigana.json")))
        XCTAssertFalse(file.readings.isEmpty)
    }

    /// The same guard `scripts/update_data.py` enforces, checked from the app's own matcher.
    func testEveryKanjiInTheDataHasAReading() throws {
        let dictionary = try loadDictionary()
        let strings = try allDataStrings()
        XCTAssertGreaterThan(strings.count, 500, "the walk should reach every string in both files")
        for (path, text) in strings {
            XCTAssertFalse(dictionary.hasUnreadKanji(in: text), "\(path) has a kanji with no reading: \(text)")
        }
    }

    func testEachVerbsKanjiSpellsItsKanaForm() throws {
        let dictionary = try loadDictionary()
        let verbsWithKanji = try loadVerbs().filter { $0.kanji != nil }
        XCTAssertEqual(verbsWithKanji.count, 23)
        for verb in verbsWithKanji {
            let spelled = dictionary.units(for: verb.kanji!).map { $0.reading ?? $0.text }.joined()
            XCTAssertEqual(spelled, verb.dict, "\(verb.kanji!) should read \(verb.dict)")
        }
    }

    func testEveryReadingIsHiraganaAndEveryKeyStartsWithAKanji() throws {
        let file = try JSONDecoder().decode(FuriganaDataFile.self, from: Data(contentsOf: dataURL("furigana.json")))
        for (key, reading) in file.readings {
            XCTAssertTrue(FuriganaDictionary.isKanji(key.first!), "key \(key) must start with a kanji")
            XCTAssertFalse(reading.isEmpty, key)
            for scalar in reading.unicodeScalars {
                XCTAssertTrue(
                    (0x3041...0x3096).contains(scalar.value) || scalar.value == 0x30FC,
                    "reading \(reading) of \(key) must be hiragana"
                )
            }
        }
    }

    /// Hand-verified readings where the answer depends on context.
    func testContextDependentReadings() throws {
        let dictionary = try loadDictionary()
        func spelled(_ text: String) -> String {
            dictionary.units(for: text).map { $0.reading ?? $0.text }.joined()
        }
        XCTAssertEqual(spelled("来る"), "くる")
        XCTAssertEqual(spelled("来られる"), "こられる")
        XCTAssertEqual(spelled("来れる"), "これる")
        XCTAssertEqual(spelled("来た"), "きた")
        XCTAssertEqual(spelled("来ます"), "きます")
        XCTAssertEqual(spelled("遅れた"), "おくれた")
        XCTAssertEqual(spelled("遅い"), "おそい")
        XCTAssertEqual(spelled("今日は"), "きょうは")
        XCTAssertEqual(spelled("明日なら"), "あしたなら")
        XCTAssertEqual(spelled("何時"), "なんじ")
        XCTAssertEqual(spelled("何もしない"), "なにもしない")
        XCTAssertEqual(spelled("毎日学校に行く"), "まいにちがっこうにいく")
        XCTAssertEqual(spelled("昨日買った"), "きのうかった")
        XCTAssertEqual(spelled("十一時に"), "じゅういちじに")
        XCTAssertEqual(spelled("引っ越す"), "ひっこす")
        XCTAssertEqual(spelled("可能形"), "かのうけい")
    }

    /// Pinned readings for the keys whose answer depends on what follows the kanji
    /// (the coverage check only fails on a missing reading, never on a wrong one).
    func testReadingsThatDependOnWhatFollows() throws {
        let dictionary = try loadDictionary()
        func spelled(_ text: String) -> String {
            dictionary.units(for: text).map { $0.reading ?? $0.text }.joined()
        }
        XCTAssertEqual(spelled("家に着いた"), "いえについた")        // 着: つ
        XCTAssertEqual(spelled("服を着ています"), "ふくをきています")  // 着: き
        XCTAssertEqual(spelled("着てみて"), "きてみて")
        XCTAssertEqual(spelled("着なさい"), "きなさい")
        XCTAssertEqual(spelled("落ち着かない"), "おちつかない")
        XCTAssertEqual(spelled("駅に出る"), "えきにでる")            // 出: で
        XCTAssertEqual(spelled("声を出す"), "こえをだす")            // 出: だ
        XCTAssertEqual(spelled("話ですね"), "はなしですね")          // 話: はなし (the noun)
        XCTAssertEqual(spelled("話し方"), "はなしかた")              // 話: はな
        XCTAssertEqual(spelled("来ながら"), "きながら")              // 来: き, not こ
        XCTAssertEqual(spelled("来ない"), "こない")
        XCTAssertEqual(spelled("友達が来ています"), "ともだちがきています")
        XCTAssertEqual(spelled("行っています"), "いっています")
        XCTAssertEqual(spelled("窓を開けて"), "まどをあけて")
        XCTAssertEqual(spelled("ドアが開いている"), "ドアがあいている")
        XCTAssertEqual(spelled("机の上に"), "つくえのうえに")        // 上: うえ
        XCTAssertEqual(spelled("上手"), "じょうず")
        XCTAssertEqual(spelled("お金"), "おかね")
        XCTAssertEqual(spelled("ご飯"), "ごはん")
        XCTAssertEqual(spelled("歩きやすい"), "あるきやすい")
        XCTAssertEqual(spelled("使いにくい"), "つかいにくい")
        XCTAssertEqual(spelled("少ない"), "すくない")                // 少: すく (少し stays すこし)
        XCTAssertEqual(spelled("少し"), "すこし")
        XCTAssertEqual(spelled("私が料理をしている間、彼は"), "わたしがりょうりをしているあいだ、かれは")
        XCTAssertEqual(spelled("間違える"), "まちがえる")
    }

    func testTheManifestFuriganaHashMatchesTheFile() throws {
        let manifestData = try Data(contentsOf: dataURL("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let block = try XCTUnwrap(manifest["furigana"] as? [String: String], "manifest.json has no furigana block")
        XCTAssertEqual(block["sha256"], sha256Hex(of: try Data(contentsOf: dataURL("furigana.json"))))
    }
}
