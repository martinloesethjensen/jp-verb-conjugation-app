import XCTest
@testable import VerbKit

final class CounterDecodingTests: XCTestCase {
    private let honJSON = """
    {"id": "hon", "counter": "本", "reading": "ほん", "meaning": "long, thin things",
     "jlpt": "N5", "sound": "h-b", "symbol": "pencil", "overrides": {},
     "readings": {"1": ["いっぽん"], "2": ["にほん"], "3": ["さんぼん"], "4": ["よんほん"], "5": ["ごほん"],
                  "6": ["ろっぽん"], "7": ["ななほん"], "8": ["はっぽん", "はちほん"], "9": ["きゅうほん"],
                  "10": ["じゅっぽん", "じっぽん"], "what": ["なんぼん"]},
     "changed": ["1", "3", "6", "8", "10", "what"],
     "things": [
       {"word": "ビール", "kana": "ビール", "meaning": "beer", "fit": "casual"},
       {"word": "傘", "kana": "かさ", "meaning": "umbrella", "fit": "primary", "symbol": "umbrella"},
       {"word": "うさぎ", "kana": "うさぎ", "meaning": "rabbit", "fit": "acceptable"},
       {"word": "鉛筆", "kana": "えんぴつ", "meaning": "pencil", "fit": "primary"}],
     "examples": [{"jp": "ビールを二本ください。", "en": "Two beers."}],
     "pitfalls": [{"heading": "Not さんほん", "explanation": "x"}],
     "related": ["hai"]}
    """

    private func decode(_ json: String) throws -> Counter {
        try JSONDecoder().decode(Counter.self, from: Data(json.utf8))
    }

    func testDecodesACounterIgnoringOverrides() throws {
        let hon = try decode(honJSON)
        XCTAssertEqual(hon.id, "hon")
        XCTAssertEqual(hon.counter, "本")
        XCTAssertEqual(hon.jlpt, .n5)
        XCTAssertEqual(hon.examples.first?.readings, [:])
        XCTAssertEqual(hon.related, ["hai"])
    }

    func testPitfallExamplesKeepTheirReadingOverrides() throws {
        let json = """
        {"id": "x", "counter": "日", "reading": "にち", "meaning": "days", "sound": "irregular", "symbol": "calendar",
         "readings": {"1": ["ついたち"]},
         "pitfalls": [{"heading": "h", "explanation": "e",
                       "examples": [{"jp": "一日に行きます。", "en": "x", "readings": {"一日": "ついたち"}},
                                    {"jp": "二日です。", "en": "y"}]}]}
        """
        let counter = try decode(json)
        let examples = try XCTUnwrap(counter.pitfalls.first?.examples)
        XCTAssertEqual(examples.map(\.readings), [["一日": "ついたち"], [:]])
    }

    func testDistractorsDecodeWhenPresentAndDefaultToNone() throws {
        let with = """
        {"id": "hon", "counter": "本", "reading": "ほん", "meaning": "m", "sound": "h-b", "symbol": "pencil",
         "readings": {"3": ["さんぼん"]},
         "distractors": {"3": ["さんほん", "さんぽん", "さっぽん"], "4": []}}
        """
        let counter = try decode(with)
        XCTAssertEqual(counter.distractors(for: .n(3)), ["さんほん", "さんぽん", "さっぽん"])
        XCTAssertEqual(counter.distractors(for: .n(4)), [])
        XCTAssertEqual(counter.distractors(for: .what), [])
        XCTAssertEqual(try decode(honJSON).distractors(for: .n(3)), [])
    }

    func testCountsObjectsDefaultsToTrueAndDecodesFalse() throws {
        XCTAssertTrue(try decode(honJSON).countsObjects)
        let json = """
        {"id": "nen", "counter": "年", "reading": "ねん", "meaning": "years", "sound": "plain", "symbol": "calendar",
         "readings": {"1": ["いちねん"]}, "countsObjects": false}
        """
        XCTAssertFalse(try decode(json).countsObjects)
    }

