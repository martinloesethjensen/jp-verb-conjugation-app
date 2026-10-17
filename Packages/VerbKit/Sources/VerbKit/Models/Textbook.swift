/// A textbook whose lessons grammar points are taught in (Genki I, Genki II).
public struct Textbook: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var edition: String?
    /// The first lesson number. Genki II continues from Genki I, so it starts at 13.
    public var firstLesson: Int
    /// The last lesson number.
    public var lessons: Int

    public init(id: String, title: String, edition: String? = nil, firstLesson: Int = 1, lessons: Int) {
        self.id = id
        self.title = title
        self.edition = edition
        self.firstLesson = firstLesson
        self.lessons = lessons
    }

    enum CodingKeys: String, CodingKey {
        case id, title, edition
        case firstLesson = "first_lesson"
        case lessons
    }

    /// `edition` and `first_lesson` may be omitted from the JSON.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        edition = try c.decodeIfPresent(String.self, forKey: .edition)
        firstLesson = try c.decodeIfPresent(Int.self, forKey: .firstLesson) ?? 1
        lessons = try c.decode(Int.self, forKey: .lessons)
    }

    public func contains(lesson: Int) -> Bool {
        (firstLesson...lessons).contains(lesson)
    }
}

/// Where a grammar point is taught: a book's lesson, and whether that is a
/// review of something taught earlier.
public struct LessonRef: Codable, Hashable, Sendable {
    public var book: String
    public var lesson: Int
    public var reviewed: Bool

    public init(book: String, lesson: Int, reviewed: Bool) {
        self.book = book
        self.lesson = lesson
        self.reviewed = reviewed
    }
}
