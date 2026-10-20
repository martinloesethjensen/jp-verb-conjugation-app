import XCTest
@testable import VerbKit

final class CounterQuestionTests: XCTestCase {
    private static let bases = ["いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう", "じゅう", "なん"]

    private func make(
        _ id: String, _ written: String, _ reading: String, _ meaning: String, sound: String = "plain",
        readings: [String: [String]] = [:], distractors: [String: [String]] = [:], changed: [String] = [],
        things: [CountedThing] = [], countsObjects: Bool = true
    ) -> Counter {
        var all: [String: [String]] = [:]
        for (key, base) in zip(CounterNumber.allCases.map(\.key), Self.bases) { all[key] = [base + reading] }
        all.merge(readings) { _, new in new }
        return Counter(
            id: id, counter: written, reading: reading, meaning: meaning, jlpt: .n5, sound: sound, symbol: "circle",
            readings: all, changed: changed, distractors: distractors, countsObjects: countsObjects, things: things
        )
    }

    private func thing(_ word: String, _ meaning: String, _ fit: CounterFit) -> CountedThing {
        CountedThing(word: word, kana: word, meaning: meaning, fit: fit, symbol: "star")
    }

    private lazy var hon = make(
        "hon", "本", "ほん", "long, thin things", sound: "h-b",
        readings: ["1": ["いっぽん"], "3": ["さんぼん"], "6": ["ろっぽん"], "8": ["はっぽん", "はちほん"],
                   "10": ["じゅっぽん"], "what": ["なんぼん"]],
        distractors: ["3": ["さんほん", "さんぽん", "さっぽん"], "1": ["いちほん", "いっぼん"]],
        changed: ["1", "3", "6", "8", "10", "what"],
        things: [thing("傘", "umbrella", .primary), thing("ビール", "beer", .primary)]
    )
    private lazy var hai = make("hai", "杯", "はい", "cups and glasses",
                                things: [thing("ビール", "beer", .primary), thing("コーヒー", "coffee", .primary)])
    private lazy var hiki = make("hiki", "匹", "ひき", "small animals", things: [thing("うさぎ", "rabbit", .acceptable)])
    private lazy var wa = make("wa", "羽", "わ", "birds and rabbits", things: [thing("うさぎ", "rabbit", .primary)])
    private lazy var nin = make(
        "nin", "人", "にん", "people", sound: "irregular",
        readings: ["1": ["ひとり"], "2": ["ふたり"], "3": ["さんにん"], "4": ["よにん"], "5": ["ごにん"]],
        distractors: ["4": ["よんにん"]], things: [thing("学生", "student", .primary)]
    )
    private lazy var tsu = make("tsu", "つ", "つ", "general counter", sound: "irregular",
                                things: [thing("椅子", "chair", .casual)])
    private lazy var nichiDate = make(
        "nichi-date", "日", "にち", "day of the month", sound: "irregular",
        readings: ["1": ["ついたち"]], distractors: ["1": ["いちにち"]]
    )
    private lazy var nichiDays = make(
        "nichi-days", "日", "にち", "number of days", sound: "irregular", readings: ["1": ["いちにち"]]
    )
    private lazy var all = [hon, hai, hiki, wa, nin, tsu, nichiDate, nichiDays]
    private lazy var longGroup = CounterGroup(
        id: "long", title: "Long", symbol: "pencil", summary: "s",
        members: [CounterGroupMember(counter: "hon"), CounterGroupMember(counter: "hiki")]
    )

    private func choice(_ counters: [Counter]? = nil, count: Int = 200) -> [CounterQuestion] {
        buildCounterQuestions(counters: counters ?? all, groups: [longGroup], kind: .counterChoice, count: count)
    }

    private func reading(_ counters: [Counter]? = nil, count: Int = 200) -> [CounterQuestion] {
        buildCounterQuestions(counters: counters ?? all, groups: [longGroup], kind: .counterReading, count: count)
    }

    // MARK: Which counter?

    func testAWordWithTwoPrimaryCountersAcceptsBothAndShowsOnlyOne() throws {
        let beer = try XCTUnwrap(choice().first { $0.prompt == "ビール" })
        XCTAssertEqual(beer.accepted, ["本", "杯"])
        XCTAssertEqual(beer.choices.count, 4)
        XCTAssertEqual(beer.choices.filter { beer.accepted.contains($0) }.count, 1)
        XCTAssertTrue(beer.accepted.contains(beer.correct))
        XCTAssertEqual(beer.kind, .counterChoice)
        XCTAssertEqual(beer.formID, "ビール")
        XCTAssertEqual(beer.detail, "beer")
        XCTAssertEqual(beer.symbol, "star")
    }

