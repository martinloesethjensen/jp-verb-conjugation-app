/// An example sentence for a verb, tagged with the form it shows. The tag is a `FormID`, so an
/// example may show any form in the catalogue (`tai`, `teiru`), not only the nine `FormKey`
/// forms; an id this build does not know still decodes, and the view falls back to the id.
public struct VerbExample: Codable, Hashable, Sendable {
    /// The example's stable id from the data ("8iij9b"); nil in older data and in previews.
    public var id: String?
    public var form: FormID
    public var jp: String
    public var en: String
    /// Particles the particle quiz may blank. Empty for most examples.
    public var particleBlanks: [ParticleBlank]
    /// This example's own review stamp; nil until a person has read it.
    public var review: ReviewStamp?

    public init(id: String? = nil, form: FormID, jp: String, en: String, particleBlanks: [ParticleBlank] = [],
                review: ReviewStamp? = nil) {
        self.id = id
        self.form = form
        self.jp = jp
        self.en = en
        self.particleBlanks = particleBlanks
        self.review = review
    }

    enum CodingKeys: String, CodingKey {
        case id, form, jp, en, review
        case particleBlanks = "particle_blanks"
    }

    /// `id`, `particle_blanks` and `review` may be omitted from the JSON.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        form = try c.decode(FormID.self, forKey: .form)
        jp = try c.decode(String.self, forKey: .jp)
        en = try c.decode(String.self, forKey: .en)
        particleBlanks = try c.decodeBlanks(forKey: .particleBlanks)
        review = try c.decodeIfPresent(ReviewStamp.self, forKey: .review)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(form, forKey: .form)
        try c.encode(jp, forKey: .jp)
        try c.encode(en, forKey: .en)
        try c.encodeBlanks(particleBlanks, forKey: .particleBlanks)
        try c.encodeIfPresent(review, forKey: .review)
    }
}
