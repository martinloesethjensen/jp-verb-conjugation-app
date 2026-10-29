import Foundation

/// A common chunk a verb is used in, in its dictionary form: `シャワーを浴びる`, "take a shower".
/// verbs.json gives each one a stable `id` for the review site; the app ignores it.
public struct VerbCollocation: Codable, Hashable, Sendable {
    public var jp: String
    public var en: String

    public init(jp: String, en: String) {
        self.jp = jp
        self.en = en
    }
}
