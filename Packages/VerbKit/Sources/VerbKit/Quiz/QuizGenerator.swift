/// Builds up to `count` questions from the (verb, form) pairs the verbs have in
/// `topics`. Each is a conjugate or an identify question, drawn from `kinds`.
///
/// - Conjugate: the choices are conjugated strings. Distractors are the same verb's
///   other forms in the topics first, then the same form of other verbs.
/// - Identify: the choices are form labels. Distractors are labels of the same
///   verb's other forms in the topics.
///
/// A form whose string equals another form's string for the same verb (the passive and the
/// potential of a ru-verb, たべられる) is only asked as a conjugate question: an identify
/// question would have two right labels. A question that cannot get at least two choices is
/// skipped rather than shown with one button.
public func buildQuestions(
    verbs: [Verb],
    topics: Set<QuizTopic>,
    count: Int,
    kinds: [QuizQuestionKind] = [.conjugate, .identify]
) -> [QuizQuestion] {
    guard count > 0, !kinds.isEmpty else { return [] }

    var pool: [PoolEntry] = []
    for verb in verbs {
        let everyString = QuizForm.available(in: verb.forms, topics: Set(QuizTopic.allCases)).map(\.value)
        for (form, value) in QuizForm.available(in: verb.forms, topics: topics) {
            pool.append(PoolEntry(
                verb: verb, form: form, value: value,
                sharesString: everyString.filter { $0 == value }.count > 1
            ))
        }
    }

    var questions: [QuizQuestion] = []
    for entry in pool.shuffled() {
        guard questions.count < count else { break }
        if let question = makeQuestion(entry, topics: topics, verbs: verbs, kinds: kinds) {
            questions.append(question)
        }
    }
    return questions
}

/// Like `buildQuestions(verbs:topics:count:kinds:)`, but for exactly the given
/// (verb, form) pairs, in order and unshuffled, so a caller can ask about specific
/// weak spots. `verbs` supplies the other-verb distractors. A pair with too few choices
/// is skipped, and the result is never padded.
public func buildQuestions(
    pairs: [(verb: Verb, form: QuizForm)],
    among verbs: [Verb],
    count: Int,
    kinds: [QuizQuestionKind] = [.conjugate, .identify]
) -> [QuizQuestion] {
    guard count > 0, !kinds.isEmpty else { return [] }
    let allTopics = Set(QuizTopic.allCases)
    var questions: [QuizQuestion] = []
    for pair in pairs {
        guard questions.count < count else { break }
        let everyString = QuizForm.available(in: pair.verb.forms, topics: allTopics).map(\.value)
        guard let value = pair.form.value(in: pair.verb.forms) else { continue }
        let entry = PoolEntry(
            verb: pair.verb, form: pair.form, value: value,
            sharesString: everyString.filter { $0 == value }.count > 1
        )
        if let question = makeQuestion(entry, topics: allTopics, verbs: verbs, kinds: kinds) {
            questions.append(question)
        }
    }
    return questions
}

private struct PoolEntry {
    let verb: Verb
    let form: QuizForm
    let value: String
    /// Another form of the same verb has the same string.
    let sharesString: Bool
}

/// One question for a pool entry, or nil when it cannot get a distractor.
/// `topics` are the topics whose forms of the same verb serve as distractors.
private func makeQuestion(
    _ entry: PoolEntry, topics: Set<QuizTopic>, verbs: [Verb], kinds: [QuizQuestionKind]
) -> QuizQuestion? {
    func pick(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return Array(candidates.shuffled().filter { seen.insert($0).inserted }.prefix(3))
    }

    let sameVerb = QuizForm.available(in: entry.verb.forms, topics: topics)
        .filter { $0.form != entry.form }
    let allowed = entry.sharesString ? kinds.filter { $0 != .identify } : kinds
    guard let kind = allowed.randomElement() else { return nil }

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

    guard !distractors.isEmpty else { return nil }
    return QuizQuestion(
        verb: entry.verb, form: entry.form, kind: kind, formString: entry.value,
        correct: correct, choices: ([correct] + distractors).shuffled()
    )
}
