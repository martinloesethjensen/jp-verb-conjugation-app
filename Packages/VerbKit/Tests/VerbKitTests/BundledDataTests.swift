import XCTest
@testable import VerbKit

final class BundledDataTests: XCTestCase {
    private func folder(name: String = "counters", data: String?, sidecar: String?) throws -> (String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        if let data { try Data(data.utf8).write(to: dir.appendingPathComponent("\(name).json")) }
        if let sidecar { try Data(sidecar.utf8).write(to: dir.appendingPathComponent("\(name).manifest.json")) }
        return { resource in
            let url = dir.appendingPathComponent(resource + ".json")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private let tiny = #"{"version": "1.0.0", "description": "d", "counters": []}"#

    private func sidecar(version: String = "1.0.0", for text: String) -> String {
        #"{"version": "\#(version)", "sha256": "\#(sha256Hex(of: Data(text.utf8)))"}"#
    }

    func testAMatchingPairLoads() throws {
        let urls = try folder(data: tiny, sidecar: sidecar(version: "2.3.0", for: tiny))
        let bundled = try XCTUnwrap(BundledData<CountersDataFile>.load(named: "counters", urlFor: urls))
        XCTAssertEqual(bundled.version, "2.3.0")
        XCTAssertEqual(bundled.sha256, sha256Hex(of: Data(tiny.utf8)))
        XCTAssertEqual(bundled.data, Data(tiny.utf8))
        XCTAssertTrue(bundled.value.counters.isEmpty)
    }

    func testAMissingResourceIsNil() throws {
        XCTAssertNil(BundledData<CountersDataFile>.load(named: "counters", urlFor: try folder(data: nil, sidecar: nil)))
        XCTAssertNil(BundledData<CountersDataFile>.load(named: "counters", urlFor: try folder(data: tiny, sidecar: nil)))
        XCTAssertNil(BundledData<CountersDataFile>.load(
            named: "counters", urlFor: try folder(data: nil, sidecar: sidecar(for: tiny))))
    }

    func testAnUnreadableFileOrSidecarIsNil() throws {
        XCTAssertNil(BundledData<CountersDataFile>.load(
            named: "counters", urlFor: try folder(data: "{", sidecar: sidecar(for: "{"))))
        XCTAssertNil(BundledData<CountersDataFile>.load(
            named: "counters", urlFor: try folder(data: tiny, sidecar: "not json")))
    }

    func testACopyThatDoesNotMatchItsSidecarIsNil() throws {
        let wrong = #"{"version": "1.0.0", "sha256": "0000"}"#
        XCTAssertNil(BundledData<CountersDataFile>.load(named: "counters", urlFor: try folder(data: tiny, sidecar: wrong)))
    }

    func testTheNameSelectsTheResource() throws {
        let urls = try folder(name: "words", data: #"{"version": "1.0.0", "description": "d", "words": []}"#,
                              sidecar: sidecar(for: #"{"version": "1.0.0", "description": "d", "words": []}"#))
        XCTAssertNotNil(BundledData<WordsDataFile>.load(named: "words", urlFor: urls))
        XCTAssertNil(BundledData<WordsDataFile>.load(named: "grammar", urlFor: urls))
    }
}
