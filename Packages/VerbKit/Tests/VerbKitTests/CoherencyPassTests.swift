import XCTest
@testable import VerbKit

final class CoherencyPassTests: XCTestCase {
    private static let counters = BundledData<CountersDataFile>.load(named: "counters")!.value.counters

    private func counter(_ written: String) -> Counter { Self.counters.first { $0.counter == written }! }

    // MARK: Start here

    func testStartHereFollowsTheBoardAndDropsHiddenCounters() {
        XCTAssertEqual(CounterHome.startHere(Self.counters).map(\.counter), ["つ", "人", "本", "枚", "個", "匹", "台", "冊", "杯"])
        XCTAssertEqual(CounterHome.startHere(Self.counters.filter { $0.counter != "本" }).count, 8)
        XCTAssertEqual(CounterHome.startHere([]), [])
    }

    // MARK: Counted number

    func testCounterHighlightFindsDigitsKanjiAndKana() {
        let hon = counter("本")
        XCTAssertEqual(CounterHighlight.range(in: "ビールを二本ください。", counter: hon), 4..<6)
        XCTAssertEqual(CounterHighlight.range(in: "ペンが3本あります。", counter: hon), 3..<5)
        XCTAssertEqual(CounterHighlight.range(in: "ペンが１２本あります。", counter: hon), 3..<6)
        XCTAssertEqual(CounterHighlight.range(in: "さんぼんください。", counter: hon), 0..<4)
        XCTAssertEqual(CounterHighlight.range(in: "何本ありますか。", counter: hon), 0..<2)
    }

    func testABareCounterIsNotACount() {
        XCTAssertNil(CounterHighlight.range(in: "本を読みます。", counter: counter("本")))
        XCTAssertNil(CounterHighlight.range(in: "日本人です。", counter: counter("人")))
    }

    func testCounterHighlightTakesTheFirstOfTwo() {
        XCTAssertEqual(CounterHighlight.range(in: "一本と二本", counter: counter("本")), 0..<2)
    }

    func testTheGeneralCounterInKana() {
        let tsu = counter("つ")
        XCTAssertEqual(CounterHighlight.range(in: "りんごを三つください。", counter: tsu), 4..<6)
        XCTAssertEqual(CounterHighlight.range(in: "りんごをみっつください。", counter: tsu), 4..<7)
    }

    func testOrdinaryWordsAndKanaPairs() {
        XCTAssertNil(CounterHighlight.range(in: "つくえがあります。", counter: counter("つ")))
        XCTAssertEqual(CounterHighlight.range(in: "ふたりとさんにん", counter: counter("人")), 0..<3)
        XCTAssertEqual(CounterHighlight.range(in: "いっぽんとにほん", counter: counter("本")), 0..<4)
    }

    // MARK: Headword furigana

    /// The counter's own reading, never the general dictionary's (人 is にん here, not ひと).
    func testHeadwordUnitsCarryTheCountersReading() {
        XCTAssertEqual(counter("人").headwordUnits, [TextUnit(text: "人", reading: "にん")])
        XCTAssertEqual(counter("頭").headwordUnits, [TextUnit(text: "頭", reading: "とう")])
        XCTAssertEqual(counter("つ").headwordUnits, [TextUnit(text: "つ")])
        let months = Self.counters.first { $0.counter.hasPrefix("か") && $0.counter.count > 1 }
        if let months {
            XCTAssertEqual(months.headwordUnits.first, TextUnit(text: "か"), months.counter)
            XCTAssertNil(months.headwordUnits.first?.reading)
            XCTAssertNotNil(months.headwordUnits.last?.reading)
        }
    }

    // MARK: Tag counts

    func testTagCountsAreSortedAndLimited() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        func entry(_ dialect: [UUID], _ custom: [UUID] = []) -> WordBankEntryValue {
            var value = WordBankEntryValue(text: "x")
            value.dialectTagIDs = dialect
            value.customTagIDs = custom
            return value
        }
        let entries = [entry([a], [b]), entry([a], [c]), entry([a, d], [b, c]), entry([])]
        let top = WordBankTagCounts.top(entries, limit: 3)
        XCTAssertEqual(top.map(\.count), [3, 2, 2])
        XCTAssertEqual(top.first?.tagID, a)
        XCTAssertEqual(Set(top.dropFirst().map(\.tagID)), [b, c])
        XCTAssertEqual(top[1].tagID.uuidString < top[2].tagID.uuidString, true, "ties by id")
        XCTAssertEqual(WordBankTagCounts.top([entry([])], limit: 6), [])
    }
}
