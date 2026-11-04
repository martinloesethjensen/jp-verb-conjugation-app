import Foundation

/// One particle question: an example sentence with one marked particle blanked
/// (電車＿＿＿乗ります → に), the right particle among common ones. After answering, the full
/// sentence, its translation and a link to its lesson or verb page are shown.
public struct ParticleQuestion: Equatable, Sendable, Identifiable {
    public var id: UUID
    /// "<example id>#<blank index>": what quiz history records as the attempt's subject, and what
    /// the review site addresses the blank by.
    public var blankID: String
    /// The whole sentence, as in the data.
    public var sentence: String
    /// The sentence before and after the blanked particle.
    public var before: String
    public var after: String
    /// The particle the data marks, and the right answer.
    public var particle: String
    /// Other particles that are just as right here. Never among `choices`.
    public var acceptAlso: [String]
    /// `particle` and up to three wrong particles, shuffled.
    public var choices: [String]
    public var translation: String
    /// Where the example comes from, for the link shown after answering.
    public var source: Route
    public var sourceTitle: String

    public init(
        id: UUID = UUID(), blankID: String, sentence: String, before: String, after: String,
        particle: String, acceptAlso: [String] = [], choices: [String], translation: String,
        source: Route, sourceTitle: String
    ) {
        self.id = id
        self.blankID = blankID
        self.sentence = sentence
        self.before = before
        self.after = after
        self.particle = particle
        self.acceptAlso = acceptAlso
        self.choices = choices
        self.translation = translation
        self.source = source
        self.sourceTitle = sourceTitle
    }

    /// The sentence with the particle replaced by the quiz's blank (＿＿＿).
    public var blanked: String { before + QuizQuestion.blank + after }

    public func isCorrect(_ choice: String) -> Bool { choice == particle || acceptAlso.contains(choice) }
}

public enum ParticleQuiz {
    /// The particles wrong choices are drawn from, as the JLPT 文法 section mixes them.
    public static let commonParticles = ["は", "が", "を", "に", "で", "へ", "と", "も", "から", "まで"]

    /// Particles that can stand where the key particle stands with the sentence still correct, so
    /// they are never offered as wrong choices: は and も can replace が and を (and each other);
    /// まで can replace に and へ of a destination, and に and へ each other. A blank's own
    /// `accept_also` adds to these.
    public static let substitutes: [String: Set<String>] = [
        "が": ["は", "も"],
        "を": ["は", "も"],
        "は": ["が", "も"],
        "も": ["は", "が", "を"],
        "に": ["まで"],
        "へ": ["に", "まで"],
    ]

    /// Up to `count` wrong particles for `blank`: common particles that are neither the answer,
    /// nor accepted, nor a substitute for it, in random order.
    public static func distractors(for blank: ParticleBlank, count: Int = 3) -> [String] {
        let excluded = Set([blank.particle] + blank.acceptAlso).union(substitutes[blank.particle] ?? [])
        return Array(commonParticles.filter { !excluded.contains($0) }.shuffled().prefix(count))
    }
}

/// Particle questions from the marked blanks (`particle_blanks`) on lesson and verb examples,
/// one per blank, shuffled and capped at `count`.
///
/// - Only lessons, usages and verbs visible under `levels` are used. A usage's examples count at
///   the usage's level (its own `jlpt`, else the lesson's); pitfall and contrast examples at the
///   lesson's level.
/// - An example without a stable id makes no question (history could not name it), and neither
///   does a blank whose particle is not where it says (the data check prevents this).
/// - Each question offers the right particle and three wrong ones (`ParticleQuiz.distractors`).
public func buildParticleQuestions(
    grammar: [GrammarPoint], verbs: [Verb], levels: LevelSettings = LevelSettings(), count: Int
) -> [ParticleQuestion] {
    guard count > 0 else { return [] }
    var questions: [ParticleQuestion] = []

    func add(_ examples: [(id: String?, jp: String, en: String, blanks: [ParticleBlank])], source: Route, title: String) {
        for example in examples {
            guard let exampleID = example.id else { continue }
            for (index, blank) in example.blanks.enumerated() {
                guard let parts = blank.split(example.jp) else { continue }
                let wrong = ParticleQuiz.distractors(for: blank)
                guard !wrong.isEmpty else { continue }
                questions.append(ParticleQuestion(
                    blankID: "\(exampleID)#\(index)", sentence: example.jp, before: parts.before, after: parts.after,
                    particle: blank.particle, acceptAlso: blank.acceptAlso, choices: ([blank.particle] + wrong).shuffled(),
                    translation: example.en, source: source, sourceTitle: title
                ))
            }
        }
    }

    for point in grammar.visible(in: levels) {
        // A usage counts at its own level; pitfalls and contrasts at the lesson's.
        var examples = point.visibleUsages(in: levels).flatMap(\.examples)
        if levels.isVisible(point.jlpt) {
            examples += point.pitfalls.flatMap(\.examples) + point.contrasts.flatMap(\.examples)
        }
        add(examples.map { ($0.id, $0.jp, $0.en, $0.particleBlanks) }, source: .grammar(point.id), title: point.title)
    }
    for verb in verbs.visible(in: levels) {
        add(verb.examples.map { ($0.id, $0.jp, $0.en, $0.particleBlanks) }, source: .verb(verb.id), title: verb.displayTitle)
    }
    return Array(questions.shuffled().prefix(count))
}
