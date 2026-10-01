import XCTest
@testable import VerbKit

/// Splits every form of every verb in the real `data/verbs.json` and checks the
/// pieces always rebuild the form and the stem always belongs to the dictionary form.
final class RealFormSplitTests: XCTestCase {
    private func loadVerbs() throws -> [Verb] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent("verbs.json")
        return try JSONDecoder().decode(VerbDataFile.self, from: Data(contentsOf: url)).verbs
    }

    /// Every populated form string on a verb, via its JSON representation.
    private func allForms(of verb: Verb) throws -> [String] {
        let data = try JSONEncoder().encode(verb.forms)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        return Array(object.values)
    }

    func testStemPlusEndingAlwaysRebuildsTheForm() throws {
        var checked = 0
        for verb in try loadVerbs() {
            for form in try allForms(of: verb) {
                let split = FormSplit.split(form, from: verb.dict)
                XCTAssertEqual(split.stem + split.ending, form, "\(verb.dict): \(form)")
                XCTAssertTrue(verb.dict.hasPrefix(split.stem), "\(verb.dict): \(form) stem \(split.stem)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 25 * 40)
    }

    func testOnlyTheDictionaryFormItselfHasNoEnding() throws {
        for verb in try loadVerbs() {
            for form in try allForms(of: verb) where !FormSplit.split(form, from: verb.dict).hasEnding {
                XCTAssertEqual(form, verb.dict, "\(verb.dict) has a form with no ending: \(form)")
            }
        }
    }

    func testWellKnownSplits() throws {
        let verbs = try loadVerbs()
        func forms(_ dict: String) throws -> VerbForms {
            try XCTUnwrap(verbs.first { $0.dict == dict }, dict).forms
        }
        XCTAssertEqual(FormSplit.split(try forms("たべる").potential!, from: "たべる"), FormSplit(stem: "たべ", ending: "られる"))
        XCTAssertEqual(FormSplit.split(try forms("のむ").potential!, from: "のむ"), FormSplit(stem: "の", ending: "める"))
        XCTAssertEqual(FormSplit.split(try forms("くる").masuPos, from: "くる"), FormSplit(stem: "", ending: "きます"))
        XCTAssertEqual(FormSplit.split(try forms("する").potential!, from: "する"), FormSplit(stem: "", ending: "できる"))
        XCTAssertEqual(FormSplit.split(try forms("たべる").shortPos, from: "たべる").hasEnding, false)
    }
}
