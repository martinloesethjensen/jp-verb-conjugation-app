import Foundation
@testable import VerbKit

/// A small, valid furigana file shared by the furigana sync, persistence and
/// store tests.
enum FuriganaFixture {
    static let json = """
    {
      "version": "test-fixture",
      "description": "Fixture for furigana tests.",
      "readings": { "食": "た", "来": "く", "来ら": "こ", "日本語": "にほんご" }
    }
    """

    static var data: Data { Data(json.utf8) }

    static var dictionary: FuriganaDictionary {
        // Force-try is fine: the fixture is a compile-time constant.
        FuriganaDictionary(file: try! JSONDecoder().decode(FuriganaDataFile.self, from: data))
    }
}
