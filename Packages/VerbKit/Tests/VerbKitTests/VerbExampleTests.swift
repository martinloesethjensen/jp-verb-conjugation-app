import XCTest
@testable import VerbKit

final class VerbExampleTests: XCTestCase {
    private func decode(_ json: String) throws -> VerbExample {
        try JSONDecoder().decode(VerbExample.self, from: Data(json.utf8))
    }

    func testDecodesABasicForm() throws {
        let example = try decode(#"{"form": "te", "jp": "たべてください。", "en": "Please eat."}"#)
        XCTAssertEqual(example.form, .te)
    }

    func testDecodesANonBasicCatalogueForm() throws {
        let example = try decode(#"{"form": "tai", "jp": "すしがたべたい。", "en": "I want to eat sushi."}"#)
        XCTAssertEqual(example.form, "tai")
        XCTAssertNotNil(FormCatalogue.bundled.spec(for: example.form))
        XCTAssertEqual(FormCatalogue.bundled.label(for: example.form), FormCatalogue.bundled.spec(for: "tai")?.label)
    }

    /// A form a newer catalogue adds still decodes, and its label falls back to the id.
    func testKeepsAnIDThisBuildDoesNotKnow() throws {
        let example = try decode(#"{"form": "zu_ni", "jp": "たべずに", "en": "without eating"}"#)
        XCTAssertEqual(example.form, "zu_ni")
        XCTAssertEqual(FormCatalogue.bundled.label(for: example.form), "zu_ni")
    }

    /// Encoded as a bare string, as `FormKey` was, so examples persisted by `VerbEntity`
    /// before this change still decode.
    func testRoundTripsAsABareString() throws {
        let example = VerbExample(form: "teiru", jp: "たべている。", en: "I am eating.")
        let data = try JSONEncoder().encode(example)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["form"] as? String, "teiru")
        XCTAssertEqual(try JSONDecoder().decode(VerbExample.self, from: data), example)
    }
}

/// Every example in the real `data/verbs.json` decodes with its form, and that form is one
/// the catalogue knows and the verb has (`update_data.py --check` enforces the same).
final class RealVerbExamplesTests: XCTestCase {
    func testEveryShippedExampleDecodesWithAFormItsVerbHas() throws {
        let verbs = try RealVerbs.load()
        let examples = verbs.flatMap { verb in verb.examples.map { (verb, $0) } }
        XCTAssertFalse(examples.isEmpty)
        for (verb, example) in examples {
            XCTAssertNotNil(FormCatalogue.bundled.spec(for: example.form), "\(verb.dict): \(example.form.rawValue)")
            let value = try XCTUnwrap(verb.forms[id: example.form], "\(verb.dict): \(example.form.rawValue)")
            XCTAssertFalse(value.isEmpty, "\(verb.dict): \(example.form.rawValue)")
        }
    }

    /// The sentence contains the form it is tagged with, in kana or written with the verb's
    /// kanji, so the tag matches the sentence and the fill-in quiz can blank it.
    func testEveryShippedExampleContainsItsForm() throws {
        for verb in try RealVerbs.load() {
            for example in verb.examples {
                let value = try XCTUnwrap(verb.forms[id: example.form], "\(verb.dict): \(example.form.rawValue)")
                let spellings = [value] + [verb.kanjiSpelling(of: value)].compactMap { $0 }
                XCTAssertTrue(spellings.contains { example.jp.contains($0) },
                              "\(verb.dict): \(example.jp) does not contain \(spellings) (\(example.form.rawValue))")
            }
        }
    }
}

final class VerbKanjiSpellingTests: XCTestCase {
    private func verb(_ dict: String, _ kanji: String?) throws -> Verb {
        try XCTUnwrap(try RealVerbs.load().first { $0.dict == dict && $0.kanji == kanji })
    }

    func testWritesTheStemInKanji() throws {
        XCTAssertEqual(try verb("たべる", "食べる").kanjiSpelling(of: "たべます"), "食べます")
        XCTAssertEqual(try verb("いく", "行く").kanjiSpelling(of: "いって"), "行って")
        XCTAssertEqual(try verb("わかる", "分かる").kanjiSpelling(of: "わからない"), "分からない")
        XCTAssertEqual(try verb("できる", "出来る").kanjiSpelling(of: "できます"), "出来ます")
    }

    func testAnIrregularStemChangesItsKana() throws {
        let kuru = try verb("くる", "来る")
        XCTAssertEqual(kuru.kanjiSpelling(of: "きます"), "来ます")
        XCTAssertEqual(kuru.kanjiSpelling(of: "こない"), "来ない")
        XCTAssertEqual(kuru.kanjiSpelling(of: "くれば"), "来れば")
    }

    func testNilWithoutKanjiOrWithoutTheStem() throws {
        XCTAssertNil(try verb("する", nil).kanjiSpelling(of: "します"))
        XCTAssertNil(try verb("たべる", "食べる").kanjiSpelling(of: "のみます"))
    }
}
