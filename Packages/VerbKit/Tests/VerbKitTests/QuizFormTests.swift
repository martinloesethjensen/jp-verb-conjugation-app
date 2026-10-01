import XCTest
@testable import VerbKit

final class QuizFormTests: XCTestCase {
    private func verb(_ dict: String) throws -> Verb {
        try XCTUnwrap(try RealVerbs.load().first { $0.dict == dict }, dict)
    }

    func testCatalogueHasFortyEightFormsWithUniqueIds() {
        XCTAssertEqual(QuizForm.all.count, 48)
        XCTAssertEqual(Set(QuizForm.all.map(\.id)).count, 48)
        XCTAssertEqual(Set(QuizForm.all.map(\.label)).count, 48, "labels must be unique so identify has one answer")
    }

    func testTopicSizes() {
        func count(_ topic: QuizTopic) -> Int { QuizForm.all.filter { $0.topic == topic }.count }
        XCTAssertEqual(count(.basic), 9)
        XCTAssertEqual(count(.potential), 9)
        XCTAssertEqual(count(.nDesu), 8)
        XCTAssertEqual(count(.auxiliaries), 22)
    }

    func testLabelsFollowTheParts() {
        func label(_ id: String) -> String? { QuizForm.all.first { $0.id == id }?.label }
        XCTAssertEqual(label("te"), "て-form")
        XCTAssertEqual(label("short_pos"), "Plain")
        XCTAssertEqual(label("short_neg"), "Plain · negative")
        XCTAssertEqual(label("masu_past_neg"), "Polite · past · negative")
        XCTAssertEqual(label("potential"), "Potential · plain")
        XCTAssertEqual(label("pot_masu_past"), "Potential · polite · past")
        XCTAssertEqual(label("pot_te"), "Potential · て-form")
        XCTAssertEqual(label("nd_casual_past"), "んです · casual · past")
        XCTAssertEqual(label("nd_past_neg"), "んです · polite · past · negative")
        XCTAssertEqual(label("teiru_masu_neg"), "ている · polite · negative")
        XCTAssertEqual(label("teiru_te"), "ている · て-form")
        XCTAssertEqual(label("teshimau_polite"), "てしまう · polite")
        XCTAssertEqual(label("teoku"), "ておく · plain")
        XCTAssertEqual(label("nagara"), "ながら")
    }

    func testValueReadsTheRightField() throws {
        let taberu = try verb("たべる")
        let byId = Dictionary(uniqueKeysWithValues: QuizForm.all.map { ($0.id, $0) })
        XCTAssertEqual(byId["masu_pos"]?.value(in: taberu.forms), "たべます")
        XCTAssertEqual(byId["pot_masu_past"]?.value(in: taberu.forms), "たべられました")
        XCTAssertEqual(byId["nd_casual_neg"]?.value(in: taberu.forms), "たべないんだ")
        XCTAssertEqual(byId["teiru_masu_past_neg"]?.value(in: taberu.forms), "たべていませんでした")
        XCTAssertEqual(byId["nagara"]?.value(in: taberu.forms), "たべながら")
    }

    func testEveryFormTheDataPopulatesIsInTheCatalogueExactlyOnce() throws {
        var populated = Set<String>()
        for verb in try RealVerbs.load() {
            let data = try JSONEncoder().encode(verb.forms)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            populated.formUnion(object.keys)
        }
        XCTAssertEqual(populated, Set(QuizForm.all.map(\.id)))
    }

    func testAvailableSkipsFormsAVerbLacks() throws {
        let aru = try verb("ある")
        let all = QuizForm.available(in: aru.forms, topics: Set(QuizTopic.allCases))
        XCTAssertEqual(all.count, 24)
        XCTAssertTrue(all.allSatisfy { !$0.value.isEmpty })
        XCTAssertFalse(all.contains { $0.form.topic == .potential })
        let taberu = try verb("たべる")
        XCTAssertEqual(QuizForm.available(in: taberu.forms, topics: Set(QuizTopic.allCases)).count, 48)
        XCTAssertEqual(QuizForm.available(in: taberu.forms, topics: [.nDesu]).count, 8)
    }

    func testTopicChoicesCountFormsAndHideEmptyTopics() throws {
        let aru = try verb("ある")
        let choices = QuizTopic.choices(for: [aru])
        XCTAssertFalse(choices.contains { $0.topic == .potential })
        XCTAssertEqual(choices.first { $0.topic == .basic }?.count, 9)
        let all = QuizTopic.choices(for: try RealVerbs.load())
        XCTAssertEqual(all.map(\.topic), QuizTopic.allCases)
        XCTAssertEqual(all.first { $0.topic == .basic }?.count, 25 * 9)
    }
}
