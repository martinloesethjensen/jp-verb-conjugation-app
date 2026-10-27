import XCTest
@testable import VerbKit

final class BundledCountersTests: XCTestCase {
    private func folder(data: String?, manifest: String?) throws -> (String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        if let data { try Data(data.utf8).write(to: dir.appendingPathComponent("counters.json")) }
        if let manifest { try Data(manifest.utf8).write(to: dir.appendingPathComponent("counters.manifest.json")) }
        return { name in
            let url = dir.appendingPathComponent(name + ".json")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private let tiny = #"{"version": "1.0.0", "description": "d", "counters": []}"#

    func testTheBundledCopyLoads() throws {
        let bundled = try XCTUnwrap(BundledCounters.load())
        XCTAssertGreaterThanOrEqual(bundled.file.counters.count, 29)
        XCTAssertFalse(bundled.manifest.version.isEmpty)
        XCTAssertEqual(sha256Hex(of: bundled.data), bundled.manifest.sha256)
    }

    func testAMissingResourceIsNil() throws {
        XCTAssertNil(BundledCounters.load(urlFor: try folder(data: nil, manifest: nil)))
        let manifest = #"{"version": "1.0.0", "sha256": "x"}"#
        XCTAssertNil(BundledCounters.load(urlFor: try folder(data: tiny, manifest: nil)))
        XCTAssertNil(BundledCounters.load(urlFor: try folder(data: nil, manifest: manifest)))
    }

    func testAnUnreadableFileIsNil() throws {
        let manifest = #"{"version": "1.0.0", "sha256": "\#(sha256Hex(of: Data("{".utf8)))"}"#
        XCTAssertNil(BundledCounters.load(urlFor: try folder(data: "{", manifest: manifest)))
        XCTAssertNil(BundledCounters.load(urlFor: try folder(data: tiny, manifest: "not json")))
    }

    func testACopyThatDoesNotMatchItsManifestIsNil() throws {
        let manifest = #"{"version": "1.0.0", "sha256": "0000"}"#
        XCTAssertNil(BundledCounters.load(urlFor: try folder(data: tiny, manifest: manifest)))
    }

    func testAMatchingCopyLoads() throws {
        let manifest = #"{"version": "2.3.0", "sha256": "\#(sha256Hex(of: Data(tiny.utf8)))"}"#
        let bundled = try XCTUnwrap(BundledCounters.load(urlFor: try folder(data: tiny, manifest: manifest)))
        XCTAssertEqual(bundled.manifest.version, "2.3.0")
        XCTAssertTrue(bundled.file.counters.isEmpty)
    }
}
