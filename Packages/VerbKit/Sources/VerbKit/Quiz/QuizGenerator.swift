/// Ported from the web app's buildQuestions: pick `count` random
/// (verb, form) pairs, then for each build up to 3 unique distractors —
/// preferring the same verb's other forms, falling back to other verbs'
/// forms — deduplicated and shuffled alongside the correct answer.
public func buildQuestions(verbs: [Verb], count: Int) -> [QuizQuestion] {
    struct PoolEntry {
        let verb: Verb
        let form: FormKey
        let correct: String
    }

    var pool: [PoolEntry] = []
    for verb in verbs {
        for form in FormKey.allCases {
            pool.append(PoolEntry(verb: verb, form: form, correct: verb.forms[form]))
        }
    }
    let selected = pool.shuffled().prefix(count)

    return selected.map { entry in
        let wrongSameVerb = FormKey.allCases
            .filter { $0 != entry.form }
            .map { entry.verb.forms[$0] }
            .filter { $0 != entry.correct }
        let wrongOtherVerbs = verbs
            .filter { $0.dict != entry.verb.dict }
            .map { $0.forms[entry.form] }
            .filter { $0 != entry.correct }

        var seen = Set<String>()
        let distractors = (wrongSameVerb + wrongOtherVerbs)
            .shuffled()
            .filter { seen.insert($0).inserted }
            .prefix(3)

        let choices = ([entry.correct] + distractors).shuffled()
        return QuizQuestion(verb: entry.verb, form: entry.form, correct: entry.correct, choices: choices)
    }
}
