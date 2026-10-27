import XCTest
@testable import VerbKit

final class CounterSearchTests: XCTestCase {
    private func counter(
        _ id: String, _ written: String, _ reading: String, _ meaning: String, readings: [String],
        things: [CountedThing] = [], changed: [String] = []
    ) -> Counter {
        Counter(
            id: id, counter: written, reading: reading, meaning: meaning, jlpt: .n5, sound: "x", symbol: "circle",
            readings: Dictionary(uniqueKeysWithValues: zip(CounterNumber.allCases.map(\.key), readings.map { [$0] })),
            changed: changed, things: things
        )
    }

    private func plain(_ suffix: String) -> [String] {
        ["いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう", "じゅう", "なん"].map { $0 + suffix }
    }

    private lazy var hon: Counter = {
        var hon = counter("hon", "本", "ほん", "long, thin things",
                          readings: ["いっぽん", "にほん", "さんぼん", "よんほん", "ごほん", "ろっぽん", "ななほん",
                                     "はっぽん", "きゅうほん", "じゅっぽん", "なんぼん"],
                          things: [CountedThing(word: "傘", kana: "かさ", meaning: "umbrella", fit: .primary),
                                   CountedThing(word: "ビール", kana: "ビール", meaning: "beer", fit: .casual)])
        hon.readings["8"] = ["はっぽん", "はちほん"]
        return hon
    }()

    private lazy var hai = counter("hai", "杯", "はい", "cups, glasses and bowls",
                                   readings: ["いっぱい", "にはい", "さんばい", "よんはい", "ごはい", "ろっぱい", "ななはい",
                                              "はっぱい", "きゅうはい", "じゅっぱい", "なんばい"])
    private lazy var hiki = counter("hiki", "匹", "ひき", "small animals", readings: plain("ひき"),
                                    things: [CountedThing(word: "うさぎ", kana: "うさぎ", meaning: "rabbit", fit: .acceptable)])
    private lazy var wa = counter("wa", "羽", "わ", "birds and rabbits", readings: plain("わ"),
                                  things: [CountedThing(word: "うさぎ", kana: "うさぎ", meaning: "rabbit", fit: .primary)])
    private lazy var nin = counter("nin", "人", "にん", "people",
                                   readings: ["ひとり", "ふたり", "さんにん", "よにん", "ごにん", "ろくにん", "ななにん",
                                              "はちにん", "きゅうにん", "じゅうにん", "なんにん"])
    private lazy var tsu = counter("tsu", "つ", "つ", "general counter",
                                   readings: ["ひとつ", "ふたつ", "みっつ", "よっつ", "いつつ", "むっつ", "ななつ",
                                              "やっつ", "ここのつ", "とお", "いくつ"])

    private lazy var all = [hon, hai, hiki, wa, nin, tsu]

    private let drinks = CounterGroup(
        id: "drinks", title: "Drinks", symbol: "cup.and.saucer",
        summary: "Cups, bottles, or just one-two when ordering.",
        members: [CounterGroupMember(counter: "hai"), CounterGroupMember(counter: "hon"), CounterGroupMember(counter: "tsu")])
    private let long = CounterGroup(
        id: "long", title: "Long things", symbol: "pencil", summary: "Pencils and umbrellas.",
        members: [CounterGroupMember(counter: "hon")])

    private func search(_ query: String) -> CounterSearchResults {
        searchCounters(all, groups: [drinks, long], query: query)
    }

    func testAnEmptyQueryGivesEmptyResults() {
        XCTAssertTrue(search("").isEmpty)
        XCTAssertTrue(search("   ").isEmpty)
    }

    func testEveryWayToTypeSanbonFindsHonAtThree() {
        for query in ["3本", "３本", "三本", "さんぼん", "sanbon", "さんぼ"] {
            let forms = search(query).forms
            XCTAssertEqual(forms.map(\.counter.id), ["hon"], query)
            XCTAssertEqual(forms.map(\.number), [.n(3)], query)
        }
    }

    func testAnAcceptedSecondReadingFindsItsForm() {
        let forms = search("はちほん").forms
        XCTAssertEqual(forms.map(\.number), [.n(8)])
        XCTAssertEqual(forms.first?.reading, "はちほん")
    }

    func testAWrittenFormReportsThePreferredReading() {
        XCTAssertEqual(search("三本").forms.first?.reading, "さんぼん")
    }

    func testAnEnglishQueryFindsGroupsByTitleAndSummary() {
        XCTAssertEqual(search("drinks").groups.map(\.id), ["drinks"])
        XCTAssertEqual(search("glasses").groups.map(\.id), ["drinks"])
    }

