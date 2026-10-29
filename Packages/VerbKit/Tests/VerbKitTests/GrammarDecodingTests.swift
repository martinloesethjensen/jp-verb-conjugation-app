import XCTest
@testable import VerbKit

final class GrammarDecodingTests: XCTestCase {
    private let json = """
    {
      "version": "test",
      "description": "d",
      "grammar": [
        {
          "id": "n-desu",
          "title": "んです",
          "summary": "Explanatory ending.",
          "jlpt": "N5",
          "usages": [
            {
              "heading": "Giving a reason",
              "explanation": "Explains why.",
              "examples": [ { "jp": "頭が痛いんです。", "en": "I have a headache." } ]
            }
          ],
          "attachment": [
            { "word_class": "verb", "pattern": "plain form + んです", "example": "食べるんです" },
            { "word_class": "na-adjective", "condition": "non-past, affirmative", "pattern": "stem + なんです", "example": "静かなんです", "note": "だ becomes な" }
          ],
          "conjugations": [
            { "form": "んです", "register": "polite" },
            { "form": "の (soft statement)", "register": "casual", "note": "sounds softer" }
          ],
          "pitfalls": [
            {
              "heading": "Negation",
              "explanation": "Negating the explanation is not a refusal.",
              "examples": [ { "jp": "食べるんじゃない。", "en": "Don't eat!" } ]
            },
            { "heading": "Past", "explanation": "Put the past on the verb." }
          ],
          "related": []
        }
      ]
    }
    """

    private func decode() throws -> GrammarDataFile {
        try JSONDecoder().decode(GrammarDataFile.self, from: Data(json.utf8))
    }

    func testOldGrammarJSONWithoutBooksOrTaughtInDecodes() throws {
        let file = try decode()
        XCTAssertEqual(file.books, [])
        XCTAssertEqual(file.grammar[0].taughtIn, [])
    }

    func testBooksAndTaughtInDecode() throws {
        let file = try JSONDecoder().decode(GrammarDataFile.self, from: GrammarFixture.data)
        XCTAssertEqual(file.books.map(\.id), ["genki-1", "genki-2"])
        XCTAssertEqual(file.books[0].firstLesson, 1)
        XCTAssertEqual(file.books[0].edition, "3rd")
        XCTAssertNil(file.books[1].edition)
        XCTAssertEqual(file.books[1].firstLesson, 13)
        XCTAssertFalse(file.books[1].contains(lesson: 12))
        XCTAssertTrue(file.books[1].contains(lesson: 13))
        XCTAssertTrue(file.books[1].contains(lesson: 23))
        XCTAssertFalse(file.books[1].contains(lesson: 24))
        XCTAssertEqual(file.grammar[0].taughtIn, [LessonRef(book: "genki-2", lesson: 21, reviewed: true)])
    }

    func testDecodesGrammarDataFile() throws {
        let file = try decode()
        XCTAssertEqual(file.grammar.count, 1)
        let point = file.grammar[0]
        XCTAssertEqual(point.id, "n-desu")
        XCTAssertEqual(point.jlpt, .n5)
        XCTAssertEqual(point.usages[0].examples[0].jp, "頭が痛いんです。")
        XCTAssertEqual(point.related, [])
    }

    func testDecodesAttachmentRulesWithOptionalFields() throws {
        let point = try decode().grammar[0]
        XCTAssertEqual(point.attachment[0].wordClass, .verb)
        XCTAssertNil(point.attachment[0].condition)
        XCTAssertNil(point.attachment[0].note)
        XCTAssertEqual(point.attachment[1].wordClass, .naAdjective)
        XCTAssertEqual(point.attachment[1].condition, "non-past, affirmative")
        XCTAssertEqual(point.attachment[1].note, "だ becomes な")
    }

    func testDecodesConjugationRegisters() throws {
        let point = try decode().grammar[0]
        XCTAssertEqual(point.conjugations.map(\.register), [.polite, .casual])
        XCTAssertEqual(point.conjugations[1].note, "sounds softer")
    }

    func testDecodesPitfallsWithAndWithoutExamples() throws {
        let point = try decode().grammar[0]
        XCTAssertEqual(point.pitfalls.map(\.heading), ["Negation", "Past"])
        XCTAssertEqual(point.pitfalls[0].examples[0].en, "Don't eat!")
        XCTAssertEqual(point.pitfalls[1].examples, [])
    }

    func testPitfallWrongFormIsOptional() throws {
        let withWrong = """
        {"heading": "h", "explanation": "e", "wrong": "静かだので"}
        """
        let without = """
        {"heading": "h", "explanation": "e"}
        """
        XCTAssertEqual(try JSONDecoder().decode(GrammarPitfall.self, from: Data(withWrong.utf8)).wrong, "静かだので")
        XCTAssertNil(try JSONDecoder().decode(GrammarPitfall.self, from: Data(without.utf8)).wrong)
        XCTAssertNil(try decode().grammar[0].pitfalls[0].wrong)
    }

    func testPitfallWrongFormSurvivesARoundTrip() throws {
        let pitfall = GrammarPitfall(heading: "h", explanation: "e", wrong: "静かだので")
        let again = try JSONDecoder().decode(GrammarPitfall.self, from: JSONEncoder().encode(pitfall))
        XCTAssertEqual(again, pitfall)
    }

    func testKeywordsAreOptional() throws {
        XCTAssertEqual(try decode().grammar[0].keywords, [])
    }

    func testKeywordsDecodeAndSurviveARoundTrip() throws {
        let withKeywords = json.replacingOccurrences(
            of: #""summary": "Explanatory ending.","#,
            with: #""summary": "Explanatory ending.", "keywords": ["the reason is", "how come"],"#
        )
        let point = try JSONDecoder().decode(GrammarDataFile.self, from: Data(withKeywords.utf8)).grammar[0]
        XCTAssertEqual(point.keywords, ["the reason is", "how come"])
        let again = try JSONDecoder().decode(GrammarPoint.self, from: JSONEncoder().encode(point))
        XCTAssertEqual(again.keywords, ["the reason is", "how come"])
    }

    func testNonStringKeywordFailsDecoding() {
        let bad = json.replacingOccurrences(
            of: #""summary": "Explanatory ending.","#, with: #""summary": "Explanatory ending.", "keywords": [3],"#
        )
        XCTAssertThrowsError(try JSONDecoder().decode(GrammarDataFile.self, from: Data(bad.utf8)))
    }

    func testIDIsSlug() throws {
        XCTAssertEqual(try decode().grammar[0].id, GrammarPoint.nDesuID)
    }

    func testUnknownWordClassFailsDecoding() {
        let bad = json.replacingOccurrences(of: "\"verb\"", with: "\"adverb\"")
        XCTAssertThrowsError(try JSONDecoder().decode(GrammarDataFile.self, from: Data(bad.utf8)))
    }

    func testEncodeDecodeRoundTrip() throws {
        let file = try decode()
        let data = try JSONEncoder().encode(file)
        let again = try JSONDecoder().decode(GrammarDataFile.self, from: data)
        XCTAssertEqual(again.grammar, file.grammar)
    }
}
