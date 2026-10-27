/// Wrong answers a learner could really write, derived from a verb's dictionary form, type and
/// て-group. Only the cases the data supports reliably are made; nothing here changes `data/`.
/// The caller drops any string equal to the right answer or to a real form of the verb.
func syntheticDistractors(for verb: Verb, form: QuizForm) -> [(value: String, tag: QuizErrorTag)] {
    let dict = verb.dict
    guard dict.count > 1 else { return [] }
    let stem = String(dict.dropLast())
    var result: [(String, QuizErrorTag)] = []

    switch form.id {
    case "te":
        // Each group's ending on the stem: the other groups' endings are the wrong-group
        // mistake, and the verb's own ending on an exception (いく) is the regular-rule mistake.
        guard verb.type == .u, verb.teGroup != nil else { break }
        for rule in TeFormRule.all {
            result.append((stem + rule.result, .wrongTeGroup(rule.group)))
        }
    case "short_neg", "masu_pos", "masu_neg":
        let ruEnding = ["short_neg": "ない", "masu_pos": "ます", "masu_neg": "ません"][form.id]!
        let uEnding = ["short_neg": "らない", "masu_pos": "ります", "masu_neg": "りません"][form.id]!
        if verb.type == .ru, dict.hasSuffix("る") {
            result.append((stem + uEnding, .ruUConfusion))
        } else if verb.type == .u,
                  RuLookalike.all.contains(where: { $0.kana == dict && $0.kanji == verb.kanji }) {
            result.append((stem + ruEnding, .ruUConfusion))
        }
        if form.id == "short_neg", dict == "ある" {
            result.append(("あらない", .aruNegative))
        }
    default:
        break
    }
    return result
}

/// The form that is easily taken for this one, when the data has both as real forms.
func lookalikeTag(of form: QuizForm, chosen: QuizForm) -> QuizErrorTag? {
    let pairs: [(String, String, QuizErrorTag)] = [
        ("passive", "potential", .passivePotential),
        ("causative_passive", "causative_passive_short", .causativePassiveLongShort),
    ]
    for (a, b, tag) in pairs where (form.id == a && chosen.id == b) || (form.id == b && chosen.id == a) {
        return tag
    }
    return nil
}