    func testAnAcceptableCounterIsNeitherRightNorOfferedWhenAPrimaryOneExists() throws {
        let rabbit = try XCTUnwrap(choice().first { $0.prompt == "うさぎ" })
        XCTAssertEqual(rabbit.accepted, ["羽"])
        XCTAssertEqual(rabbit.counterID, "wa")
        XCTAssertFalse(rabbit.choices.contains("匹"))
    }

    func testAWordWithOnlyACasualCounterMakesNoQuestion() {
        XCTAssertNil(choice().first { $0.prompt == "椅子" })
    }

    func testThingsOfACounterThatMeasuresRatherThanCountsMakeNoQuestionAndAreNeverOffered() throws {
        // 結婚 under 年 (years of marriage) is as natural with 回: it is not a thing 年 counts.
        let nen = make("nen", "年", "ねん", "years", things: [thing("結婚", "marriage", .primary)], countsObjects: false)
        let kai = make("kai", "回", "かい", "times", things: [thing("試験", "exam", .primary)], countsObjects: false)
        let questions = choice(all + [nen, kai])
        XCTAssertNil(questions.first { $0.prompt == "結婚" })
        XCTAssertNil(questions.first { $0.prompt == "試験" })
        XCTAssertFalse(questions.isEmpty)
        XCTAssertFalse(questions.contains { $0.choices.contains("年") || $0.choices.contains("回") })
        // Read it still covers them: it asks about the counter's own readings.
        XCTAssertFalse(reading([nen]).isEmpty)
    }

    func testWrongCountersFromTheSameGroupComeFirst() throws {
        let umbrella = try XCTUnwrap(choice().first { $0.prompt == "傘" })
        // 本's group holds 匹; 杯 and 羽 follow in input order; 人 and つ are left out.
        XCTAssertEqual(Set(umbrella.choices), ["本", "匹", "杯", "羽"])
    }

    func testTheExplanationNamesEveryRightCounter() throws {
        let umbrella = try XCTUnwrap(choice().first { $0.prompt == "傘" })
        XCTAssertEqual(umbrella.explanation, "傘 is counted with 本 (long, thin things)")
        let beer = try XCTUnwrap(choice().first { $0.prompt == "ビール" })
        XCTAssertEqual(beer.explanation, "ビール is counted with 本 (long, thin things) or 杯 (cups and glasses)")
    }

    func testFewCountersMeanFewChoicesAndOneCounterMeansNoQuestion() throws {
        let two = choice([hon, hai])
        let umbrella = try XCTUnwrap(two.first { $0.prompt == "傘" })
        XCTAssertEqual(Set(umbrella.choices), ["本", "杯"])
        XCTAssertNil(two.first { $0.prompt == "ビール" }, "ビール is right under both, so nothing is left to offer")
        XCTAssertTrue(choice([hon]).isEmpty)
    }

    // MARK: Read it

    func testReadItPromptsTheCountedFormAndOffersTheGeneratedWrongReadings() throws {
        let q = try XCTUnwrap(reading().first { $0.counterID == "hon" && $0.formID == "3" })
        XCTAssertEqual(q.kind, .counterReading)
        XCTAssertEqual(q.prompt, "三本")
        XCTAssertEqual(q.detail, "long, thin things")
        XCTAssertEqual(q.correct, "さんぼん")
        XCTAssertEqual(q.choices.count, 4)
        XCTAssertEqual(Set(q.choices), ["さんぼん", "さんほん", "さんぽん", "さっぽん"])
        XCTAssertTrue(q.explanation.hasPrefix("本 changes at 1, 3, 6, 8, 10 and 何"))
        XCTAssertTrue(q.explanation.hasSuffix(": さんぼん"))
    }

    func testEveryAcceptedReadingIsRightAndNoWrongChoiceIsOne() throws {
        let q = try XCTUnwrap(reading().first { $0.counterID == "hon" && $0.formID == "8" })
        XCTAssertEqual(q.accepted, ["はっぽん", "はちほん"])
        XCTAssertEqual(q.correct, "はっぽん")
        XCTAssertEqual(q.choices.filter { q.accepted.contains($0) }, ["はっぽん"])
        XCTAssertFalse(q.choices.contains("はちほん"), "the other right reading is never offered as a wrong choice")
    }

