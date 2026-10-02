import Foundation

/// `verbtable://quiz` starts a quiz on everything, `verbtable://quiz/<topic>` on one topic
/// (`basic`, `potential`, `nDesu`, `auxiliaries`). Used by Siri and Shortcuts.
public struct QuizLink: Equatable, Sendable {
    /// `nil` means every topic.
    public var topic: QuizTopic?

    public init(topic: QuizTopic? = nil) {
        self.topic = topic
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Route.urlScheme
        components.host = "quiz"
        if let topic { components.path = "/" + topic.rawValue }
        return components.url!
    }

    /// nil for anything that is not a quiz link, including an unknown topic.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Route.urlScheme, url.host?.lowercased() == "quiz" else { return nil }
        let name = url.path.split(separator: "/").first.map(String.init)
        if let name {
            guard let topic = QuizTopic(rawValue: name) else { return nil }
            self.topic = topic
        } else {
            self.topic = nil
        }
    }
}
