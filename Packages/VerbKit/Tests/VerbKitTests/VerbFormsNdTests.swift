import XCTest
@testable import VerbKit

final class VerbFormsNdTests: XCTestCase {
    private func baseForms() -> VerbForms {
        VerbForms(
            masuPos: "たべます", masuNeg: "たべません", masuPast: "たべました", masuPastNeg: "たべませんでした",
            te: "たべて", shortPos: "たべる", shortNeg: "たべない", shortPast: "たべた", shortPastNeg: "たべなかった"
        )
    }

    func testHasNdFormsIsFalseByDefault() {
        XCTAssertFalse(baseForms().hasNdForms)
    }

    func testHasNdFormsIsTrueWhenAnyFieldIsSet() {
        var forms = baseForms()
        forms.ndCasualPastNeg = "たべなかったんだ"
        XCTAssertTrue(forms.hasNdForms)
    }

    func testDecodesSnakeCaseNdKeys() throws {
        let json = """
        {
          "masu_pos": "a", "masu_neg": "b", "masu_past": "c", "masu_past_neg": "d",
          "te": "e", "short_pos": "f", "short_neg": "g", "short_past": "h", "short_past_neg": "i",
          "nd_pos": "1", "nd_neg": "2", "nd_past": "3", "nd_past_neg": "4",
          "nd_casual_pos": "5", "nd_casual_neg": "6", "nd_casual_past": "7", "nd_casual_past_neg": "8"
        }
        """
        let forms = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertEqual(
            [forms.ndPos, forms.ndNeg, forms.ndPast, forms.ndPastNeg,
             forms.ndCasualPos, forms.ndCasualNeg, forms.ndCasualPast, forms.ndCasualPastNeg],
            ["1", "2", "3", "4", "5", "6", "7", "8"]
        )
    }

    func testOldDataWithoutNdKeysStillDecodes() throws {
        let json = """
        {
          "masu_pos": "a", "masu_neg": "b", "masu_past": "c", "masu_past_neg": "d",
          "te": "e", "short_pos": "f", "short_neg": "g", "short_past": "h", "short_past_neg": "i"
        }
        """
        let forms = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertFalse(forms.hasNdForms)
    }

    func testEncodesSnakeCaseNdKeys() throws {
        var forms = baseForms()
        forms.ndPos = "たべるんです"
        forms.ndCasualPastNeg = "たべなかったんだ"
        let data = try JSONEncoder().encode(forms)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["nd_pos"] as? String, "たべるんです")
        XCTAssertEqual(object["nd_casual_past_neg"] as? String, "たべなかったんだ")
        XCTAssertNil(object["nd_neg"])
    }
}
