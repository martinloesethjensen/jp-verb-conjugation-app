import XCTest
@testable import VerbKit

final class MyCourseTests: XCTestCase {
    private let textbooks = [
        Textbook(id: "genki-1", title: "Genki I", lessons: 12),
        Textbook(id: "genki-2", title: "Genki II", firstLesson: 13, lessons: 23),
    ]

    private func point(_ id: String, _ refs: [(String, Int)] = [], reviewed: Bool = false) -> GrammarPoint {
        GrammarPoint(id: id, title: id, summary: "", usages: [], attachment: [],
                     conjugations: [], pitfalls: [], related: [],
                     taughtIn: refs.map { LessonRef(book: $0.0, lesson: $0.1, reviewed: reviewed) })
    }

    /// L7: teiru. L12: node, hou. sugiru unmapped.
    private var points: [GrammarPoint] {
        [point("teiru", [("genki-1", 7)]),
         point("node", [("genki-1", 12)]),
         point("hou", [("genki-1", 12)]),
         point("sugiru")]
    }

    /// Only L12 is mapped.
    private var l12Only: [GrammarPoint] {
        [point("teiru"), point("node", [("genki-1", 12)]), point("hou", [("genki-1", 12)]), point("sugiru")]
    }

    private func names(_ course: MyCourse, _ pts: [GrammarPoint]) -> [String] {
        course.resolved(points: pts, textbooks: textbooks).map(\.name)
    }

    private func lesson(_ course: MyCourse, _ name: String, _ pts: [GrammarPoint]) -> CourseLesson? {
        course.resolved(points: pts, textbooks: textbooks).first { $0.name == name }
    }

    func testStartingFromABookMakesOneLessonPerMappedLessonInOrder() {
        let course = MyCourse.starting(from: ["genki-1"], points: points, textbooks: textbooks)
        let resolved = course.resolved(points: points, textbooks: textbooks)
        XCTAssertEqual(resolved.map(\.name), ["Genki I · Lesson 7", "Genki I · Lesson 12"])
        XCTAssertTrue(resolved.allSatisfy(\.unreviewed))
        XCTAssertEqual(resolved.map(\.grammarIDs), [["teiru"], ["node", "hou"]])
        XCTAssertEqual(course.lessons.map(\.base), [LessonKey(book: "genki-1", lesson: 7), LessonKey(book: "genki-1", lesson: 12)])
    }

    func testReviewedRefsAreNotUnreviewed() {
        let pts = [point("node", [("genki-1", 12)], reviewed: true)]
        let course = MyCourse.starting(from: ["genki-1"], points: pts, textbooks: textbooks)
        XCTAssertEqual(course.resolved(points: pts, textbooks: textbooks).map(\.unreviewed), [false])
    }

    func testStartingEmptyHasNoLessons() {
        let course = MyCourse.starting(from: [], points: points, textbooks: textbooks)
        XCTAssertEqual(course.lessons, [])
        XCTAssertEqual(course.resolved(points: points, textbooks: textbooks), [])
    }

    func testAddRenameDeleteCustomLesson() {
        var course = MyCourse.starting(from: [], points: points, textbooks: textbooks)
        let id = course.addLesson(named: "Week 1")
        course.add("sugiru", to: id, points: points, textbooks: textbooks)
        course.add("node", to: id, points: points, textbooks: textbooks)
        var resolved = course.resolved(points: points, textbooks: textbooks)
        XCTAssertEqual(resolved.map(\.name), ["Week 1"])
        XCTAssertEqual(resolved.first?.grammarIDs, ["sugiru", "node"])
        XCTAssertEqual(resolved.first?.unreviewed, false)
        XCTAssertNil(resolved.first?.base)

        course.rename(id, to: "Week one", points: points, textbooks: textbooks)
        course.remove("sugiru", from: id, points: points, textbooks: textbooks)
        resolved = course.resolved(points: points, textbooks: textbooks)
        XCTAssertEqual(resolved.map(\.name), ["Week one"])
        XCTAssertEqual(resolved.first?.grammarIDs, ["node"])

        course.deleteLesson(id, points: points, textbooks: textbooks)
        XCTAssertEqual(course.resolved(points: points, textbooks: textbooks), [])
        XCTAssertEqual(course.removedBaseLessons, [])
    }

