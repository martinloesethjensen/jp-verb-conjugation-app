import XCTest
@testable import VerbKit

@MainActor
final class CourseStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    private let textbooks = [Textbook(id: "genki-1", title: "Genki I", lessons: 12)]
    private let points = [
        GrammarPoint(id: "node", title: "node", summary: "", usages: [], attachment: [],
                     conjugations: [], pitfalls: [], related: [],
                     taughtIn: [LessonRef(book: "genki-1", lesson: 12, reviewed: false)]),
    ]

    override func setUp() {
        super.setUp()
        suiteName = "CourseStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testStartEditClearPersist() throws {
        let store = CourseStore(defaults: defaults)
        XCTAssertNil(store.course)
        store.start(from: ["genki-1"], points: points, textbooks: textbooks)
        let id = try XCTUnwrap(store.course?.lessons.first?.id)
        store.edit { $0.rename(id, to: "Because", points: self.points, textbooks: self.textbooks) }

        let reloaded = CourseStore(defaults: defaults)
        XCTAssertEqual(reloaded.course, store.course)
        XCTAssertEqual(reloaded.course?.lessons.map(\.name), ["Because"])

        reloaded.clear()
        XCTAssertNil(reloaded.course)
        XCTAssertNil(defaults.object(forKey: CourseStore.defaultsKey))
        XCTAssertNil(CourseStore(defaults: defaults).course)
    }

    func testEditWithoutACourseDoesNothing() {
        let store = CourseStore(defaults: defaults)
        store.edit { _ = $0.addLesson(named: "x") }
        XCTAssertNil(store.course)
        XCTAssertNil(defaults.object(forKey: CourseStore.defaultsKey))
    }

    func testCorruptStoredCourseLoadsAsNone() {
        defaults.set(Data("x".utf8), forKey: CourseStore.defaultsKey)
        XCTAssertNil(CourseStore(defaults: defaults).course)
    }

    /// Pins the v1 stored shape: a future required field must not silently wipe learners' courses.
    func testAVersionOneStoredCourseStillLoads() throws {
        let json = #"{"baseBookIDs":["genki-1"],"lessons":[{"added":["kara"],"base":{"book":"genki-1","lesson":12},"id":"6F1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D","name":"Because","order":["kara"],"removed":["node"]}],"removedBaseLessons":[{"book":"genki-1","lesson":3}]}"#
        defaults.set(Data(json.utf8), forKey: CourseStore.defaultsKey)
        let course = try XCTUnwrap(CourseStore(defaults: defaults).course)
        XCTAssertEqual(course.baseBookIDs, ["genki-1"])
        XCTAssertEqual(course.removedBaseLessons, [LessonKey(book: "genki-1", lesson: 3)])
        let edit = try XCTUnwrap(course.lessons.first)
        XCTAssertEqual(course.lessons.count, 1)
        XCTAssertEqual(edit.id, UUID(uuidString: "6F1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D"))
        XCTAssertEqual(edit.name, "Because")
        XCTAssertEqual(edit.base, LessonKey(book: "genki-1", lesson: 12))
        XCTAssertEqual(edit.added, ["kara"])
        XCTAssertEqual(edit.removed, ["node"])
        XCTAssertEqual(edit.order, ["kara"])
    }

    func testMalformedTextbookRangeContainsNothingAndDoesNotTrap() {
        let book = Textbook(id: "bad", title: "Bad", firstLesson: 13, lessons: 12)
        XCTAssertFalse(book.contains(lesson: 12))
        XCTAssertFalse(book.contains(lesson: 13))
    }
}
