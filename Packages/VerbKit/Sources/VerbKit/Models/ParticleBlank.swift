/// A particle in an example sentence that the particle quiz may blank (`particle_blanks` in
/// grammar.json and verbs.json). Only marked blanks are ever asked: a person chose each one as
/// unambiguous. See docs/superpowers/specs/2026-10-29-particle-blanks-design.md.
public struct ParticleBlank: Codable, Hashable, Sendable {
    /// The particle at `at` ("に", "から").
    public var particle: String
    /// Where the particle starts in the example's `jp`, counted in Unicode code points (not
    /// UTF-16 units or grapheme clusters), from 0.
    public var at: Int
    /// Other particles that are just as right here (が and を with the potential). They are never
    /// offered as wrong choices, and the feedback names them.
    public var acceptAlso: [String]

    public init(particle: String, at: Int, acceptAlso: [String] = []) {
        self.particle = particle
        self.at = at
        self.acceptAlso = acceptAlso
    }

    enum CodingKeys: String, CodingKey {
        case particle, at
        case acceptAlso = "accept_also"
    }

    /// `accept_also` may be omitted from the JSON.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        particle = try c.decode(String.self, forKey: .particle)
        at = try c.decode(Int.self, forKey: .at)
        acceptAlso = try c.decodeIfPresent([String].self, forKey: .acceptAlso) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(particle, forKey: .particle)
        try c.encode(at, forKey: .at)
        if !acceptAlso.isEmpty { try c.encode(acceptAlso, forKey: .acceptAlso) }
    }

    /// The sentence split around the blank, or nil when `particle` is not at `at` in `sentence`
    /// (data that drifted; the generator checks this, the app double-checks).
    public func split(_ sentence: String) -> (before: String, after: String)? {
        let scalars = Array(sentence.unicodeScalars)
        let particleScalars = Array(particle.unicodeScalars)
        guard at > 0, !particleScalars.isEmpty, at + particleScalars.count <= scalars.count,
              Array(scalars[at..<(at + particleScalars.count)]) == particleScalars else { return nil }
        var before = String.UnicodeScalarView(), after = String.UnicodeScalarView()
        before.append(contentsOf: scalars[..<at])
        after.append(contentsOf: scalars[(at + particleScalars.count)...])
        return (String(before), String(after))
    }
}

/// Decodes and encodes the optional `particle_blanks` key of an example.
extension KeyedDecodingContainer {
    func decodeBlanks(forKey key: Key) throws -> [ParticleBlank] {
        try decodeIfPresent([ParticleBlank].self, forKey: key) ?? []
    }
}

extension KeyedEncodingContainer {
    mutating func encodeBlanks(_ blanks: [ParticleBlank], forKey key: Key) throws {
        if !blanks.isEmpty { try encode(blanks, forKey: key) }
    }
}
