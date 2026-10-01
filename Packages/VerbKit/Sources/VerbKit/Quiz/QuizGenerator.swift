/// Builds up to `count` questions from the (verb, form) pairs the verbs have in
/// `topics`. Each is a conjugate or an identify question, drawn from `kinds`.
///
/// - Conjugate: the choices are conjugated strings. Distractors are the same verb's
///   other forms in the topics first, then the same form of other verbs.
/// - Identify: the choices are form labels. Distractors are labels of the same
///   verb's other forms in the topics.
///
/// A pool entry is skipped when its string equals another form's string for the same
/// verb (it would have two right answers), and a question that cannot get at least
/// two choices is skipped rather than shown with one button.
public func buildQuestions(
    verbs: [Verb],
    topics: Set<QuizTopic>,
    count: Int,
    kinds: [QuizQuestionKind] = [.conjugate, .identify]
) -> [QuizQuestion] {
    guard count > 0, !kinds.isEmpty else { return [] }

    struct PoolEntry {
        let verb: Verb
        let form: QuizForm
        let value: String
    }

    var pool: [PoolEntry] = []
    for verb in verbs {
        let everyString = QuizForm.available(in: verb.forms, topics: Set(QuizTopic.allCases)).map(\.value)
        for (form, value) in QuizForm.available(in: verb.forms, topics: topics)
        where everyString.filter({ $0 == value }).count == 1 {
            pool.append(PoolEntry(verb: verb, form: form, value: value))
        }
    }

    func pick(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return Array(candidates.shuffled().filter { seen.insert($0).inserted }.prefix(3))
    }

    var questions: [QuizQuestion] = []
    for entry in pool.shuffled() {
        guard questions.count < count else { break }
        let sameVerb = QuizForm.available(in: entry.verb.forms, topics: topics)
            .filter { $0.form != entry.form }
        let kind = kinds.randomElement()!

        let correct: String
        let distractors: [String]
        switch kind {
        case .conjugate:
            correct = entry.value
            let sameVerbStrings = sameVerb.map(\.value).filter { $0 != correct }
            let otherVerbStrings = verbs
                .filter { $0.dict != entry.verb.dict }
                .compactMap { entry.form.value(in: $0.forms) }
                .filter { $0 != correct }
            // Same verb's forms first, as before; shuffle within each group.
            var seen = Set<String>()
            distractors = Array(
                (sameVerbStrings.shuffled() + otherVerbStrings.shuffled())
                    .filter { seen.insert($0).inserted }
                    .prefix(3)
            )
        case .identify:
            correct = entry.form.label
            distractors = pick(sameVerb.map(\.form.label).filter { $0 != correct })
        }

        guard !distractors.isEmpty else { continue }
        questions.append(QuizQuestion(
            verb: entry.verb, form: entry.form, kind: kind, formString: entry.value,
            correct: correct, choices: ([correct] + distractors).shuffled()
        ))
    }
    return questions
}