    func testRemovingABaseIdAndAddingAnother() throws {
        var course = MyCourse.starting(from: ["genki-1"], points: points, textbooks: textbooks)
        let l12 = try XCTUnwrap(lesson(course, "Genki I · Lesson 12", points))
        XCTAssertEqual(l12.grammarIDs, ["node", "hou"])
        course.remove("node", from: l12.id, points: points, textbooks: textbooks)
        course.add("teiru", to: l12.id, points: points, textbooks: textbooks)
        XCTAssertEqual(lesson(course, "Genki I · Lesson 12", points)?.grammarIDs, ["hou", "teiru"])
        XCTAssertEqual(course.lessons.last?.removed, ["node"])
        XCTAssertEqual(course.lessons.last?.added, ["teiru"])

        // Removing an added id takes it out of `added`; re-adding a removed base id restores it.
        course.remove("teiru", from: l12.id, points: points, textbooks: textbooks)
        course.add("node", to: l12.id, points: points, textbooks: textbooks)
        XCTAssertEqual(course.lessons.last?.added, [])
        XCTAssertEqual(course.lessons.last?.removed, [])
        XCTAssertEqual(lesson(course, "Genki I · Lesson 12", points)?.grammarIDs, ["node", "hou"])
    }

    func testReAddingARemovedIdThatLeftTheBaseAddsItOnce() throws {
        var course = MyCourse.starting(from: ["genki-1"], points: points, textbooks: textbooks)
        let l12 = try XCTUnwrap(lesson(course, "Genki I · Lesson 12", points))
        course.remove("node", from: l12.id, points: points, textbooks: textbooks)
        // A data update moves node out of L12.
        let moved = [point("teiru", [("genki-1", 7)]), point("node", [("genki-1", 7)]),
                     point("hou", [("genki-1", 12)]), point("sugiru")]
        course.add("node", to: l12.id, points: moved, textbooks: textbooks)
        XCTAssertEqual(lesson(course, "Genki I · Lesson 12", moved)?.grammarIDs, ["hou", "node"])
        XCTAssertEqual(course.lessons.last?.removed, [])
        XCTAssertEqual(course.lessons.last?.added, ["node"])
    }

    func testSetOrderReorders() throws {
        var course = MyCourse.starting(from: ["genki-1"], points: points, textbooks: textbooks)
        let l12 = try XCTUnwrap(lesson(course, "Genki I · Lesson 12", points))
        course.add("sugiru", to: l12.id, points: points, textbooks: textbooks)
        course.setOrder(["sugiru", "hou"], in: l12.id, points: points, textbooks: textbooks)
        XCTAssertEqual(lesson(course, "Genki I · Lesson 12", points)?.grammarIDs, ["sugiru", "hou", "node"])

        let custom = course.addLesson(named: "Mine")
        course.add("node", to: custom, points: points, textbooks: textbooks)
        course.add("hou", to: custom, points: points, textbooks: textbooks)
        course.setOrder(["hou", "node"], in: custom, points: points, textbooks: textbooks)
        XCTAssertEqual(lesson(course, "Mine", points)?.grammarIDs, ["hou", "node"])
    }

    func testIdsMissingFromTheDataAreDropped() throws {
        var course = MyCourse.starting(from: ["genki-1"], points: points, textbooks: textbooks)
        let l12 = try XCTUnwrap(lesson(course, "Genki I · Lesson 12", points))
        course.add("hou", to: course.addLesson(named: "Mine"), points: points, textbooks: textbooks)
        course.setOrder(["hou", "node"], in: l12.id, points: points, textbooks: textbooks)
        let withoutHou = points.filter { $0.id != "hou" }
        XCTAssertEqual(lesson(course, "Genki I · Lesson 12", withoutHou)?.grammarIDs, ["node"])
        XCTAssertEqual(lesson(course, "Mine", withoutHou)?.grammarIDs, [])
    }

    func testNewBaseLessonsAppearButDeletedOnesStayDeleted() throws {
        var course = MyCourse.starting(from: ["genki-1"], points: l12Only, textbooks: textbooks)
        XCTAssertEqual(names(course, l12Only), ["Genki I · Lesson 12"])
        let l12 = try XCTUnwrap(lesson(course, "Genki I · Lesson 12", l12Only))
        course.deleteLesson(l12.id, points: l12Only, textbooks: textbooks)
        XCTAssertEqual(course.removedBaseLessons, [LessonKey(book: "genki-1", lesson: 12)])
        XCTAssertEqual(names(course, points), ["Genki I · Lesson 7"])
    }

    func testDeletingANewlyArrivedBaseLessonOnlyRecordsItsKey() throws {
        var course = MyCourse.starting(from: ["genki-1"], points: l12Only, textbooks: textbooks)
        let l7 = try XCTUnwrap(lesson(course, "Genki I · Lesson 7", points))
        course.deleteLesson(l7.id, points: points, textbooks: textbooks)
        XCTAssertEqual(course.lessons.count, 1)
        XCTAssertEqual(course.removedBaseLessons, [LessonKey(book: "genki-1", lesson: 7)])
        XCTAssertEqual(names(course, points), ["Genki I · Lesson 12"])
    }

