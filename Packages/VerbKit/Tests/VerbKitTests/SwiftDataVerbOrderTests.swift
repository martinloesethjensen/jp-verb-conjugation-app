import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class SwiftDataVerbOrderTests: XCTestCase {
    func testLoadPreservesTheSourceOrder() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("data").appendingPathComponent("verbs.json")
        let verbs = try JSONDecoder().decode(VerbDataFile.self, from: Data(contentsOf: url)).verbs
        let container = try VerbModelContainer.makeInMemory()
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(container))

        try persisting.replaceAllVerbs(with: verbs)
        XCTAssertEqual(try persisting.loadAllVerbs().map(\.dict), verbs.map(\.dict))

        let reversed = Array(verbs.reversed())
        try persisting.replaceAllVerbs(with: reversed)
        XCTAssertEqual(try persisting.loadAllVerbs().map(\.dict), reversed.map(\.dict))
    }
}
