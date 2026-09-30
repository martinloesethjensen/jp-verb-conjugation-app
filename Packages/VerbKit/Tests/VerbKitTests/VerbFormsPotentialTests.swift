import XCTest
@testable import VerbKit

final class VerbFormsPotentialTests: XCTestCase {
    private func baseForms() -> VerbForms {
        VerbForms(
            masuPos: "たべます", masuNeg: "たべません", masuPast: "たべました", masuPastNeg: "たべませんでした",
            te: "たべて", shortPos: "たべる", shortNeg: "たべない", shortPast: "たべた", shortPastNeg: "たべなかった"
        )
    }

    func testHasPotentialFormsIsFalseByDefault() {
        XCTAssertFalse(baseForms().hasPotentialForms)
    }

    func testHasPotentialFormsIsTrueWhenOnlyTheBaseFormIsSet() {
        var forms = baseForms()
        forms.potential = "たべられる"
        XCTAssertTrue(forms.hasPotentialForms)
    }

    func testHasPotentialFormsIsTrueWhenAnyConjugationIsSet() {
        var forms = baseForms()
        forms.potShortPastNeg = "たべられなかった"
        XCTAssertTrue(forms.hasPotentialForms)
    }

    func testDecodesSnakeCasePotentialKeys() throws {
        let json = """
        {
          "masu_pos": "a", "masu_neg": "b", "masu_past": "c", "masu_past_neg": "d",
          "te": "e", "short_pos": "f", "short_neg": "g", "short_past": "h", "short_past_neg": "i",
          "potential": "1", "pot_masu_pos": "2", "pot_masu_neg": "3", "pot_masu_past": "4",
          "pot_masu_past_neg": "5", "pot_te": "6", "pot_short_neg": "7", "pot_short_past": "8",
          "pot_short_past_neg": "9"
        }
        """
        let forms = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertEqual(
            [forms.potential, forms.potMasuPos, forms.potMasuNeg, forms.potMasuPast, forms.potMasuPastNeg,
             forms.potTe, forms.potShortNeg, forms.potShortPast, forms.potShortPastNeg],
            ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
        )
    }

    func testDataWithoutPotentialKeysStillDecodes() throws {
        let json = """
        {
          "masu_pos": "a", "masu_neg": "b", "masu_past": "c", "masu_past_neg": "d",
          "te": "e", "short_pos": "f", "short_neg": "g", "short_past": "h", "short_past_neg": "i"
        }
        """
        let forms = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertFalse(forms.hasPotentialForms)
    }

    func testEncodesSnakeCasePotentialKeys() throws {
        var forms = baseForms()
        forms.potMasuPos = "たべられます"
        forms.potShortPastNeg = "たべられなかった"
        let data = try JSONEncoder().encode(forms)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["pot_masu_pos"] as? String, "たべられます")
        XCTAssertEqual(object["pot_short_past_neg"] as? String, "たべられなかった")
        XCTAssertNil(object["pot_te"])
    }

    func testPotentialFieldsDoNotAffectHasNdForms() {
        var forms = baseForms()
        forms.potential = "たべられる"
        XCTAssertFalse(forms.hasNdForms)
    }
}
