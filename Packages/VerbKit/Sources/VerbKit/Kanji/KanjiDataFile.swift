import Foundation

/// A decoded `data/kanji.json`.
public struct KanjiDataFile: Equatable, Sendable {
    /// The major format version this build reads. A file with a newer one is refused.
    public static let supportedSchema = 1

    public enum LoadError: Error, Equatable, Sendable {
        /// Not JSON, no `schema`, a key that is not one character, or an entry without strokes.
        case malformed
        /// The file's major schema is newer than `supportedSchema`.
        case unsupportedSchema(Int)
    }

    public var entries: [Character: KanjiEntry]

    public init(entries: [Character: KanjiEntry]) {
        self.entries = entries
    }

    private struct Header: Decodable { let schema: Int }

    private struct Raw: Decodable {
        struct Entry: Decodable {
            let strokes: [String]
            let grade: Int?
            let on: [String]?
            let kun: [String]?
            let meanings: [String]?
        }
        let kanji: [String: Entry]
    }

    public static func decode(_ data: Data) throws -> KanjiDataFile {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw LoadError.malformed }
        guard header.schema <= supportedSchema else { throw LoadError.unsupportedSchema(header.schema) }
        guard let raw = try? decoder.decode(Raw.self, from: data) else { throw LoadError.malformed }
        var entries: [Character: KanjiEntry] = [:]
        entries.reserveCapacity(raw.kanji.count)
        for (key, value) in raw.kanji {
            guard key.count == 1, let character = key.first, !value.strokes.isEmpty else { throw LoadError.malformed }
            entries[character] = KanjiEntry(
                character: character, strokes: value.strokes, grade: value.grade,
                on: value.on ?? [], kun: value.kun ?? [], meanings: value.meanings ?? []
            )
        }
        return KanjiDataFile(entries: entries)
    }
}
