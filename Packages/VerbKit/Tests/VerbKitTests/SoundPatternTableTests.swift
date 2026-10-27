import XCTest
@testable import VerbKit

final class SoundPatternTableTests: XCTestCase {
    private func counter(
        _ id: String, sound: String, readings: [String: String] = [:], changed: [String] = []
    ) -> Counter {
        Counter(
            id: id, counter: id, reading: id, meaning: id, sound: sound, symbol: "pencil",
            readings: readings.mapValues { [$0] }, changed: changed
        )
    }

    private var ko: Counter { counter("ko", sound: "k", readings: ["1": "いっこ", "3": "さんこ", "6": "ろっこ"], changed: ["1", "6"]) }
    private var kai: Counter { counter("kai", sound: "k", readings: ["1": "いっかい"], changed: ["1"]) }
    private var satsu: Counter { counter("satsu", sound: "s", readings: ["1": "いっさつ", "3": "さんさつ", "6": "ろくさつ"], changed: ["1"]) }
    private var hon: Counter { counter("hon", sound: "h-b", readings: ["1": "いっぽん", "3": "さんぼん", "6": "ろっぽん"], changed: ["1", "3", "6"]) }
    private var fun: Counter { counter("fun", sound: "h-p", readings: ["1": "いっぷん", "3": "さんぷん", "4": "よんぷん", "6": "ろっぷん"], changed: ["1", "3", "4", "6"]) }
    private var mai: Counter { counter("mai", sound: "plain", readings: ["1": "いちまい", "3": "さんまい", "6": "ろくまい"]) }
    private var nin: Counter { counter("nin", sound: "irregular") }

    func testNumbersAreTheOnesThatEverChange() {
        XCTAssertEqual(soundPatternTable(from: [hon]).numbers, [.n(1), .n(3), .n(6), .n(8), .n(10)])
    }

    func testColumnsGroupBySoundClassAndSkipEmptyOnes() {
        let table = soundPatternTable(from: [mai, hon, fun, ko, nin])
        XCTAssertEqual(table.columns.map(\.id), [.k, .h, .other])
        XCTAssertEqual(table.columns.first { $0.id == .h }?.counters.map(\.id), ["hon", "fun"])
        XCTAssertEqual(table.irregular.map(\.id), ["nin"])
    }

    func testTheSampleIsTheFixedCounterWhenVisibleElseTheFirstOfTheColumn() {
        XCTAssertEqual(soundPatternTable(from: [fun, hon]).columns[0].sample.id, "hon")
        XCTAssertEqual(soundPatternTable(from: [kai, ko]).columns[0].sample.id, "ko")
        XCTAssertEqual(soundPatternTable(from: [kai]).columns[0].sample.id, "kai")
    }

    func testACellIsTheSamplesPreferredReadingAndItsChange() {
        let table = soundPatternTable(from: [ko, satsu])
        XCTAssertEqual(table.cell(.n(6), .k)?.reading, "ろっこ")
        XCTAssertEqual(table.cell(.n(6), .k)?.changed, true)
        XCTAssertEqual(table.cell(.n(6), .s)?.changed, false)
        XCTAssertNil(table.cell(.n(6), .h))
    }

    func testSentenceNamesTheColumnsAndTheSharedStem() {
        let table = soundPatternTable(from: [ko, satsu, hon, mai])
        XCTAssertEqual(table.sentence(for: .n(6)), "6 → ろっ in か行 and は行")
    }

    func testSentenceSaysWhenNothingChangesAndWhenThereIsNoSharedStem() {
        let table = soundPatternTable(from: [ko, satsu, hon, mai])
        XCTAssertEqual(table.sentence(for: .n(8)), "8 never changes sound in these columns.")
        XCTAssertEqual(table.sentence(for: .n(3)), "3 changes in は行")
    }

    func testExceptionsAreWhatACounterChangesBeyondItsColumn() {
        let table = soundPatternTable(from: [hon, fun])
        XCTAssertEqual(table.exceptions.map(\.counter.id), ["fun"])
        XCTAssertEqual(table.exceptions.first?.numbers, [.n(4)])
    }

    func testAffectedCountersAreThoseThatChangeNotJustTheSamplesColumn() {
        let floor = counter("kai-floor", sound: "k", readings: ["3": "さんがい"], changed: ["3"])
        let table = soundPatternTable(from: [ko, floor, hon, mai])
        XCTAssertEqual(table.affected(for: .n(3)).map(\.id), ["kai-floor", "hon"])
        XCTAssertEqual(table.affected(for: .n(6)).map(\.id), ["ko", "hon"])
        XCTAssertEqual(table.affected(for: .n(8)).map(\.id), [])
    }
}
