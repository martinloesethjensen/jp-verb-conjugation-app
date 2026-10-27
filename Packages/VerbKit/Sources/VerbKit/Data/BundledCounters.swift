import Foundation

/// The copy of `counters.json` that ships inside the app, so the Counters tab works on a first launch
/// with no network. `scripts/update_data.py` writes it (byte for byte, with `counters.manifest.json`
/// holding its version and hash); a synced copy replaces it only when it is not older.
public struct BundledCounters: Equatable, Sendable {
    public let file: CountersDataFile
    public let manifest: CountersManifest
    /// The file's bytes, which `manifest.sha256` covers.
    public let data: Data

    public init(file: CountersDataFile, manifest: CountersManifest, data: Data) {
        self.file = file
        self.manifest = manifest
        self.data = data
    }

    /// The bundled copy, or nil when a resource is missing, unreadable, or does not match its manifest.
    /// Never crashes: without it the app starts empty and waits for a sync, as it did before.
    public static func load() -> BundledCounters? {
        load(urlFor: { Bundle.module.url(forResource: $0, withExtension: "json") })
    }

    /// - Parameter urlFor: the URL of a `.json` resource by name (`counters`, `counters.manifest`).
    static func load(urlFor: (String) -> URL?) -> BundledCounters? {
        guard let dataURL = urlFor("counters"), let manifestURL = urlFor("counters.manifest"),
              let data = try? Data(contentsOf: dataURL),
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(CountersManifest.self, from: manifestData),
              sha256Hex(of: data) == manifest.sha256,
              let file = try? JSONDecoder().decode(CountersDataFile.self, from: data)
        else { return nil }
        return BundledCounters(file: file, manifest: manifest, data: data)
    }
}
