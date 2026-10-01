import XCTest
@testable import VerbKit

final class VerbFormsAuxiliaryTests: XCTestCase {
    private func baseForms() -> VerbForms {
        VerbForms(
            masuPos: "たべます", masuNeg: "たべません", masuPast: "たべました", masuPastNeg: "たべませんでした",
            te: "たべて", shortPos: "たべる", shortNeg: "たべない", shortPast: "たべた", shortPastNeg: "たべなかった"
        )
    }

    private let baseJSON = """
    "masu_pos": "a", "masu_neg": "b", "masu_past": "c", "masu_past_neg": "d",
    "te": "e", "short_pos": "f", "short_neg": "g", "short_past": "h", "short_past_neg": "i"
    """

    func testHasAuxiliaryFormsIsFalseByDefault() {
        XCTAssertFalse(baseForms().hasAuxiliaryForms)
    }

    func testHasAuxiliaryFormsIsTrueWhenOnlyTheStemFormsAreSet() {
        var forms = baseForms()
        forms.nagara = "たべながら"
        XCTAssertTrue(forms.hasAuxiliaryForms)
    }

    func testHasAuxiliaryFormsIsTrueWhenAnyTeiruFormIsSet() {
        var forms = baseForms()
        forms.teiruMasuPastNeg = "たべていませんでした"
        XCTAssertTrue(forms.hasAuxiliaryForms)
    }

    func testDecodesAllTwentyTwoSnakeCaseKeys() throws {
        let json = """
        {
          \(baseJSON),
          "teiru": "1", "teiru_neg": "2", "teiru_past": "3", "teiru_past_neg": "4",
          "teiru_masu_pos": "5", "teiru_masu_neg": "6", "teiru_masu_past": "7",
          "teiru_masu_past_neg": "8", "teiru_te": "9",
          "teshimau": "10", "teshimau_polite": "11", "teoku": "12", "teoku_polite": "13",
          "temiru": "14", "temiru_polite": "15",
          "sugiru": "16", "sugiru_polite": "17", "yasui": "18", "yasui_polite": "19",
          "nikui": "20", "nikui_polite": "21", "nagara": "22"
        }
        """
        let f = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertEqual(
            [f.teiru, f.teiruNeg, f.teiruPast, f.teiruPastNeg, f.teiruMasuPos, f.teiruMasuNeg,
             f.teiruMasuPast, f.teiruMasuPastNeg, f.teiruTe, f.teshimau, f.teshimauPolite,
             f.teoku, f.teokuPolite, f.temiru, f.temiruPolite, f.sugiru, f.sugiruPolite,
             f.yasui, f.yasuiPolite, f.nikui, f.nikuiPolite, f.nagara],
            (1...22).map(String.init)
        )
    }

    func testDataWithoutAuxiliaryKeysStillDecodes() throws {
        let json = "{ \(baseJSON) }"
        let forms = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertFalse(forms.hasAuxiliaryForms)
    }

    func testAnExcludedVerbCanHaveOnlyTheStemForms() throws {
        let json = "{ \(baseJSON), \"sugiru\": \"x\", \"nagara\": \"y\" }"
        let forms = try JSONDecoder().decode(VerbForms.self, from: Data(json.utf8))
        XCTAssertTrue(forms.hasAuxiliaryForms)
        XCTAssertNil(forms.teiru)
        XCTAssertNil(forms.teshimau)
    }

    func testEncodesSnakeCaseAuxiliaryKeys() throws {
        var forms = baseForms()
        forms.teiruMasuPastNeg = "たべていませんでした"
        forms.yasuiPolite = "たべやすいです"
        let data = try JSONEncoder().encode(forms)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["teiru_masu_past_neg"] as? String, "たべていませんでした")
        XCTAssertEqual(object["yasui_polite"] as? String, "たべやすいです")
        XCTAssertNil(object["teiru"])
    }
}
