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
}
