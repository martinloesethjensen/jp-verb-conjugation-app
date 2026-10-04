import XCTest
@testable import VerbKit

final class WordModelTests: XCTestCase {
    private struct VerbsFile: Decodable {
        var verbs: [Word]
    }

    private func realURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data/verbs.json")
    }

    // MARK: FormID and Conjugations

    func testFormIDCodesAsABareString() throws {
        let data = try JSONEncoder().encode(["id": FormID.masuPos])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"id":"masu_pos"}"#)
        let decoded = try JSONDecoder().decode([String: FormID].self, from: data)
        XCTAssertEqual(decoded["id"], .masuPos)
    }

    func testConjugationsCodeAsAnObjectOfIdToString() throws {
        let forms = Conjugations([.te: "たべて", .masuPos: "たべます"])
        let data = try JSONEncoder().encode(forms)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object, ["te": "たべて", "masu_pos": "たべます"])
        XCTAssertEqual(try JSONDecoder().decode(Conjugations.self, from: data), forms)
    }

    func testConjugationsSubscriptAndIds() {
        var forms = Conjugations()
        XCTAssertTrue(forms.isEmpty)
        XCTAssertNil(forms[.te])
        forms[.te] = "して"
        XCTAssertEqual(forms[.te], "して")
        XCTAssertEqual(forms.ids, [.te])
        forms[.te] = nil
        XCTAssertTrue(forms.isEmpty)
    }

    func testAnUnknownFormIDSurvivesTheRoundTrip() throws {
        let json = #"{"future_form":"x","te":"して"}"#
        let forms = try JSONDecoder().decode(Conjugations.self, from: Data(json.utf8))
        XCTAssertEqual(forms["future_form"], "x")
        XCTAssertEqual(forms.count, 2)
    }

    func testWordClassCoversTheFourClasses() {
        XCTAssertEqual(WordClass.allCases.map(\.rawValue), ["verb", "i-adjective", "na-adjective", "noun"])
    }

    // MARK: Word from a Verb

    func testWordFromAVerbKeepsTheFormsAndExamples() throws {
        for verb in try RealVerbs.load() {
            let word = Word(verb)
            XCTAssertEqual(word.wordClass, .verb)
            XCTAssertEqual(word.dict, verb.dict)
            XCTAssertEqual(word.verb?.type, verb.type)
            XCTAssertEqual(word.verb?.label, verb.label)
            XCTAssertEqual(word.verb?.teGroup, verb.teGroup)
            XCTAssertEqual(word.jlpt, verb.jlpt)
            XCTAssertEqual(word.examples.map(\.form.rawValue), verb.examples.map(\.form.rawValue))
            for key in FormKey.allCases {
                XCTAssertEqual(word.forms[FormID(rawValue: key.rawValue)], verb.forms[key], "\(verb.dict) \(key)")
            }
            XCTAssertEqual(word.forms[.potential], verb.forms.potential, verb.dict)
        }
    }

    func testWordFormsAreExactlyTheKeysInTheDataFile() throws {
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: realURL())) as? [String: Any]
        let entries = try XCTUnwrap(raw?["verbs"] as? [[String: Any]])
        let verbs = try RealVerbs.load()
        XCTAssertEqual(entries.count, verbs.count)
        for (entry, verb) in zip(entries, verbs) {
            let keys = Set(try XCTUnwrap((entry["forms"] as? [String: Any])?.keys))
            XCTAssertEqual(Set(Word(verb).forms.ids.map(\.rawValue)), keys, verb.dict)
        }
    }

    func testEveryFormInTheDataIsInTheCatalogue() throws {
        for verb in try RealVerbs.load() {
            for id in Word(verb).forms.ids {
                XCTAssertNotNil(FormCatalogue.bundled.spec(for: id), "\(verb.dict): \(id.rawValue)")
            }
        }
    }

    // MARK: Word decoded from the data file

    func testDecodingTheVerbDataFileAsWordsMatchesTheBridge() throws {
        let data = try Data(contentsOf: realURL())
        let words = try JSONDecoder().decode(VerbsFile.self, from: data).verbs
        XCTAssertEqual(words, try RealVerbs.load().map { Word($0) })
    }

    func testAnEntryWithoutWordClassIsAVerb() throws {
        let json = """
        {"type":"ru","label":"Ru-verb","dict":"たべる","meaning":"to eat","description":"d",
         "forms":{"te":"たべて"},"examples":[]}
        """
        let word = try JSONDecoder().decode(Word.self, from: Data(json.utf8))
        XCTAssertEqual(word.wordClass, .verb)
        XCTAssertEqual(word.verb?.type, .ru)
    }

    func testANonVerbEntryNeedsNoVerbFieldsAndKeepsAlternates() throws {
        let json = """
        {"word_class":"na-adjective","dict":"しずか","kanji":"静か","meaning":"quiet","description":"d",
         "forms":{"short_pos":"しずかだ","polite_neg":"しずかじゃないです"},
         "alt":{"polite_neg":["しずかではありません"]}}
        """
        let word = try JSONDecoder().decode(Word.self, from: Data(json.utf8))
        XCTAssertEqual(word.wordClass, .naAdjective)
        XCTAssertNil(word.verb)
        XCTAssertEqual(word.alternates["polite_neg"], ["しずかではありません"])
        XCTAssertEqual(word.baseForm, "しずかだ")
        XCTAssertEqual(word.id, "na-adjective:しずか")
        XCTAssertTrue(word.examples.isEmpty)
    }

    func testAVerbEntryWithoutATypeFailsToDecode() {
        let json = #"{"dict":"たべる","meaning":"m","description":"d","forms":{}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Word.self, from: Data(json.utf8)))
    }

    func testWordRoundTripsThroughJSON() throws {
        for verb in try RealVerbs.load() {
            let word = Word(verb)
            let data = try JSONEncoder().encode(word)
            XCTAssertEqual(try JSONDecoder().decode(Word.self, from: data), word, verb.dict)
        }
    }

    func testBaseFormFallsBackToTheCitationForm() {
        let word = Word(wordClass: .noun, dict: "がくせい", meaning: "student", description: "d", forms: Conjugations())
        XCTAssertEqual(word.baseForm, "がくせい")
    }

    func testWordsAreLeveled() {
        let word = Word(wordClass: .noun, dict: "がくせい", meaning: "m", description: "d", jlpt: .n5, forms: Conjugations())
        XCTAssertTrue([word].visible(in: LevelSettings(hidden: [.n5])).isEmpty)
        XCTAssertEqual([word].visible(in: LevelSettings(hidden: [.n4])).count, 1)
    }
}
