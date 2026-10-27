import XCTest
@testable import VerbKit

final class CopulaTests: XCTestCase {
    private func loadWords() throws -> [Word] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/words.json")
        return try JSONDecoder().decode(WordsDataFile.self, from: Data(contentsOf: url)).words
    }

    private func word(_ dict: String) throws -> Word {
        try XCTUnwrap(loadWords().first { $0.dict == dict }, dict)
    }

    func testCopulaTableHasTheSevenRows() {
        XCTAssertEqual(Copula.rows.map(\.plain), ["だ", "じゃない", "だった", "じゃなかった", "で", "なら", "だろう"])
        XCTAssertEqual(Copula.rows.map(\.polite), ["です", "じゃないです", "でした", "じゃなかったです", "で", "なら", "でしょう"])
    }

    func testCopulaFormalAlternates() {
        XCTAssertEqual(Copula.rows[1].plainAlt, "ではない")
        XCTAssertEqual(Copula.rows[1].politeAlt, "ではありません")
        XCTAssertEqual(Copula.rows[3].plainAlt, "ではなかった")
        XCTAssertEqual(Copula.rows[3].politeAlt, "ではありませんでした")
    }

    func testSameInBothRegistersRowsCarryANote() {
        for row in Copula.rows where row.plain == row.polite {
            XCTAssertNotNil(row.note, row.plain)
        }
    }

    func testTheTwoJoiningNotes() {
        XCTAssertTrue(Copula.notes.joined().contains("だ becomes な before ので (静かなので)"))
        XCTAssertFalse(Copula.notes.joined().contains("drops"))
        XCTAssertTrue(Copula.notes.joined().contains("学生かもしれない"))
    }

    func testEveryWordInWordsJSONHasFourPoliteForms() throws {
        for word in try loadWords() {
            let rows = try XCTUnwrap(PoliteForms.rows(for: word), word.dict)
            XCTAssertEqual(rows.count, 4, word.dict)
            for row in rows {
                XCTAssertTrue(row.polite.hasSuffix("です") || row.polite.hasSuffix("でした"), "\(word.dict) \(row.polite)")
                // The plain だ must be gone (ともだち has a だ of its own, so look at the joins).
                for leftover in ["だです", "だでした", "だじゃ", "だだ"] {
                    XCTAssertFalse(row.polite.contains(leftover), "\(word.dict) \(row.polite)")
                }
            }
            if word.wordClass == .iAdjective {
                XCTAssertTrue(rows[2].polite.hasSuffix("かったです"), word.dict)
                XCTAssertFalse(rows[2].polite.hasSuffix("いでした"), word.dict)
            }
        }
    }

    func testTakaiPoliteForms() throws {
        let rows = try XCTUnwrap(PoliteForms.rows(for: word("たかい")))
        XCTAssertEqual(rows.map(\.polite), ["たかいです", "たかくないです", "たかかったです", "たかくなかったです"])
        XCTAssertEqual(rows[1].politeAlt, "たかくありません")
        XCTAssertEqual(rows[3].politeAlt, "たかくありませんでした")
        XCTAssertNil(rows[0].politeAlt)
    }

    func testIiAndKakkoiiAreIrregular() throws {
        let ii = try XCTUnwrap(PoliteForms.rows(for: word("いい")))
        XCTAssertEqual(ii.map(\.polite), ["いいです", "よくないです", "よかったです", "よくなかったです"])
        let kakkoii = try XCTUnwrap(PoliteForms.rows(for: word("かっこいい")))
        XCTAssertEqual(kakkoii[2].polite, "かっこよかったです")
    }

    func testNaAdjectiveAndNounPoliteForms() throws {
        let shizuka = try XCTUnwrap(PoliteForms.rows(for: word("しずか")))
        XCTAssertEqual(shizuka.map(\.polite), ["しずかです", "しずかじゃないです", "しずかでした", "しずかじゃなかったです"])
        XCTAssertEqual(shizuka[1].politeAlt, "しずかではありません")
        XCTAssertEqual(shizuka[3].politeAlt, "しずかではありませんでした")
        let student = try XCTUnwrap(PoliteForms.rows(for: word("がくせい")))
        XCTAssertEqual(student.map(\.polite), ["がくせいです", "がくせいじゃないです", "がくせいでした", "がくせいじゃなかったです"])
    }

    func testVerbsHaveNoPoliteAdjectiveRows() throws {
        var verb = try word("たかい")
        verb.wordClass = .verb
        XCTAssertNil(PoliteForms.rows(for: verb))
    }

    func testTheTrapForms() throws {
        let trap = try XCTUnwrap(PoliteForms.trap(for: word("たかい")))
        XCTAssertEqual(trap.wrong, ["たかいでした", "たかくないでした"])
        XCTAssertEqual(trap.right, ["たかかったです", "たかくなかったです"])
    }

    func testOnlyIAdjectivesHaveATrap() throws {
        XCTAssertNil(try PoliteForms.trap(for: word("しずか")))
        XCTAssertNil(try PoliteForms.trap(for: word("がくせい")))
    }
}
