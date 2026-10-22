import Foundation
import Observation

/// Holds My course and keeps it in `UserDefaults` as JSON. On-device only. A missing or unreadable
/// stored course loads as none.
@MainActor
@Observable
public final class CourseStore {
    public static let defaultsKey = "myCourse"

    public private(set) var course: MyCourse?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.course = defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(MyCourse.self, from: $0) }
    }

    public func start(from bookIDs: [String], points: [GrammarPoint], textbooks: [Textbook]) {
        course = .starting(from: bookIDs, points: points, textbooks: textbooks)
        save()
    }

    /// Applies `change` and saves. Does nothing when there is no course.
    public func edit(_ change: (inout MyCourse) -> Void) {
        guard var updated = course else { return }
        change(&updated)
        course = updated
        save()
    }

    public func clear() {
        course = nil
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func save() {
        guard let course, let data = try? JSONEncoder().encode(course) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
