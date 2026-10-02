/// What a quiz can practise. "Everything" is not a topic: it is all of them at once.
public enum QuizTopic: String, CaseIterable, Sendable {
    case basic, potential, nDesu, auxiliaries, otherForms

    public var title: String {
        switch self {
        case .basic: return "Basic forms"
        case .potential: return "Potential"
        case .nDesu: return "んです"
        case .auxiliaries: return "Auxiliaries"
        case .otherForms: return "More forms"
        }
    }
}

/// One row of the topic sheet: a topic and how many forms the verbs in play have in it.
public struct QuizTopicChoice: Equatable, Sendable {
    public let topic: QuizTopic
    public let count: Int
}

extension QuizTopic {
    /// The topics worth offering for these verbs, in display order, skipping any
    /// the verbs have no forms in (ある has no Potential).
    public static func choices(for verbs: [Verb]) -> [QuizTopicChoice] {
        allCases.compactMap { topic in
            let count = verbs.reduce(0) { $0 + QuizForm.available(in: $1.forms, topics: [topic]).count }
            return count > 0 ? QuizTopicChoice(topic: topic, count: count) : nil
        }
    }
}
