import Foundation

/// A copy of one data file that ships inside the app, with the version and hash of its manifest entry.
/// `scripts/update_data.py` writes the copy (byte for byte) and its `<name>.manifest.json` sidecar. A store
/// installs it into the persisted data when it is newer than anything the device has, so a first launch
/// with no network still has every file.
public struct BundledData<Value: Decodable & Sendable>: Sendable {
    public let value: Value
    public let version: String
    public let sha256: String
    /// The file's bytes, which `sha256` covers.
    public let data: Data

    public init(value: Value, version: String, sha256: String, data: Data) {
        self.value = value
        self.version = version
        self.sha256 = sha256
        self.data = data
    }

    private struct Sidecar: Decodable {
        var version: String
        var sha256: String
    }

    /// The bundled `<name>.json`, or nil when it or its sidecar is missing, unreadable, or does not match
    /// its hash. Never crashes: without a bundle the app behaves as it did before bundles existed.
    public static func load(named name: String) -> BundledData? {
        load(named: name, urlFor: { Bundle.module.url(forResource: $0, withExtension: "json") })
    }

    /// - Parameter urlFor: the URL of a `.json` resource by name (`counters`, `counters.manifest`).
    static func load(named name: String, urlFor: (String) -> URL?) -> BundledData? {
        guard let dataURL = urlFor(name), let sidecarURL = urlFor(name + ".manifest"),
              let data = try? Data(contentsOf: dataURL),
              let sidecarData = try? Data(contentsOf: sidecarURL),
              let sidecar = try? JSONDecoder().decode(Sidecar.self, from: sidecarData),
              sha256Hex(of: data) == sidecar.sha256,
              let value = try? JSONDecoder().decode(Value.self, from: data)
        else { return nil }
        return BundledData(value: value, version: sidecar.version, sha256: sidecar.sha256, data: data)
    }
}
