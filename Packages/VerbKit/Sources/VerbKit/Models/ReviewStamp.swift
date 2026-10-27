import Foundation

/// Who reviewed an entry. The data pipeline accepts only these two.
public enum Reviewer: String, Codable, Hashable, Sendable {
    case owner, teacher

    public var displayName: String {
        switch self {
        case .owner: "the owner"
        case .teacher: "a teacher"
        }
    }
}

/// A review stamp on a counter or grammar point (`review` in the data). The pipeline hashes the entry's own
/// content into `sha256` and refuses data whose stamp no longer matches, so a stamp that reaches the app is
/// current: the app only checks that one is there.
public struct ReviewStamp: Codable, Hashable, Sendable {
    public var by: Reviewer
    /// An ISO date, "2026-10-24".
    public var on: String
    public var sha256: String

    public init(by: Reviewer, on: String, sha256: String) {
        self.by = by
        self.on = on
        self.sha256 = sha256
    }
}

/// Content that can carry a review stamp.
public protocol Reviewable {
    var review: ReviewStamp? { get }
}

extension Reviewable {
    public var isReviewed: Bool { review != nil }
}

/// How much of a list has been reviewed, and when the latest review was.
public struct ReviewSummary: Equatable, Sendable {
    public var reviewed: Int
    public var total: Int
    /// The greatest review date among the stamped items, or nil when none is stamped.
    public var latest: String?

    public init(reviewed: Int, total: Int, latest: String?) {
        self.reviewed = reviewed
        self.total = total
        self.latest = latest
    }

    public init(_ items: [some Reviewable]) {
        let stamps = items.compactMap(\.review)
        self.init(reviewed: stamps.count, total: items.count, latest: stamps.map(\.on).max())
    }
}

extension Counter: Reviewable {}
extension GrammarPoint: Reviewable {}
