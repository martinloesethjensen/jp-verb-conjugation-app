import Foundation

/// `verbtable://quiz` starts a quiz on everything, `verbtable://quiz/<topic>` on one topic
/// (a `QuizTopic` raw value such as `basic` or `nDesu`), and `verbtable://quiz/weak` a Weak spots
/// quiz (the Review reminder). Used by Siri, Shortcuts and notifications.
public struct QuizLink: Equatable, Sendable {
    /// `nil` means every topic. Always nil for a weak-spots link.
    public var topic: QuizTopic?
    /// A Weak spots quiz rather than a topic quiz.
    public var weakSpots: Bool

    public init(topic: QuizTopic? = nil) {
        self.topic = topic
        self.weakSpots = false
    }

    private init(weakSpots: Bool) {
        self.topic = nil
        self.weakSpots = weakSpots
    }

    /// `verbtable://quiz/weak`.
    public static let weakSpots = QuizLink(weakSpots: true)
    static let weakPath = "weak"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Route.urlScheme
        components.host = "quiz"
        if weakSpots {
            components.path = "/" + Self.weakPath
        } else if let topic {
            components.path = "/" + topic.rawValue
        }
        return components.url!
    }

    /// nil for anything that is not a quiz link, including an unknown topic.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Route.urlScheme, url.host?.lowercased() == "quiz" else { return nil }
        let name = url.path.split(separator: "/").first.map(String.init)
        self.weakSpots = false
        if name == Self.weakPath {
            self.topic = nil
            self.weakSpots = true
        } else if let name {
            guard let topic = QuizTopic(rawValue: name) else { return nil }
            self.topic = topic
        } else {
            self.topic = nil
        }
    }
}
