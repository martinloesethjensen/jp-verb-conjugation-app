import CryptoKit
import Foundation

/// A textbook lesson, such as Genki I lesson 12.
public struct LessonKey: Codable, Hashable, Sendable {
    public var book: String
    public var lesson: Int

    public init(book: String, lesson: Int) {
        self.book = book
        self.lesson = lesson
    }
}

/// One stored lesson of My course: a custom lesson (`base == nil`) or the user's edits over a
/// textbook lesson. Base-linked lessons store only edits, so mapping changes in the data still apply.
public struct CourseLessonEdit: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var base: LessonKey?
    /// Ids added on top of the base lesson (or, for a custom lesson, all of its ids).
    public var added: [String]
    /// Base ids the user took out.
    public var removed: [String]
    /// Ids that come first, in this order; the rest keep their order.
    public var order: [String]

    public init(id: UUID = UUID(), name: String, base: LessonKey? = nil,
                added: [String] = [], removed: [String] = [], order: [String] = []) {
        self.id = id
        self.name = name
        self.base = base
        self.added = added
        self.removed = removed
        self.order = order
    }
}

/// A lesson of My course resolved against the current grammar data.
public struct CourseLesson: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var base: LessonKey?
    public var grammarIDs: [String]
    /// True when any included id is there because of an unreviewed textbook mapping for `base`.
    public var unreviewed: Bool

    public init(id: UUID, name: String, base: LessonKey?, grammarIDs: [String], unreviewed: Bool) {
        self.id = id
        self.name = name
        self.base = base
        self.grammarIDs = grammarIDs
        self.unreviewed = unreviewed
    }
}

/// The learner's on-device course: edits over the lessons of the chosen textbooks, plus custom lessons.
/// Base lessons of `baseBookIDs` that have mapped points and no edit (for example ones that arrived
/// with a data update) appear after the stored lessons, unless the user deleted them.
public struct MyCourse: Codable, Equatable, Sendable {
    public var baseBookIDs: [String]
    public var lessons: [CourseLessonEdit]
    public var removedBaseLessons: [LessonKey]

    public init(baseBookIDs: [String] = [], lessons: [CourseLessonEdit] = [], removedBaseLessons: [LessonKey] = []) {
        self.baseBookIDs = baseBookIDs
        self.lessons = lessons
        self.removedBaseLessons = removedBaseLessons
    }

    /// One edit per mapped lesson of `bookIDs`, by book then lesson number. Empty `bookIDs` gives an empty course.
    public static func starting(from bookIDs: [String], points: [GrammarPoint], textbooks: [Textbook]) -> MyCourse {
        var course = MyCourse(baseBookIDs: bookIDs)
        course.lessons = course.pendingBaseLessons(points: points, textbooks: textbooks)
        return course
    }

    public func resolved(points: [GrammarPoint], textbooks: [Textbook]) -> [CourseLesson] {
        let known = Set(points.map(\.id))
        return (lessons + pendingBaseLessons(points: points, textbooks: textbooks))
            .map { resolve($0, points: points, known: known) }
    }

    /// The first resolved lesson containing `grammarID`.
    public func lessonTag(for grammarID: String, points: [GrammarPoint], textbooks: [Textbook]) -> CourseLesson? {
        resolved(points: points, textbooks: textbooks).first { $0.grammarIDs.contains(grammarID) }
    }

    // MARK: - Editing

    public mutating func addLesson(named name: String) -> UUID {
        let edit = CourseLessonEdit(name: name)
        lessons.append(edit)
        return edit.id
    }

    public mutating func rename(_ id: UUID, to name: String, points: [GrammarPoint], textbooks: [Textbook]) {
        guard let i = materialise(id, points: points, textbooks: textbooks) else { return }
        lessons[i].name = name
    }

    /// Deleting a base-linked lesson records its key so it does not come back. A base lesson that
    /// has no edit yet only has its key recorded.
    public mutating func deleteLesson(_ id: UUID, points: [GrammarPoint], textbooks: [Textbook]) {
        if let i = lessons.firstIndex(where: { $0.id == id }) {
            let edit = lessons.remove(at: i)
            if let key = edit.base { recordRemoved(key) }
        } else if let pending = pendingBaseLessons(points: points, textbooks: textbooks).first(where: { $0.id == id }),
                  let key = pending.base {
            recordRemoved(key)
        }
    }

    /// Re-adding a removed base id restores it; any other id is appended to `added`.
    public mutating func add(_ grammarID: String, to lesson: UUID, points: [GrammarPoint], textbooks: [Textbook]) {
        guard let i = materialise(lesson, points: points, textbooks: textbooks) else { return }
        if let r = lessons[i].removed.firstIndex(of: grammarID) {
            lessons[i].removed.remove(at: r)
            return
        }
        if let key = lessons[i].base, Self.baseIDs(for: key, points: points).contains(grammarID) { return }
        if !lessons[i].added.contains(grammarID) { lessons[i].added.append(grammarID) }
    }