    func testEditingANewlyArrivedBaseLessonMaterialisesItInPlace() throws {
        var course = MyCourse.starting(from: ["genki-1"], points: l12Only, textbooks: textbooks)
        let resolved = course.resolved(points: points, textbooks: textbooks)
        XCTAssertEqual(resolved.map(\.name), ["Genki I · Lesson 12", "Genki I · Lesson 7"])
        let l7 = resolved[1]
        // The derived id is stable across resolves.
        XCTAssertEqual(course.resolved(points: points, textbooks: textbooks)[1].id, l7.id)

        course.rename(l7.id, to: "Te-iru", points: points, textbooks: textbooks)
        XCTAssertEqual(course.lessons.count, 2)
        let after = course.resolved(points: points, textbooks: textbooks)
        XCTAssertEqual(after.map(\.name), ["Genki I · Lesson 12", "Te-iru"])
        XCTAssertEqual(after[1].id, l7.id)
        XCTAssertEqual(after[1].base, LessonKey(book: "genki-1", lesson: 7))
        XCTAssertEqual(after[1].grammarIDs, ["teiru"])
    }

    func testMaterialisingKeepsEarlierNewLessonsAheadOfIt() throws {
        let threeNew = [point("teiru", [("genki-1", 7)]), point("hou", [("genki-1", 9)]),
                        point("node", [("genki-1", 12)])]
        var course = MyCourse.starting(from: ["genki-1"], points: [], textbooks: textbooks)
        let l9 = try XCTUnwrap(lesson(course, "Genki I · Lesson 9", threeNew))
        course.add("sugiru", to: l9.id, points: threeNew, textbooks: textbooks)
        XCTAssertEqual(names(course, threeNew), ["Genki I · Lesson 7", "Genki I · Lesson 9", "Genki I · Lesson 12"])
        XCTAssertEqual(lesson(course, "Genki I · Lesson 9", threeNew + [point("sugiru")])?.grammarIDs, ["hou", "sugiru"])
    }

    func testEditsSurviveABaseMappingChange() throws {
        var course = MyCourse.starting(from: ["genki-1"], points: points, textbooks: textbooks)
        let l12 = try XCTUnwrap(lesson(course, "Genki I · Lesson 12", points))
        course.remove("node", from: l12.id, points: points, textbooks: textbooks)
        let updated = [point("teiru", [("genki-1", 7)]), point("node", [("genki-1", 12)]),
                       point("hou", [("genki-1", 12)]), point("sugiru", [("genki-1", 12)])]
        XCTAssertEqual(lesson(course, "Genki I · Lesson 12", updated)?.grammarIDs, ["hou", "sugiru"])
    }

    func testBaseLessonsComeInBookThenLessonOrder() {
        let pts = [point("a", [("genki-2", 13)]), point("b", [("genki-1", 12)]), point("c", [("genki-1", 3)])]
        let course = MyCourse.starting(from: ["genki-2", "genki-1"], points: pts, textbooks: textbooks)
        XCTAssertEqual(names(course, pts), ["Genki I · Lesson 3", "Genki I · Lesson 12", "Genki II · Lesson 13"])
    }

    func testLessonTagIsTheFirstLessonContainingThePoint() {
        var course = MyCourse.starting(from: ["genki-1"], points: points, textbooks: textbooks)
        let custom = course.addLesson(named: "Mine")
        course.add("hou", to: custom, points: points, textbooks: textbooks)
        XCTAssertEqual(course.lessonTag(for: "hou", points: points, textbooks: textbooks)?.name, "Genki I · Lesson 12")
        XCTAssertEqual(course.lessonTag(for: "teiru", points: points, textbooks: textbooks)?.name, "Genki I · Lesson 7")
        XCTAssertNil(course.lessonTag(for: "sugiru", points: points, textbooks: textbooks))
    }

    func testUnknownLessonIdsAreANoOp() {
        var course = MyCourse.starting(from: ["genki-1"], points: points, textbooks: textbooks)
        let before = course
        let unknown = UUID()
        course.rename(unknown, to: "x", points: points, textbooks: textbooks)
        course.add("sugiru", to: unknown, points: points, textbooks: textbooks)
        course.remove("node", from: unknown, points: points, textbooks: textbooks)
        course.setOrder(["hou"], in: unknown, points: points, textbooks: textbooks)
        course.deleteLesson(unknown, points: points, textbooks: textbooks)
        XCTAssertEqual(course, before)
    }

    func testCourseRoundTripsThroughJSON() throws {
        var course = MyCourse.starting(from: ["genki-1"], points: points, textbooks: textbooks)
        let custom = course.addLesson(named: "Mine")
        course.add("sugiru", to: custom, points: points, textbooks: textbooks)
        course.deleteLesson(course.lessons[0].id, points: points, textbooks: textbooks)
        let data = try JSONEncoder().encode(course)
        XCTAssertEqual(try JSONDecoder().decode(MyCourse.self, from: data), course)
    }
}
