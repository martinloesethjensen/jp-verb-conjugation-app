import XCTest
@testable import VerbKit

final class VerbDecodingTests: XCTestCase {
    private func loadFixture() throws -> VerbDataFile {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "verbs-fixture", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(VerbDataFile.self, from: data)
    }

    func testDecodesVerbDataFile() throws {
        let file = try loadFixture()
        XCTAssertEqual(file.verbs.count, 2)
        XCTAssertEqual(file.version, "test-fixture")
    }

    func testDecodesIrregularVerbWithoutTeGroup() throws {
        let file = try loadFixture()
        let suru = try XCTUnwrap(file.verbs.first { $0.dict == "する" })
        XCTAssertEqual(suru.type, .irregular)
        XCTAssertNil(suru.teGroup)
        XCTAssertNil(suru.kanji)
        XCTAssertEqual(suru.forms.masuPos, "します")
        XCTAssertEqual(suru.forms.shortPastNeg, "しなかった")
        XCTAssertNil(suru.forms.potential)
    }

    func testDecodesRuVerbWithExamples() throws {
        let file = try loadFixture()
        let taberu = try XCTUnwrap(file.verbs.first { $0.dict == "たべる" })
        XCTAssertEqual(taberu.type, .ru)
        XCTAssertEqual(taberu.kanji, "食べる")
        XCTAssertNil(taberu.notes)
        XCTAssertEqual(taberu.examples.count, 2)
        XCTAssertEqual(taberu.examples[0].form, .te)
        XCTAssertEqual(taberu.examples[0].jp, "たべてください。")
    }

    func testFormSubscriptMatchesNamedProperty() throws {
        let file = try loadFixture()
        let suru = try XCTUnwrap(file.verbs.first { $0.dict == "する" })
        XCTAssertEqual(suru.forms[.masuPos], suru.forms.masuPos)
        XCTAssertEqual(suru.forms[.te], "して")
    }

    func testVerbIDIsDictForm() throws {
        let file = try loadFixture()
        let suru = try XCTUnwrap(file.verbs.first { $0.dict == "する" })
        XCTAssertEqual(suru.id, "する")
    }
}