    func testTheSameWrittenFormOnTwoCountersAsksTwoDifferentQuestions() throws {
        let date = try XCTUnwrap(reading().first { $0.counterID == "nichi-date" && $0.formID == "1" })
        let days = try XCTUnwrap(reading().first { $0.counterID == "nichi-days" && $0.formID == "1" })
        XCTAssertEqual(date.prompt, "一日")
        XCTAssertEqual(days.prompt, "一日")
        XCTAssertEqual(date.detail, "day of the month")
        XCTAssertEqual(days.detail, "number of days")
        XCTAssertEqual(date.accepted, ["ついたち"])
        XCTAssertEqual(days.accepted, ["いちにち"])
        XCTAssertTrue(date.choices.contains("いちにち"), "the other counter's reading is the classic wrong answer")
    }

    func testACounterWithoutGeneratedWrongReadingsIsFilledFromNearbyNumbers() throws {
        let q = try XCTUnwrap(reading().first { $0.counterID == "nin" && $0.formID == "4" })
        XCTAssertEqual(q.choices.count, 4)
        XCTAssertTrue(q.choices.contains("よんにん"))
        XCTAssertTrue(q.choices.contains("さんにん"), "the nearest number's reading fills a gap")
        XCTAssertEqual(q.choices.filter { q.accepted.contains($0) }, ["よにん"])
        XCTAssertEqual(q.explanation, "人 is irregular: learn each reading. 四人 is よにん")
    }

    func testANumberThatDoesNotChangeSaysSoInsteadOfClaimingItChanges() throws {
        let q = try XCTUnwrap(reading().first { $0.counterID == "hon" && $0.formID == "2" })
        XCTAssertEqual(q.explanation, "本 keeps its plain reading at 2: にほん. It changes at 1, 3, 6, 8, 10 and 何.")
        let changing = try XCTUnwrap(reading().first { $0.counterID == "hon" && $0.formID == "3" })
        XCTAssertEqual(changing.explanation, "本 changes at 1, 3, 6, 8, 10 and 何: さんぼん")
    }

    func testAPlainCounterExplainsThatNothingChanges() throws {
        let tidy = make("mai", "枚", "まい", "flat things", distractors: ["3": ["さっまい"]])
        let q = try XCTUnwrap(reading([tidy]).first { $0.formID == "3" })
        XCTAssertEqual(q.explanation, "枚 has no sound changes: さんまい")
    }

    func testReadItNeedsAtLeastOneWrongChoice() {
        let lone = make("x", "枚", "まい", "m", readings: [:], distractors: [:])
        // Every other number's reading differs, so fillers exist: all eleven keys still make questions.
        XCTAssertEqual(reading([lone]).count, 11)
        let same = make("y", "枚", "まい", "m", readings: Dictionary(
            uniqueKeysWithValues: CounterNumber.allCases.map { ($0.key, ["おなじ"]) }
        ))
        XCTAssertTrue(reading([same]).isEmpty, "no wrong reading can be found when every number reads alike")
    }

    // MARK: Count and practising one counter

    func testCountCapsAndPractiseOneCounterAsksReadingsOfThatCounterOnly() {
        XCTAssertEqual(choice(count: 2).count, 2)
        XCTAssertEqual(reading(count: 5).count, 5)
        let practise = buildCounterQuestions(for: hon, count: 100)
        XCTAssertEqual(practise.count, 11)
        XCTAssertTrue(practise.allSatisfy { $0.counterID == "hon" && $0.kind == .counterReading })
        XCTAssertEqual(Set(practise.map(\.formID)), Set(CounterNumber.allCases.map(\.key)))
        XCTAssertEqual(buildCounterQuestions(for: hon, count: 3).count, 3)
    }

    func testPairsAreAskedInOrderUnshuffledAndSkippedWhenNothingIsWrong() {
        let questions = buildCounterQuestions(
            pairs: [(nin, .n(4)), (hon, .n(3)), (hon, .what)], count: 100
        )
        XCTAssertEqual(questions.map(\.counterID), ["nin", "hon", "hon"])
        XCTAssertEqual(questions.map(\.formID), ["4", "3", "what"])
        XCTAssertTrue(questions.allSatisfy { $0.kind == .counterReading })
        XCTAssertEqual(buildCounterQuestions(pairs: [(hon, .n(3)), (nin, .n(4))], count: 1).map(\.formID), ["3"])
        let same = make("y", "枚", "まい", "m", readings: Dictionary(
            uniqueKeysWithValues: CounterNumber.allCases.map { ($0.key, ["おなじ"]) }
        ))
        XCTAssertTrue(buildCounterQuestions(pairs: [(same, .n(3))], count: 5).isEmpty)
        XCTAssertTrue(buildCounterQuestions(pairs: [], count: 5).isEmpty)
    }

    func testOtherKindsBuildNothing() {
        XCTAssertTrue(buildCounterQuestions(counters: all, groups: [], kind: .conjugate, count: 10).isEmpty)
    }
}
