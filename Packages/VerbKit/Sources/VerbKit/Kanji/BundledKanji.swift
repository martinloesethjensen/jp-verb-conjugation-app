import Foundation

/// The kanji file the app ships with: its exact bytes and the version and hash of its manifest entry
/// (`kanji.manifest.json`, written by `scripts/update_data.py`). Kept as bytes, not decoded, so the
/// 2.4 MB file is decoded once, off the main actor, by `KanjiStore`.
public struct BundledKanji: Sendable {
    public let data: Data
    public let version: String
    public let sha256: String

    public init(data: Data, version: String, sha256: String) {
        self.data = data
        self.version = version
        self.sha256 = sha256
    }

    private struct Sidecar: Decodable {
        var version: String
        var sha256: String
    }

    /// The bundled copy, or nil when it or its sidecar is missing, unreadable or does not match its hash.
    public static func load() -> BundledKanji? {
        guard let dataURL = Bundle.module.url(forResource: "kanji", withExtension: "json"),
              let sidecarURL = Bundle.module.url(forResource: "kanji.manifest", withExtension: "json"),
              let data = try? Data(contentsOf: dataURL),
              let sidecar = try? JSONDecoder().decode(Sidecar.self, from: Data(contentsOf: sidecarURL)),
              sha256Hex(of: data) == sidecar.sha256
        else { return nil }
        return BundledKanji(data: data, version: sidecar.version, sha256: sidecar.sha256)
    }
}
