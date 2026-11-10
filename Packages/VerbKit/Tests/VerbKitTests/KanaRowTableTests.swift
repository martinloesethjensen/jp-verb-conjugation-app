import XCTest
@testable import VerbKit

final class GodanEndingTests: XCTestCase {
    func testTheNineEndingsInKanaTableOrder() {
        XCTAssertEqual(GodanEnding.endings, ["う", "く", "ぐ", "す", "つ", "ぬ", "ぶ", "む", "る"])
    }

    func testEachEndingAlongItsRow() {
        XCTAssertEqual(KanaRow.allCases.map { GodanEnding.kana("く", in: $0) }, ["か", "き", "く", "け", "こ"])
        XCTAssertEqual(KanaRow.allCases.map { GodanEnding.kana("す", in: $0) }, ["さ", "し", "す", "せ", "そ"])
        XCTAssertEqual(KanaRow.allCases.map { GodanEnding.kana("つ", in: $0) }, ["た", "ち", "つ", "て", "と"])
        XCTAssertEqual(KanaRow.allCases.map { GodanEnding.kana("ぶ", in: $0) }, ["ば", "び", "ぶ", "べ", "ぼ"])
    }

    /// The あ-row of う is わ: 買わない, never 買あない.
    func testUTakesWaInTheARow() {
        XCTAssertEqual(KanaRow.allCases.map { GodanEnding.kana("う", in: $0) }, ["わ", "い", "う", "え", "お"])
    }

    func testNotAnEnding() {
        XCTAssertNil(GodanEnding.kana("か", in: .e))
        XCTAssertNil(GodanEnding.kana("ん", in: .a))
    }

    func testPositionOfAKana() {
        XCTAssertEqual(GodanEnding.position(of: "け")?.row, .e)
        XCTAssertEqual(GodanEnding.position(of: "け")?.ending, "く")
        XCTAssertEqual(GodanEnding.position(of: "わ")?.row, .a)
        XCTAssertEqual(GodanEnding.position(of: "わ")?.ending, "う")
        XCTAssertEqual(GodanEnding.position(of: "い")?.row, .i)
        XCTAssertNil(GodanEnding.position(of: "あ"))
        XCTAssertNil(GodanEnding.position(of: "ん"))
    }
}

final class KanaRowTableTests: XCTestCase {
    private func rule(_ example: String, row: KanaRow? = .e) -> AttachmentRule {
        AttachmentRule(wordClass: .verb, condition: "U-verbs", pattern: "p", example: example, kanaRow: row)
    }

    func testRowsFromTheRulesExamples() throws {
        let table = try XCTUnwrap(KanaRowTable(rule: rule("飲む → 飲める / 買う → 買える")))
        XCTAssertEqual(table.target, .e)
        XCTAssertEqual(table.rows.map(\.base), ["飲む", "買う"])
        XCTAssertEqual(table.rows.map(\.built), ["飲める", "買える"])
        XCTAssertEqual(table.rows.map(\.ending), ["む", "う"])
        XCTAssertEqual(table.rows[1].kana, ["わ", "い", "う", "え", "お"])
    }

    func testNoTableWithoutAKanaRow() {
        XCTAssertNil(KanaRowTable(rule: rule("飲む → 飲める", row: nil)))
    }

    /// A pair that does not end in a u-verb ending (する) is left out; with none left, no table.
    func testSkipsPairsThatAreNotUVerbs() throws {
        let table = try XCTUnwrap(KanaRowTable(rule: rule("飲む → 飲める / 勉強する → 勉強できる / 見る")))
        XCTAssertEqual(table.rows.map(\.base), ["飲む"])
        XCTAssertNil(KanaRowTable(rule: rule("勉強する → 勉強できる")))
    }

    func testThePotentialAndVolitionalLessonsHaveTables() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/grammar.json")
        let points = try JSONDecoder().decode(GrammarDataFile.self, from: Data(contentsOf: url)).grammar
        for (id, row) in [("potential", KanaRow.e), ("volitional", .o)] {
            let lesson = try XCTUnwrap(points.first { $0.id == id }, id)
            let tables = lesson.attachment.compactMap(KanaRowTable.init(rule:))
            XCTAssertEqual(tables.count, 1, id)
            XCTAssertEqual(tables.first?.target, row, id)
            XCTAssertEqual(Set(tables.first?.rows.map(\.ending) ?? []), Set(GodanEnding.endings), id)
        }
    }
}
