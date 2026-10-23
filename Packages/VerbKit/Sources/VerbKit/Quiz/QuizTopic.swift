/// What a quiz can practise. "Everything" is not a topic: it is all of them at once.
public enum QuizTopic: String, CaseIterable, Codable, Sendable {
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

    /// The catalogue family (`forms.json`) this topic quizzes.
    public var family: String {
        switch self {
        case .basic: return "basic"
        case .potential: return "potential"
        case .nDesu: return "nd"
        case .auxiliaries: return "auxiliary"
        case .otherForms: return "other"
        }
    }

    /// The topic for a catalogue family, or nil for a family this build does not know.
    public init?(family: String) {
        guard let topic = Self.allCases.first(where: { $0.family == family }) else { return nil }
        self = topic
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