    func testOptionalArraysMayBeOmitted() throws {
        let minimal = """
        {"id": "x", "counter": "枚", "reading": "まい", "meaning": "flat", "sound": "plain",
         "symbol": "doc", "readings": {"1": ["いちまい"]}}
        """
        let counter = try decode(minimal)
        XCTAssertNil(counter.jlpt)
        XCTAssertEqual(counter.changed, [])
        XCTAssertEqual(counter.things, [])
        XCTAssertEqual(counter.examples, [])
        XCTAssertEqual(counter.pitfalls, [])
        XCTAssertEqual(counter.related, [])
    }

    func testReadingsKeepTheirOrderAndMarkChangedNumbers() throws {
        let hon = try decode(honJSON)
        XCTAssertEqual(hon.readings(for: .n(8)), ["はっぽん", "はちほん"])
        XCTAssertEqual(hon.readings(for: .what), ["なんぼん"])
        XCTAssertTrue(hon.isChanged(.n(3)))
        XCTAssertFalse(hon.isChanged(.n(2)))
        XCTAssertTrue(hon.isChanged(.what))
    }

    func testWrittenFormUsesKanjiNumerals() throws {
        let hon = try decode(honJSON)
        XCTAssertEqual(hon.written(.n(3)), "三本")
        XCTAssertEqual(hon.written(.n(10)), "十本")
        XCTAssertEqual(hon.written(.what), "何本")
    }

    func testThingsAreOrderedByFitThenFileOrder() throws {
        let hon = try decode(honJSON)
        XCTAssertEqual(hon.thingsByFit.map(\.word), ["傘", "鉛筆", "うさぎ", "ビール"])
    }

    func testCounterNumberKeysMatchTheDataPipeline() {
        XCTAssertEqual(CounterNumber.allCases.map(\.key),
                       ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "what"])
        XCTAssertEqual(CounterNumber.allCases.map(\.kanji),
                       ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "何"])
        XCTAssertEqual(CounterNumber(key: "what"), .what)
        XCTAssertEqual(CounterNumber(key: "7"), .n(7))
        XCTAssertNil(CounterNumber(key: "11"))
    }

    func testAnExampleReadingWinsOverTheDictionary() throws {
        let dictionary = FuriganaDictionary(readings: ["一日": "いちにち"])
        let date = CounterExample(jp: "一日に会いましょう。", en: "x", readings: ["一日": "ついたち"])
        let days = CounterExample(jp: "一日休みました。", en: "x")
        XCTAssertEqual(date.furigana(over: dictionary).units(for: "一日").first?.reading, "ついたち")
        XCTAssertEqual(days.furigana(over: dictionary).units(for: "一日").first?.reading, "いちにち")
    }

    func testMergingLeavesTheOriginalAlone() {
        let base = FuriganaDictionary(readings: ["日": "にち"])
        XCTAssertEqual(base.merging(["日": "ひ", "月": "つき"]).readings, ["日": "ひ", "月": "つき"])
        XCTAssertEqual(base.readings, ["日": "にち"])
        XCTAssertEqual(base.merging([:]), base)
    }

    func testGroupCountersFollowMemberOrderAndSkipMissingOnes() throws {
        let hon = try decode(honJSON)
        var hai = hon
        hai.id = "hai"
        let group = CounterGroup(id: "drinks", title: "Drinks", symbol: "cup.and.saucer", summary: "s", members: [
            CounterGroupMember(counter: "hai", note: "glasses"),
            CounterGroupMember(counter: "tsu", note: "casual"),
            CounterGroupMember(counter: "hon", note: nil),
        ])
        let found = group.counters(in: [hon, hai])
        XCTAssertEqual(found.map(\.counter.id), ["hai", "hon"])
        XCTAssertEqual(found.map(\.note), ["glasses", nil])
    }

    func testTheFileDecodesWithoutGroups() throws {
        let json = "{\"version\": \"1.0.0\", \"description\": \"d\", \"counters\": [\(honJSON)]}"
        let file = try JSONDecoder().decode(CountersDataFile.self, from: Data(json.utf8))
        XCTAssertEqual(file.counters.count, 1)
        XCTAssertEqual(file.groups, [])
    }

    func testCountersAreLeveled() throws {
        let hon = try decode(honJSON)
        let settings = LevelSettings(hidden: [.n5])
        XCTAssertEqual([hon].visible(in: settings), [])
    }
}