    /// An added id is deleted from `added`; a base id is recorded in `removed`.
    public mutating func remove(_ grammarID: String, from lesson: UUID, points: [GrammarPoint], textbooks: [Textbook]) {
        guard let i = materialise(lesson, points: points, textbooks: textbooks) else { return }
        lessons[i].added.removeAll { $0 == grammarID }
        lessons[i].order.removeAll { $0 == grammarID }
        if let key = lessons[i].base, Self.baseIDs(for: key, points: points).contains(grammarID),
           !lessons[i].removed.contains(grammarID) {
            lessons[i].removed.append(grammarID)
        }
    }

    public mutating func setOrder(_ ids: [String], in lesson: UUID, points: [GrammarPoint], textbooks: [Textbook]) {
        guard let i = materialise(lesson, points: points, textbooks: textbooks) else { return }
        lessons[i].order = ids
    }

    // MARK: - Resolution

    /// Base lessons of `baseBookIDs` with mapped points, no edit, and not deleted: by book (textbook
    /// order), then lesson number, with a default name and an id derived from the key.
    func pendingBaseLessons(points: [GrammarPoint], textbooks: [Textbook]) -> [CourseLessonEdit] {
        let books = Set(baseBookIDs)
        let edited = Set(lessons.compactMap(\.base))
        let deleted = Set(removedBaseLessons)
        var keys: Set<LessonKey> = []
        for point in points {
            for ref in point.taughtIn where books.contains(ref.book) {
                keys.insert(LessonKey(book: ref.book, lesson: ref.lesson))
            }
        }
        keys.subtract(edited)
        keys.subtract(deleted)

        let bookRank = { (book: String) -> Int in
            if let i = textbooks.firstIndex(where: { $0.id == book }) { return i }
            return textbooks.count + (baseBookIDs.firstIndex(of: book) ?? 0)
        }
        return keys
            .sorted { (bookRank($0.book), $0.lesson) < (bookRank($1.book), $1.lesson) }
            .map { key in
                let title = textbooks.first { $0.id == key.book }?.title ?? key.book
                return CourseLessonEdit(id: Self.lessonID(for: key), name: "\(title) · Lesson \(key.lesson)", base: key)
            }
    }

    private func resolve(_ edit: CourseLessonEdit, points: [GrammarPoint], known: Set<String>) -> CourseLesson {
        var ids: [String]
        var unreviewedIDs: Set<String> = []
        if let key = edit.base {
            let removed = Set(edit.removed)
            ids = []
            for point in points {
                let refs = point.taughtIn.filter { $0.book == key.book && $0.lesson == key.lesson }
                guard !refs.isEmpty, !removed.contains(point.id) else { continue }
                ids.append(point.id)
                if refs.contains(where: { !$0.reviewed }) { unreviewedIDs.insert(point.id) }
            }
        } else {
            ids = []
        }
        for id in edit.added where !ids.contains(id) { ids.append(id) }

        let ordered = edit.order.filter(ids.contains).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        ids = ordered + ids.filter { !ordered.contains($0) }
        ids = ids.filter(known.contains)

        return CourseLesson(id: edit.id, name: edit.name, base: edit.base, grammarIDs: ids,
                            unreviewed: ids.contains(where: unreviewedIDs.contains))
    }

    private static func baseIDs(for key: LessonKey, points: [GrammarPoint]) -> [String] {
        points.filter { $0.taughtIn.contains { $0.book == key.book && $0.lesson == key.lesson } }.map(\.id)
    }

    /// The index of the edit for `id`. A base lesson with no edit yet is materialised in place: it,
    /// and any pending base lessons resolved ahead of it, are appended to `lessons` so the order holds.
    private mutating func materialise(_ id: UUID, points: [GrammarPoint], textbooks: [Textbook]) -> Int? {
        if let i = lessons.firstIndex(where: { $0.id == id }) { return i }
        let pending = pendingBaseLessons(points: points, textbooks: textbooks)
        guard let p = pending.firstIndex(where: { $0.id == id }) else { return nil }
        lessons.append(contentsOf: pending[...p])
        return lessons.count - 1
    }

    private mutating func recordRemoved(_ key: LessonKey) {
        if !removedBaseLessons.contains(key) { removedBaseLessons.append(key) }
    }

    /// A stable id for a base lesson: the first 16 bytes of SHA-256 of "book:lesson", marked as a v5-style UUID.
    static func lessonID(for key: LessonKey) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("\(key.book):\(key.lesson)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
