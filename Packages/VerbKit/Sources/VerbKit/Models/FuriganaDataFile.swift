/// The published `furigana.json`: a central dictionary from kanji to reading.
///
/// A key is a run of kanji optionally followed by up to three kana that
/// select a reading (`来ら` → こ, `来た` → き); the value is the hiragana
/// reading of the kanji part only.
public struct FuriganaDataFile: Codable, Equatable, Sendable {
    public var version: String
    public var description: String
    public var readings: [String: String]

    public init(version: String, description: String, readings: [String: String]) {
        self.version = version
        self.description = description
        self.readings = readings
    }
}
