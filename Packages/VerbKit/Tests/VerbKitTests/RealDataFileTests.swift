import XCTest
@testable import VerbKit

/// Guards the real `data/verbs.json` and `data/manifest.json` this repo
/// publishes — the file every user's app actually fetches on first
/// launch — rather than the `Fixtures/verbs-fixture.json` every other
/// test in this package uses. A bad edit to the real data (malformed
/// JSON, or a manifest hash that no longer matches the file) would break
/// first launch for every user, and nothing else in this suite would
/// catch it.
final class RealDataFileTests: XCTestCase {
    /// Walks up from this source file to the repo root: this file lives
    /// at `Packages/VerbKit/Tests/VerbKitTests/RealDataFileTests.swift`,
    /// so five `deletingLastPathComponent()` calls (filename, then the
    /// four containing directories) land on the repo root, where the
    /// published `data/` directory lives.
    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }

    private var realVerbsURL: URL {
        repoRoot.appendingPathComponent("data/verbs.json")
    }

    private var realManifestURL: URL {
        repoRoot.appendingPathComponent("data/manifest.json")
    }

    func testRealManifestHashMatchesRealVerbsFile() throws {
        let verbsData = try Data(contentsOf: realVerbsURL)
        let manifestData = try Data(contentsOf: realManifestURL)
        let manifest = try JSONDecoder().decode(VerbManifest.self, from: manifestData)

        XCTAssertEqual(
            manifest.sha256,
            sha256Hex(of: verbsData),
            "data/manifest.json's sha256 no longer matches data/verbs.json — every user's first launch would fail hash verification"
        )
    }

    func testRealVerbsFileDecodesAsVerbDataFile() throws {
        let verbsData = try Data(contentsOf: realVerbsURL)
        let decoded = try JSONDecoder().decode(VerbDataFile.self, from: verbsData)

        XCTAssertFalse(decoded.verbs.isEmpty, "data/verbs.json decoded to zero verbs")
    }
}
