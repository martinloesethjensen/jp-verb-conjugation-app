import Foundation

/// One dialect the tag picker can suggest. Read-only bundled data: a tag only
/// exists once the user creates one from a record (keeping its `id`).
public struct DialectRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    /// 熊本弁
    public var name: String
    /// くまもとべん
    public var kana: String
    /// Kumamoto-ben
    public var romaji: String
    /// Other names for the same dialect (飛騨弁 ↔ 高山弁), in kanji, kana or romaji.
    public var aliases: [String]
    /// Every prefecture it is spoken in; several for 関西弁 or 東北弁.
    public var prefectures: [Prefecture]
    public var region: Region
}

/// The bundled `dialects.json`: at least one dialect per prefecture, plus the
/// well-known ones within them.
public struct DialectCatalogue: Sendable {
    public let dialects: [DialectRecord]

    private struct Document: Decodable {
        var schema: Int
        var dialects: [DialectRecord]
    }

    public init(data: Data) throws {
        dialects = try JSONDecoder().decode(Document.self, from: data).dialects
    }

    public init(dialects: [DialectRecord]) {
        self.dialects = dialects
    }

    /// The catalogue bundled with the app. A missing or malformed resource is a
    /// build error, not a runtime condition, so it stops the app.
    public static let bundled: DialectCatalogue = {
        guard let url = Bundle.module.url(forResource: "dialects", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalogue = try? DialectCatalogue(data: data)
        else {
            fatalError("VerbKit's bundled dialects.json is missing or malformed")
        }
        return catalogue
    }()

    /// Dialects spoken in `prefecture`, in catalogue order.
    public func dialects(in prefecture: Prefecture) -> [DialectRecord] {
        dialects.filter { $0.prefectures.contains(prefecture) }
    }

    public func dialects(in region: Region) -> [DialectRecord] {
        dialects.filter { $0.region == region }
    }
}
