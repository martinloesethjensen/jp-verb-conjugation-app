import Foundation
@testable import VerbKit

/// A small, valid grammar file shared by the grammar sync, persistence,
/// store, search and route tests.
enum GrammarFixture {
    static let json = """
    {
      "version": "test-fixture",
      "description": "Fixture for grammar tests.",
      "grammar": [
        {
          "id": "n-desu",
          "title": "んです",
          "summary": "Marks explanation. なんです after nouns and な-adjectives.",
          "level": "beginner",
          "usages": [
            {
              "heading": "Giving a reason",
              "explanation": "Explains why.",
              "examples": [ { "jp": "頭が痛いんです。", "en": "I have a headache." } ]
            }
          ],
          "attachment": [
            { "word_class": "verb", "pattern": "plain form + んです", "example": "食べるんです" }
          ],
          "conjugations": [ { "form": "んです", "register": "polite" } ],
          "pitfalls": [],
          "related": [ "wake-desu" ]
        },
        {
          "id": "wake-desu",
          "title": "わけです",
          "summary": "Marks a logical conclusion.",
          "level": "intermediate",
          "usages": [
            {
              "heading": "Conclusion",
              "explanation": "That is why.",
              "examples": [ { "jp": "だから太ったわけです。", "en": "So that's why I gained weight." } ]
            }
          ],
          "attachment": [],
          "conjugations": [],
          "pitfalls": [],
          "related": []
        }
      ]
    }
    """

    static var data: Data { Data(json.utf8) }

    static var points: [GrammarPoint] {
        // Force-try is fine: the fixture is a compile-time constant.
        try! JSONDecoder().decode(GrammarDataFile.self, from: data).grammar
    }
}
