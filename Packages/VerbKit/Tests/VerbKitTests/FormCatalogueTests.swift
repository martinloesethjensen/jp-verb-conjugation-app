import XCTest
@testable import VerbKit

final class FormCatalogueTests: XCTestCase {
    private let catalogue = FormCatalogue.bundled

    /// The quiz topic each catalogue family corresponds to.
    private let topicForFamily: [String: QuizTopic] = [
        "basic": .basic, "potential": .potential, "nd": .nDesu, "auxiliary": .auxiliaries,
        "other": .otherForms,
    ]

    func testBundledCatalogueLoads() {
        XCTAssertEqual(catalogue.schema, 1)
        XCTAssertEqual(catalogue.forms.count, 72)
        XCTAssertEqual(catalogue.families.map(\.id), ["basic", "potential", "nd", "auxiliary", "other"])
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

    func testEveryFormAppliesToVerbsAndThePlainFormsToEveryClass() {
        XCTAssertEqual(catalogue.specs(for: .verb).count, 72)
        let shared: [FormID] = ["te", "short_pos", "short_neg", "short_past", "short_past_neg"]
        for wordClass in [WordClass.iAdjective, .naAdjective, .noun] {
            XCTAssertEqual(catalogue.specs(for: wordClass).map(\.id), shared, wordClass.rawValue)
        }
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
        // たべる has every form but the short causative-passive, which only godan verbs have.
        XCTAssertEqual(catalogue.available(in: taberu.forms, for: .verb).count, 71)
        XCTAssertEqual(catalogue.available(in: aru.forms, for: .verb).count, 41)
        // ある has only some of the other forms: no passive, causative, imperative, なさい or 〜な.
        XCTAssertEqual(
            catalogue.available(in: aru.forms, for: .verb, family: "other").map { $0.spec.id.rawValue },
            ["volitional", "conditional_ba", "conditional_tara", "tai", "masu_volitional", "neg_te",
             "nakute", "te_mo_ii", "te_wa_ikenai", "te_cha_dame", "nakereba_naranai",
             "nakute_wa_ikenai", "nakya", "nakucha", "nakute_mo_ii", "conditional_to",
             "conditional_nara"]
        )
        XCTAssertTrue(catalogue.available(in: aru.forms, for: .verb, family: "potential").isEmpty)
        XCTAssertEqual(catalogue.available(in: taberu.forms, for: .verb, family: "nd").count, 8)
    }

    func testAvailableKeepsCatalogueOrder() throws {
        // のむ is a godan verb that is not a す-verb, so it has every form.
        let nomu = Word(try XCTUnwrap(try RealVerbs.load().first { $0.dict == "のむ" }))
        let ids = catalogue.available(in: nomu.forms, for: .verb).map { $0.spec.id }
        XCTAssertEqual(ids, catalogue.forms.map(\.id))
    }
}
