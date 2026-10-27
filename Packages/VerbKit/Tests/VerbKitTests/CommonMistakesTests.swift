import XCTest
@testable import VerbKit

/// Reads the real `data/grammar.json` and `data/counters.json` from the repo checkout.
final class CommonMistakesTests: XCTestCase {
    private func dataURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data").appendingPathComponent(name)
    }

    private func load() throws -> (grammar: [GrammarPoint], counters: [Counter]) {
        let g = try JSONDecoder().decode(GrammarDataFile.self, from: Data(contentsOf: dataURL("grammar.json")))
        let c = try JSONDecoder().decode(CountersDataFile.self, from: Data(contentsOf: dataURL("counters.json")))
        return (g.grammar, c.counters)
    }

    func testEveryPitfallAppearsExactlyOnceUnderATheme() throws {
        let (grammar, counters) = try load()
        let expected = grammar.reduce(0) { $0 + $1.pitfalls.count } + counters.reduce(0) { $0 + $1.pitfalls.count }
        XCTAssertGreaterThan(expected, 90)
        let all = CommonMistakes.build(grammar: grammar, counters: counters)
        XCTAssertEqual(all.count, expected)
        XCTAssertEqual(Set(all.map(\.id)).count, expected)
        let grouped = CommonMistakes.grouped(all)
        XCTAssertEqual(grouped.reduce(0) { $0 + $1.mistakes.count }, expected)
        XCTAssertEqual(grouped.map(\.theme), grouped.map(\.theme).sorted { $0.order < $1.order })
    }

    func testGrammarTableCoversEveryPitfallWithNoStaleKeys() throws {
        let (grammar, _) = try load()
        let keys = Set(grammar.flatMap { p in p.pitfalls.indices.map { "\(p.id)#\($0)" } })
        for key in CommonMistakes.grammarThemes.keys { XCTAssertTrue(keys.contains(key), "stale: \(key)") }
        for key in keys { XCTAssertNotNil(CommonMistakes.grammarThemes[key], "unassigned: \(key)") }
    }

    func testCounterExceptionsHaveNoStaleKeys() throws {
        let (_, counters) = try load()
        let keys = Set(counters.flatMap { c in c.pitfalls.indices.map { "\(c.id)#\($0)" } })
        for key in CommonMistakes.counterExceptions.keys { XCTAssertTrue(keys.contains(key), "stale: \(key)") }
    }

    func testEverySourceRouteResolves() throws {
        let (grammar, counters) = try load()
        for m in CommonMistakes.build(grammar: grammar, counters: counters) {
            XCTAssertNotNil(m.source.resolve(verbs: [], grammarPoints: grammar, counters: counters), m.id)
            XCTAssertFalse(m.sourceTitle.isEmpty, m.id)
        }
    }

    func testCountersDefaultToReadingsWithExceptions() throws {
        let (grammar, counters) = try load()
        let all = CommonMistakes.build(grammar: grammar, counters: counters)
        XCTAssertEqual(all.first { $0.id == "counter:hon#0" }?.theme, .counterReadings)
        XCTAssertEqual(all.first { $0.id == "counter:tou#1" }?.theme, .lookAlike)
    }

    func testSearchFindsAPitfall() throws {
        let (grammar, counters) = try load()
        let all = CommonMistakes.build(grammar: grammar, counters: counters)
        XCTAssertEqual(all.filter { matchesMistakeSearch($0, query: "ら抜き") }.map(\.id), ["potential#1"])
        XCTAssertTrue(all.contains { $0.id == "obligation#0" && matchesMistakeSearch($0, query: "べき") })
        XCTAssertEqual(all.filter { matchesMistakeSearch($0, query: "  ") }.count, all.count)
        XCTAssertTrue(all.filter { matchesMistakeSearch($0, query: "zzqx") }.isEmpty)
    }

    func testWrongFormsCarryThroughToTheMistakes() throws {
        let (grammar, counters) = try load()
        let all = CommonMistakes.build(grammar: grammar, counters: counters)
        XCTAssertEqual(all.first { $0.id == "node#0" }?.wrong, "静かだので")
        XCTAssertEqual(all.first { $0.id == "hou-ga-ii#0" }?.wrong, "行かなかったほうがいい")
        XCTAssertNil(all.first { $0.id == "n-desu#1" }?.wrong)
    }

    func testWrongFormsAreNeverBlankOrAnExample() throws {
        let (grammar, _) = try load()
        let withWrong = grammar.flatMap(\.pitfalls).compactMap { p in p.wrong.map { ($0, p) } }
        XCTAssertGreaterThanOrEqual(withWrong.count, 5)
        for (wrong, pitfall) in withWrong {
            XCTAssertFalse(wrong.trimmingCharacters(in: .whitespaces).isEmpty, pitfall.heading)
            XCTAssertFalse(pitfall.examples.contains { $0.jp.contains(wrong) }, "\(pitfall.heading): shown as correct")
        }
    }

    func testLevelFilteringUsesTheSourceLevel() {
        let m = CommonMistake(
            id: "x#0", theme: .joining, heading: "h", explanation: "e", examples: [],
            source: .grammar("x"), sourceTitle: "X", jlpt: .n3)
        XCTAssertTrue([m].visible(in: LevelSettings(hidden: [.n3])).isEmpty)
        XCTAssertEqual([m].visible(in: LevelSettings()).count, 1)
    }
}
