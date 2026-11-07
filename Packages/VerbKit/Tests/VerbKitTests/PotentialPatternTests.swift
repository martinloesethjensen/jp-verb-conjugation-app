import XCTest
@testable import VerbKit

final class PotentialPatternTests: XCTestCase {
    private static var verbs: [Verb] = []

    override class func setUp() {
        super.setUp()
        verbs = (try? RealVerbs.load()) ?? []
    }

    private func verb(_ id: String) throws -> Verb {
        try XCTUnwrap(Self.verbs.first { $0.id == id })
    }

    func testRuVerb() throws { XCTAssertEqual(PotentialPattern(verb: try verb("たべる")), .ru) }
    func testUVerb() throws { XCTAssertEqual(PotentialPattern(verb: try verb("のむ")), .u) }
    func testSuru() throws { XCTAssertEqual(PotentialPattern(verb: try verb("する")), .suru) }
    func testKuru() throws { XCTAssertEqual(PotentialPattern(verb: try verb("くる")), .kuru) }

    func testSuruCompound() {
        var forms = VerbForms(masuPos: "x", masuNeg: "x", masuPast: "x", masuPastNeg: "x", te: "x",
                              shortPos: "べんきょうする", shortNeg: "x", shortPast: "x", shortPastNeg: "x")
        forms.potential = "べんきょうできる"
        let benkyou = Verb(type: .irregular, label: "", dict: "べんきょうする", kanji: "勉強する",
                           meaning: "", description: "", forms: forms, examples: [])
        XCTAssertEqual(PotentialPattern(verb: benkyou), .suru)
    }

    /// ある has no potential form, so the Potential page explains nothing.
    func testNoPatternWithoutPotential() throws {
        XCTAssertNil(PotentialPattern(verb: try verb("ある")))
    }
}
