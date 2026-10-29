import XCTest
@testable import VerbKit

/// Tests against the grammar half of the real published files in `data/`
/// (`RealDataFileTests` already guards `verbs.json` against its manifest
/// hash). They read the files straight from the repo checkout, so they
/// fail when someone edits the data and forgets `scripts/update_data.py`.
final class RealGrammarDataTests: XCTestCase {
    private func dataURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent(name)
    }

    private func loadVerbs() throws -> [Verb] {
        let data = try Data(contentsOf: dataURL("verbs.json"))
        return try JSONDecoder().decode(VerbDataFile.self, from: data).verbs
    }

    private func loadGrammar() throws -> [GrammarPoint] {
        let data = try Data(contentsOf: dataURL("grammar.json"))
        return try JSONDecoder().decode(GrammarDataFile.self, from: data).grammar
    }

    private func loadGrammarFile() throws -> GrammarDataFile {
        let data = try Data(contentsOf: dataURL("grammar.json"))
        return try JSONDecoder().decode(GrammarDataFile.self, from: data)
    }

    /// Issue #102: an N4-only learner sees "maybe" in the certainty lesson, and not わけ (N3).
    func testCertaintyWithOnlyN4ShowsHazuAndKamoshirenaiButNotWake() throws {
        let certainty = try XCTUnwrap(loadGrammar().first { $0.id == "certainty" })
        let onlyN4 = LevelSettings(hidden: [.n5, .n3, .n2, .n1])
        XCTAssertTrue(certainty.isVisible(in: onlyN4))
        let shown = certainty.visibleUsages(in: onlyN4).map(\.heading)
        XCTAssertTrue(shown.contains { $0.contains("かもしれない") })
        XCTAssertTrue(shown.contains { $0.hasPrefix("はず") })
        XCTAssertFalse(shown.contains { $0.contains("わけ") })
        XCTAssertEqual(certainty.levelRange, .n4 ... .n3)
    }

    func testTeiruIsN5WithTearuAtN4() throws {
        let teiru = try XCTUnwrap(loadGrammar().first { $0.id == "teiru" })
        let onlyN5 = LevelSettings(hidden: [.n4, .n3, .n2, .n1])
        XCTAssertFalse(teiru.visibleUsages(in: onlyN5).contains { $0.heading.contains("てある") })
        XCTAssertEqual(teiru.levelRange, .n5 ... .n4)
    }

    func testEveryLessonRefPointsAtAKnownBookAndLesson() throws {
        let file = try loadGrammarFile()
        XCTAssertEqual(Set(file.books.map(\.id)), ["genki-1", "genki-2"])
        let booksByID = Dictionary(uniqueKeysWithValues: file.books.map { ($0.id, $0) })
        var refs = 0
        for point in file.grammar {
            for ref in point.taughtIn {
                let book = try XCTUnwrap(booksByID[ref.book], "\(point.id) -> \(ref.book)")
                XCTAssertTrue(book.contains(lesson: ref.lesson), "\(point.id) \(ref.book) L\(ref.lesson)")
                refs += 1
            }
        }
        XCTAssertGreaterThan(refs, 0)
    }

    func testEveryVerbHasNdFormsBuiltFromItsPlainForms() throws {
        let verbs = try loadVerbs()
        XCTAssertFalse(verbs.isEmpty)
        for verb in verbs {
            let f = verb.forms
            XCTAssertEqual(f.ndPos, f.shortPos + "んです", verb.dict)
            XCTAssertEqual(f.ndNeg, f.shortNeg + "んです", verb.dict)
            XCTAssertEqual(f.ndPast, f.shortPast + "んです", verb.dict)
            XCTAssertEqual(f.ndPastNeg, f.shortPastNeg + "んです", verb.dict)
            XCTAssertEqual(f.ndCasualPos, f.shortPos + "んだ", verb.dict)
            XCTAssertEqual(f.ndCasualNeg, f.shortNeg + "んだ", verb.dict)
            XCTAssertEqual(f.ndCasualPast, f.shortPast + "んだ", verb.dict)
            XCTAssertEqual(f.ndCasualPastNeg, f.shortPastNeg + "んだ", verb.dict)
        }
    }

    /// Hand-verified values, one per verb class: ichidan, godan, and both irregulars.
    func testNdFormsSpotChecks() throws {
        let verbs = try loadVerbs()
        func forms(_ dict: String) throws -> VerbForms {
            try XCTUnwrap(verbs.first { $0.dict == dict }, dict).forms
        }
        XCTAssertEqual(try forms("たべる").ndPastNeg, "たべなかったんです")
        XCTAssertEqual(try forms("かう").ndNeg, "かわないんです")
        XCTAssertEqual(try forms("かう").ndPast, "かったんです")
        XCTAssertEqual(try forms("する").ndCasualPos, "するんだ")
        XCTAssertEqual(try forms("くる").ndNeg, "こないんです")
        XCTAssertEqual(try forms("くる").ndPast, "きたんです")
    }

    func testGrammarFileDecodesAndContainsNDesu() throws {
        let points = try loadGrammar()
        let nDesu = try XCTUnwrap(points.first { $0.id == GrammarPoint.nDesuID })
        XCTAssertEqual(nDesu.title, "んです")
        XCTAssertEqual(nDesu.usages.count, 7)
        XCTAssertEqual(nDesu.attachment.count, 6)
        XCTAssertEqual(nDesu.pitfalls.count, 3)
        XCTAssertTrue(nDesu.conjugations.contains { $0.form == "の" && $0.register == .casual })
    }

    func testGrammarIDsAreUniqueAndRelatedIDsExist() throws {
        let points = try loadGrammar()
        let ids = points.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for point in points {
            for related in point.related {
                XCTAssertTrue(ids.contains(related), "\(point.id) -> \(related)")
            }
        }
    }

    func testManifestGrammarHashMatchesTheGrammarFile() throws {
        let manifestData = try Data(contentsOf: dataURL("manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let grammar = try XCTUnwrap(manifest["grammar"] as? [String: String], "manifest.json has no grammar block")
        XCTAssertEqual(grammar["sha256"], sha256Hex(of: try Data(contentsOf: dataURL("grammar.json"))))
    }

    func testEveryVerbHasItsMasuStem() throws {
        for verb in try loadVerbs() {
            XCTAssertFalse(verb.forms.stem.isEmpty, verb.dict)
            XCTAssertEqual(verb.forms.stem + "ます", verb.forms.masuPos, verb.dict)
        }
    }

    private func loadWords() throws -> [Word] {
        try JSONDecoder().decode(WordsDataFile.self, from: Data(contentsOf: dataURL("words.json"))).words
    }

    func testWordsFileMatchesTheManifestAndDecodes() throws {
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: dataURL("manifest.json"))) as? [String: Any]
        let entry = try XCTUnwrap(manifest?["words"] as? [String: Any])
        XCTAssertEqual(entry["sha256"] as? String, sha256Hex(of: try Data(contentsOf: dataURL("words.json"))))
        let words = try loadWords()
        XCTAssertGreaterThanOrEqual(words.count, 30)
        XCTAssertEqual(Set(words.map(\.wordClass)), [.iAdjective, .naAdjective, .noun])
    }

    /// Every rule with an ending builds a pattern for every eligible word of its class and
    /// every slot it lists, so the cards and the quiz never meet a missing form. A verb is
    /// ineligible only when it lacks the form the rule spells out (わかる has no ましょう).
    func testEverySlotRuleBuildsForEveryEligibleWordOfItsClass() throws {
        let verbs = try loadVerbs()
        let words = try loadWords()
        var built = 0
        for point in try loadGrammar() {
            for rule in point.attachment where rule.then != nil {
                for slot in rule.slots {
                    let sources: [SlotSource] = rule.wordClass == .verb
                        ? rule.eligibleVerbs(slot, among: verbs)
                        : words.filter { $0.wordClass == rule.wordClass }
                    for word in sources {
                        XCTAssertNotNil(rule.build(word, slot: slot), "\(point.id) \(rule.wordClass) \(slot) \(word.dict)")
                        built += 1
                    }
                    guard rule.wordClass == .verb else { continue }
                    let practised = rule.practisedForms(slot, among: verbs)
                    let skipped = Set(verbs.map(\.id)).subtracting(sources.map(\.stableKey))
                    for verb in verbs where skipped.contains(verb.id) {
                        XCTAssertTrue(practised.contains { $0.value(in: verb.forms) == nil },
                                      "\(point.id) \(slot) skips \(verb.dict), which has every form it spells out")
                    }
                }
            }
        }
        XCTAssertGreaterThan(built, 200)
    }

    /// The forms the data leaves out (scripts/update_data.py, PARTIAL_OTHER_FORMS) are never
    /// asked: わかる, しる and つかれる are not volitional, so they have no ましょう form.
    func testTheVolitionalRuleSkipsVerbsWithoutAMasuVolitional() throws {
        let verbs = try loadVerbs()
        let volitional = try XCTUnwrap(try loadGrammar().first { $0.id == "volitional" })
        let rule = try XCTUnwrap(volitional.attachment.first { $0.then == "ましょう" })
        XCTAssertEqual(rule.practisedForms(.stem, among: verbs).map(\.id), ["masu_volitional"])
        let skipped = Set(verbs.map(\.dict)).subtracting(rule.eligibleVerbs(.stem, among: verbs).map(\.dict))
        XCTAssertEqual(skipped, ["わかる", "しる", "つかれる", "くれる", "できる", "みえる", "きこえる", "あく", "おくれる", "ふる"])

        let never: Set<String> = ["わかりましょう", "しりましょう", "つかれましょう", "くれましょう", "できましょう",
                                  "みえましょう", "きこえましょう", "あきましょう", "おくれましょう", "ふりましょう"]
        for _ in 0..<5 {
            let questions = buildConnectionQuestions(points: [volitional], verbs: verbs, words: [], count: verbs.count)
            XCTAssertGreaterThan(questions.count, 20)
            XCTAssertTrue(never.isDisjoint(with: questions.map(\.correct)), "\(questions.map(\.correct))")
        }
    }

    /// Spot checks a learner would recognise, one per tricky rule.
    func testBuiltPatternsSpotChecks() throws {
        let points = Dictionary(uniqueKeysWithValues: try loadGrammar().map { ($0.id, $0) })
        let words = try loadWords()
        let verbs = try loadVerbs()
        func build(_ id: String, _ dict: String, _ slot: GrammarSlot) throws -> String? {
            let source: SlotSource = try XCTUnwrap(verbs.first { $0.dict == dict } ?? words.first { $0.dict == dict }, dict)
            let rules = try XCTUnwrap(points[id], id).attachment
            return rules.lazy.compactMap { $0.build(source, slot: slot) }.first
        }
        XCTAssertEqual(try build("node", "しずか", .plain), "しずかなので")
        XCTAssertEqual(try build("node", "あめ", .plainPast), "あめだったので")
        XCTAssertEqual(try build("node", "たかい", .plainNeg), "たかくないので")
        XCTAssertEqual(try build("hou-ga-ii", "ねる", .plainPast), "ねたほうがいいです")
        XCTAssertEqual(try build("hou-ga-ii", "たべる", .plainNeg), "たべないほうがいいです")
        XCTAssertEqual(try build("sugiru", "いい", .stem), "よすぎる")
        XCTAssertEqual(try build("sugiru", "からい", .stem), "からすぎる")
        XCTAssertEqual(try build("n-desu", "がくせい", .plain), "がくせいなんです")
        XCTAssertEqual(try build("n-desu", "しずか", .plainPast), "しずかだったんです")
    }

    func testTheNewLessonsExistWithContrasts() throws {
        let points = try loadGrammar()
        for id in ["node", "hou-ga-ii"] {
            let point = try XCTUnwrap(points.first { $0.id == id }, id)
            XCTAssertFalse(point.contrasts.isEmpty, id)
        }
    }

    /// Every lesson with an ending yields a full connection quiz from the real verbs and
    /// words, each question with its answer among distinct choices.
    func testConnectionQuestionsBuildFromTheRealData() throws {
        let points = try loadGrammar().filter(\.hasConnections)
        XCTAssertEqual(Set(points.map(\.id)), ["n-desu", "sugiru", "node", "hou-ga-ii", "tai", "volitional", "nai-te", "te-mo-ii"])
        let verbs = try loadVerbs()
        let words = try loadWords()
        for point in points {
            let questions = buildConnectionQuestions(points: [point], verbs: verbs, words: words, count: 20)
            XCTAssertEqual(questions.count, 20, point.id)
            for question in questions {
                XCTAssertTrue(question.choices.contains(question.correct), "\(point.id) \(question.correct)")
                XCTAssertGreaterThanOrEqual(question.choices.count, 2)
                XCTAssertEqual(Set(question.choices).count, question.choices.count)
            }
        }
    }
}
