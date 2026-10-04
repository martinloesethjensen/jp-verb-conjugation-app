import XCTest
@testable import VerbKit

final class FolderTreeTests: XCTestCase {
    private let trip = WordBankFolderValue(name: "Trip 2026", sortOrder: 0)
    private lazy var takayama = WordBankFolderValue(name: "Takayama", parentID: trip.id, sortOrder: 1)
    private lazy var kyoto = WordBankFolderValue(name: "Kyoto", parentID: trip.id, sortOrder: 0)
    private lazy var market = WordBankFolderValue(name: "Morning market", parentID: takayama.id)
    private let friends = WordBankFolderValue(name: "Friends", sortOrder: 0)

    private var tree: FolderTree { FolderTree([market, takayama, trip, friends, kyoto]) }

    func testChildrenAreOrderedBySortOrderThenName() {
        XCTAssertEqual(tree.children(of: nil).map(\.name), ["Friends", "Trip 2026"])
        XCTAssertEqual(tree.children(of: trip.id).map(\.name), ["Kyoto", "Takayama"])
        XCTAssertEqual(tree.children(of: market.id), [])
    }

    func testPathIsRootFirst() {
        XCTAssertEqual(tree.path(of: market.id).map(\.name), ["Trip 2026", "Takayama", "Morning market"])
        XCTAssertEqual(tree.path(of: friends.id).map(\.name), ["Friends"])
    }

    func testDescendantsExcludeTheFolderItself() {
        XCTAssertEqual(tree.descendants(of: trip.id), [takayama.id, kyoto.id, market.id])
        XCTAssertEqual(tree.descendants(of: market.id), [])
    }

    func testAFolderCannotMoveIntoItselfOrADescendant() {
        XCTAssertFalse(tree.canMove(trip.id, to: trip.id))
        XCTAssertFalse(tree.canMove(trip.id, to: market.id))
        XCTAssertTrue(tree.canMove(market.id, to: nil))
        XCTAssertTrue(tree.canMove(market.id, to: friends.id))
        XCTAssertFalse(tree.canMove(market.id, to: UUID()), "unknown parent")
    }

    func testSiblingNamesCompareNormalised() {
        XCTAssertFalse(tree.nameIsFree("ｋｙｏｔｏ", in: trip.id))
        XCTAssertFalse(tree.nameIsFree(" kyoto ", in: trip.id))
        XCTAssertTrue(tree.nameIsFree("Kyoto", in: nil), "a different parent")
        XCTAssertTrue(tree.nameIsFree("Kyoto", in: trip.id, ignoring: kyoto.id), "renaming itself")
    }

    func testPathSurvivesACycleInBadData() {
        let a = UUID(), b = UUID()
        let looped = FolderTree([
            WordBankFolderValue(id: a, name: "A", parentID: b),
            WordBankFolderValue(id: b, name: "B", parentID: a),
        ])
        XCTAssertLessThanOrEqual(looped.path(of: a).count, 2)
    }
}