    func testTheCounterItselfFindsTheCounterButNoForms() {
        for query in ["hon", "ほん", "本"] {
            let results = search(query)
            XCTAssertEqual(results.counters.map(\.id), ["hon"], query)
            XCTAssertTrue(results.forms.isEmpty, query)
        }
    }

    func testAThingFindsItsCounters() {
        for query in ["umbrella", "kasa", "傘"] {
            let things = search(query).things
            XCTAssertEqual(things.map(\.thing.word), ["傘"], query)
            XCTAssertEqual(things.first?.counters.map(\.id), ["hon"], query)
        }
    }

    func testAKatakanaThingIsFoundByItsRomaji() {
        XCTAssertEqual(search("beer").things.map(\.thing.word), ["ビール"])
    }

    func testOneThingRowListsEveryCounterPrimaryFirst() {
        let things = search("rabbit").things
        XCTAssertEqual(things.count, 1)
        XCTAssertEqual(things.first?.counters.map(\.id), ["wa", "hiki"])
        XCTAssertEqual(things.first?.thing.fit, .primary)
    }

    func testABareNumberMatchesNoForms() {
        XCTAssertTrue(search("さん").forms.isEmpty)
        XCTAssertTrue(search("san").forms.isEmpty)
        XCTAssertTrue(search("いっ").forms.isEmpty)
    }

    func testAGroupAppearsWhenAMemberCounterMatches() {
        XCTAssertEqual(search("本").groups.map(\.id), ["drinks", "long"])
    }

    func testFormRowsAreCapped() {
        let many = (0..<30).map { counter("c\($0)", "本", "ほん", "m", readings: plain("ほん")) }
        let results = searchCounters(many, groups: [], query: "にほ")
        XCTAssertEqual(results.forms.count, 20)
    }

    func testKanjiNumerals() {
        XCTAssertEqual(kanjiNumerals(in: "1本"), "一本")
        XCTAssertEqual(kanjiNumerals(in: "10本"), "十本")
        XCTAssertEqual(kanjiNumerals(in: "３本"), "三本")
        XCTAssertEqual(kanjiNumerals(in: "11本"), "十一本")
        XCTAssertEqual(kanjiNumerals(in: "何本"), "何本")
        XCTAssertEqual(kanjiNumerals(in: "0本"), "0本")
        XCTAssertEqual(kanjiNumerals(in: "15分"), "十五分")
        XCTAssertEqual(kanjiNumerals(in: "100円"), "百円")
        XCTAssertEqual(kanjiNumerals(in: "3000円"), "三千円")
        XCTAssertEqual(kanjiNumerals(in: "10001本"), "10001本")
    }

    private lazy var fun: Counter = {
        var fun = counter("fun", "分", "ふん", "minutes", readings: plain("ふん"))
        fun.extent = 59
        fun.extra = [100]
        for value in 11...59 { fun.readings[String(value)] = ["じゅう" + String(value)] }
        fun.readings["15"] = ["じゅうごふん"]
        fun.readings["35"] = ["さんじゅうごふん"]
        fun.readings["100"] = ["ひゃくふん"]
        return fun
    }()

    private lazy var yen: Counter = {
        var yen = counter("en", "円", "えん", "yen", readings: plain("えん"))
        yen.extent = 99
        yen.extra = [100, 3000]
        yen.readings["3000"] = ["さんぜんえん"]
        yen.readings["100"] = ["ひゃくえん"]
        return yen
    }()

    func testNumbersAboveTenAreFoundByDigitsOrKanji() {
        for query in ["15分", "十五分", "じゅうごふん"] {
            let forms = searchCounters([fun, hon], groups: [], query: query).forms
            XCTAssertEqual(forms.map(\.number), [.n(15)], query)
            XCTAssertEqual(forms.first?.counter.id, "fun", query)
        }
        XCTAssertEqual(searchCounters([yen], groups: [], query: "3000円").forms.map(\.number), [.n(3000)])
        XCTAssertEqual(searchCounters([fun], groups: [], query: "100分").forms.map(\.number), [.n(100)])
    }

    func testANumberTheCounterDoesNotHaveIsNotFound() {
        XCTAssertTrue(searchCounters([hon], groups: [], query: "15本").forms.isEmpty)
        XCTAssertTrue(searchCounters([fun], groups: [], query: "60分").forms.isEmpty)
    }

    func testBareTensPrefixesMatchNothing() {
        for query in ["じゅう", "さんじゅう", "ひゃく", "にじゅう"] {
            XCTAssertTrue(searchCounters([fun, yen], groups: [], query: query).forms.isEmpty, query)
        }
        XCTAssertEqual(searchCounters([fun], groups: [], query: "さんじゅうご").forms.map(\.number), [.n(35)])
    }
}
