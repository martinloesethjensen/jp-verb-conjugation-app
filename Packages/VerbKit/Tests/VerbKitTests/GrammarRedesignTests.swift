import XCTest
@testable import VerbKit

final class GrammarRedesignTests: XCTestCase {
    private static let grammar = BundledData<GrammarDataFile>.load(named: "grammar")!.value.grammar
    private static let verbs = BundledData<VerbDataFile>.load(named: "verbs")!.value.verbs

    private func point(_ id: String) -> GrammarPoint { Self.grammar.first { $0.id == id }! }

    // MARK: Highlight

    func testHighlightPicksTheLongestFirstMatch() {
        XCTAssertEqual(GrammarHighlight.range(in: "雨が降るかもしれない。", patterns: ["かもしれない", "かも"]), 4..<10)
    }

    func testHighlightIsNilWhenAbsent() {
        XCTAssertNil(GrammarHighlight.range(in: "雨です。", patterns: ["はず"]))
        XCTAssertNil(GrammarHighlight.range(in: "雨です。", patterns: []))
    }

    func testPatternsComeFromEndingsAndTitle() {
        let patterns = GrammarHighlight.patterns(of: point("certainty"))
        XCTAssertTrue(Set(["はず", "かもしれない", "わけ"]).isSubset(of: Set(patterns)), "\(patterns)")
        XCTAssertEqual(patterns, patterns.sorted { $0.count > $1.count }, "longest first")
        XCTAssertTrue(GrammarHighlight.patterns(of: point("te-mo-ii")).contains("もいい"))
    }

    func testPatternsIncludeTheLessonsForms() {
        // The polite form 〜かもしれません comes from the lesson's conjugations, not its title.
        let patterns = GrammarHighlight.patterns(of: point("certainty"))
        XCTAssertEqual(GrammarHighlight.range(in: "山田さんは来ないかもしれません。", patterns: patterns), 8..<15)
    }

    func testPatternsSkipSingleCharacters() {
        // 命令形・〜な・〜なさい: a lone な would underline every な in a sentence.
        XCTAssertFalse(GrammarHighlight.patterns(of: point("imperative")).contains("な"))
    }

    // MARK: Mistakes

    func testMistakeMarksTheDifferingMiddle() {
        XCTAssertEqual(MistakeMark.wrongRange(wrong: "学生だかもしれない", right: "学生かもしれない"), 2..<3)
        XCTAssertEqual(MistakeMark.wrongRange(wrong: "静かだので", right: "この部屋は静かなので、よく眠れます。"), 2..<3)
    }

    func testMistakeMarksEverythingWhenNothingIsShared() {
        XCTAssertEqual(MistakeMark.wrongRange(wrong: "静かだので", right: "ぜんぜん違う文です"), 0..<5)
        XCTAssertEqual(MistakeMark.wrongRange(wrong: "静かだので", right: nil), 0..<5)
    }

    // MARK: Formula

    func testFormulaIsNilWithoutAnyPattern() {
        XCTAssertNil(point("verb-pairs").formula)
    }

    func testFormulaListsEveryEndingOnceFromSlottedRules() throws {
        let formula = try XCTUnwrap(point("te-mo-ii").formula)
        XCTAssertEqual(formula.base, .slot(.te))
        XCTAssertEqual(formula.endings, ["もいい", "はいけない"])
    }

    func testFormulaKeepsEverySlotOfItsRule() throws {
        let formula = try XCTUnwrap(point("node").formula)
        XCTAssertEqual(formula.slots, [.plain, .plainNeg, .plainPast, .plainPastNeg])
        XCTAssertTrue(formula.isPlainForm)
        XCTAssertFalse(try XCTUnwrap(point("te-mo-ii").formula).isPlainForm)
    }

    func testFormulaFallsBackToTheWrittenPattern() throws {
        let formula = try XCTUnwrap(point("certainty").formula)
        XCTAssertEqual(formula.base, .text("plain form"))
        XCTAssertEqual(formula.endings, ["はず", "かもしれない", "わけ"])
        XCTAssertEqual(formula.examples["はず"], "行くはず")
    }

    // MARK: Attachment example

    func testExampleBuildsFromTheRule() throws {
        let rule = try XCTUnwrap(point("node").attachment.first { $0.wordClass == .verb && !$0.slots.isEmpty })
        let eligible = Dictionary(rule.slots.map { ($0, Set(rule.eligibleVerbs($0, among: Self.verbs).map(\.stableKey))) },
                                  uniquingKeysWith: { first, _ in first })
        let example = try XCTUnwrap(rule.example(from: Self.verbs, eligible: eligible, offset: 0))
        XCTAssertTrue(example.built.hasSuffix("ので"), example.built)
        XCTAssertTrue(example.built.hasPrefix(String(example.base.prefix(1))))
    }

    // MARK: Forms table

    func testRowsPadTheShorterColumn() {
        let rows = ConjugationTable.rows([
            GrammarConjugation(form: "はずです", register: .polite),
            GrammarConjugation(form: "はずがありません", register: .polite),
            GrammarConjugation(form: "はずだ", register: .casual),
        ])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].polite?.form, "はずです")
        XCTAssertEqual(rows[0].casual?.form, "はずだ")
        XCTAssertNil(rows[1].casual)
        let casualOnly = ConjugationTable.rows([GrammarConjugation(form: "かも", register: .casual)])
        XCTAssertEqual(casualOnly.count, 1)
        XCTAssertNil(casualOnly[0].polite)
    }
}
