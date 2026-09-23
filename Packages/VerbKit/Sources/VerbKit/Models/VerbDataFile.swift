public struct VerbDataFile: Codable, Sendable {
    public var version: String
    public var description: String
    public var verbs: [Verb]

    public init(version: String, description: String, verbs: [Verb]) {
        self.version = version
        self.description = description
        self.verbs = verbs
    }
}
