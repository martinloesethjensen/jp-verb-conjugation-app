import XCTest
@testable import VerbKit

final class LeveledTests: XCTestCase {
    private struct Item: Leveled, Equatable {
        let id: Int
        let jlpt: JLPTLevel?
    }

    private let items = [
        Item(id: 1, jlpt: .n5), Item(id: 2, jlpt: nil), Item(id: 3, jlpt: .n4),
        Item(id: 4, jlpt: .n3), Item(id: 5, jlpt: .n4),
    ]

    func testVisibleKeepsNilAndOrder() {
        let s = LevelSettings(hidden: [.n4])
        XCTAssertEqual(items.visible(in: s).map(\.id), [1, 2, 4])
    }

    func testHiddenCount() {
        XCTAssertEqual(items.hiddenCount(in: LevelSettings(hidden: [.n4])), 2)
        XCTAssertEqual(items.hiddenCount(in: LevelSettings()), 0)
        XCTAssertEqual(items.hiddenCount(in: LevelSettings(hidden: [.n1])), 0)
    }

    func testLevelsSkipsNil() {
        XCTAssertEqual(items.levels(), [.n5, .n4, .n3])
    }

    func testVerbAndGrammarPointAreLeveled() {
        let _: any Leveled.Type = Verb.self
        let _: any Leveled.Type = GrammarPoint.self
    }
}
