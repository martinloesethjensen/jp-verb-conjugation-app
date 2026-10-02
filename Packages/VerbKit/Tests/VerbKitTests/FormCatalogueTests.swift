import XCTest
@testable import VerbKit

final class FormCatalogueTests: XCTestCase {
    private let catalogue = FormCatalogue.bundled

    /// The quiz topic each catalogue family corresponds to.
    private let topicForFamily: [String: QuizTopic] = [
        "basic": .basic, "potential": .potential, "nd": .nDesu, "auxiliary": .auxiliaries,
    ]

    func testBundledCatalogueLoads() {
        XCTAssertEqual(catalogue.schema, 1)
        XCTAssertEqual(catalogue.forms.count, 48)
        XCTAssertEqual(catalogue.families.map(\.id), ["basic", "potential", "nd", "auxiliary"])
    }

    func testIdsAreUniqueAndLookupFindsThem() {
        XCTAssertEqual(Set(catalogue.forms.map(\.id)).count, catalogue.forms.count)
        for form in catalogue.forms {
            XCTAssertEqual(catalogue.spec(for: form.id), form)
        }
        XCTAssertNil(catalogue.spec(for: "no_such_form"))
    }

    func testEveryFormBelongsToAFamily() {
        let families = Set(catalogue.families.map(\.id))
        XCTAssertTrue(catalogue.forms.allSatisfy { families.contains($0.family) })
    }

    func testAllFormsApplyToVerbsForNow() {
        XCTAssertEqual(catalogue.specs(for: .verb).count, 48)
        XCTAssertTrue(catalogue.specs(for: .iAdjective).isEmpty)
    }

    func testTheNineAuthoredFormsAreTheOnesSearchMatches() {
        let authored = catalogue.forms.filter { $0.source == .authored }.map(\.id)
        let searchable = catalogue.forms.filter(\.search).map(\.id)
        XCTAssertEqual(authored, FormKey.allCases.map { FormID(rawValue: $0.rawValue) })
        XCTAssertEqual(searchable, authored)
    }

    // The quiz still has its own table of forms. Until it reads the catalogue,
    // the two must agree; delete these when `QuizForm.all` goes.

    func testMatchesTheQuizFormsInIdLabelAndTopic() {
        XCTAssertEqual(Set(catalogue.forms.map(\.id.rawValue)), Set(QuizForm.all.map(\.id)))
        for quiz in QuizForm.all {
            let spec = catalogue.spec(for: FormID(rawValue: quiz.id))
            XCTAssertNotNil(spec, quiz.id)
            XCTAssertEqual(spec?.label, quiz.label, quiz.id)
            XCTAssertEqual(spec.flatMap { topicForFamily[$0.family] }, quiz.topic, quiz.id)
        }
    }

    func testFamilyTitlesMatchTheQuizTopics() {
        for family in catalogue.families {
            XCTAssertEqual(family.title, topicForFamily[family.id]?.title, family.id)
        }
    }

    func testAvailableSkipsFormsAWordLacks() throws {
        let aru = Word(try XCTUnwrap(try RealVerbs.load().first { $0.dict == "ある" }))
        let taberu = Word(try XCTUnwrap(try RealVerbs.load().first { $0.dict == "たべる" }))
        XCTAssertEqual(catalogue.available(in: taberu.forms, for: .verb).count, 48)
        XCTAssertEqual(catalogue.available(in: aru.forms, for: .verb).count, 24)
        XCTAssertTrue(catalogue.available(in: aru.forms, for: .verb, family: "potential").isEmpty)
        XCTAssertEqual(catalogue.available(in: taberu.forms, for: .verb, family: "nd").count, 8)
    }

    func testAvailableKeepsCatalogueOrder() throws {
        let taberu = Word(try XCTUnwrap(try RealVerbs.load().first { $0.dict == "たべる" }))
        let ids = catalogue.available(in: taberu.forms, for: .verb).map { $0.spec.id }
        XCTAssertEqual(ids, catalogue.forms.map(\.id))
    }
}
