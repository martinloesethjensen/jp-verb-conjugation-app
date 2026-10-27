import XCTest
@testable import VerbKit

/// The app's bundled copies must be the repo's data files, byte for byte, with the version and hash of
/// the manifest's entry: `scripts/update_data.py` writes them and CI checks them, and this checks the
/// built resources too.
final class RealBundledDataTests: XCTestCase {
    private var data: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("data")
    }

    private struct Anything: Decodable, Sendable {}

    private func manifestEntry(_ name: String) throws -> (version: String, sha256: String) {
        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: data.appendingPathComponent("manifest.json"))
        ) as? [String: Any] ?? [:]
        let entry = name == "verbs" ? manifest : (manifest[name] as? [String: Any] ?? [:])
        return (entry["version"] as? String ?? "", entry["sha256"] as? String ?? "")
    }

    private func check<Value: Decodable & Sendable>(_ name: String, as type: Value.Type) throws {
        let bundled = try XCTUnwrap(BundledData<Value>.load(named: name), name)
        XCTAssertEqual(bundled.data, try Data(contentsOf: data.appendingPathComponent("\(name).json")), name)
        let entry = try manifestEntry(name)
        XCTAssertEqual(bundled.version, entry.version, name)
        XCTAssertEqual(bundled.sha256, entry.sha256, name)
    }

    func testEverySixBundledCopyEqualsItsDataFile() throws {
        try check("verbs", as: VerbDataFile.self)
        try check("grammar", as: GrammarDataFile.self)
        try check("furigana", as: FuriganaDataFile.self)
        try check("words", as: WordsDataFile.self)
        try check("counters", as: CountersDataFile.self)
        try check("forms", as: Anything.self)
    }
}
