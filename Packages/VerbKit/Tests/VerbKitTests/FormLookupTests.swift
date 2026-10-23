import XCTest
@testable import VerbKit

/// "What form is this?" (#110) on the real verbs: the display items `FormLookup` builds from
/// the matcher's spans, the Word Bank's dictionary-form offer and `FormLookupStore`'s index
/// lifetime. Tokens are fixed, as in `VerbMatcherTests`, except in the single-word tests,
/// which run the real `CFStringTokenizer` because that is what the app sends one word through.
@MainActor
final class FormLookupTests: XCTestCase {
    private static var verbs: [Verb] = []
    private static var index: FormIndex!

    override class func setUp() {
        super.setUp()
        verbs = (try? RealVerbs.load()) ?? []
        index = FormIndex(verbs: verbs, catalogue: .bundled)
    }

    private func items(_ tokens: String) -> [FormLookup.Item] {
        let tokenizer = FixedTokenizer([tokens])
        let text = tokenizer.tokens.keys.first ?? ""
        let spans = VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: tokenizer).spans(in: text)
        return FormLookup(verbs: Self.verbs, catalogue: .bundled).items(for: spans)
    }

    private func verb(_ id: String) throws -> Verb {
        try XCTUnwrap(Self.verbs.first { $0.id == id })
    }

    // MARK: Readings

    func testAChainIsLabelledPartByPartAndMarksTheRuleBuiltEnding() throws {
        let item = try XCTUnwrap(items("食べ させ られ なかっ た").first)
        XCTAssertEqual(item.status, .known)
        let reading = try XCTUnwrap(item.readings.first)
        XCTAssertEqual(reading.verb, try verb("たべる"))
        XCTAssertNil(reading.formID)
        XCTAssertEqual(reading.label, "Causative-passive + Plain · past · negative")
        XCTAssertEqual(reading.parts.map(\.surface), ["食べさせられ", "なかった"])
        XCTAssertEqual(reading.parts.map(\.isRuleBuilt), [false, true])
        XCTAssertTrue(reading.isRuleBuilt)
    }

    func testAnExactFormHasTheCatalogueLabel() throws {
        let reading = try XCTUnwrap(items("飲み まし た").first?.readings.first)
        XCTAssertEqual(reading.formID, "masu_past")
        XCTAssertEqual(reading.label, "Polite · past")
        XCTAssertFalse(reading.isRuleBuilt)
        XCTAssertEqual(reading.parts.count, 1)
    }

    func testLessonsComeFromThePartsForms() throws {
        let potential = try XCTUnwrap(items("泳げ ます").first?.readings.first)
        XCTAssertEqual(potential.lessonIDs, ["potential"])
        // て-form + a polite ている: the ている lesson, once.
        let teiru = try XCTUnwrap(items("食べ て い ます").first?.readings.first)
        XCTAssertEqual(teiru.lessonIDs, ["teiru"])
        // The basic forms have no lesson.
        XCTAssertEqual(try XCTUnwrap(items("飲み まし た").first?.readings.first).lessonIDs, [])
    }

    func testAnAuxiliaryPartKeepsTheMatchersLabelAndTakesItsFormsLesson() throws {
        let reading = try XCTUnwrap(items("忘れ て しまい まし た").first?.readings.first)
        XCTAssertEqual(reading.parts.last?.label, "てしまう · polite past")
        XCTAssertEqual(reading.parts.last?.lessonID, "teshimau")
        XCTAssertEqual(reading.lessonIDs, ["teshimau"])
        // です has no catalogue form, so no lesson.
        let desu = try XCTUnwrap(items("食べ たい です").first?.readings.first)
        XCTAssertNil(desu.parts.last?.lessonID)
    }

    func testAnAmbiguousSpanListsEveryReading() throws {
        let item = try XCTUnwrap(items("きた").first)
        XCTAssertEqual(item.status, .ambiguous)
        XCTAssertGreaterThanOrEqual(item.readings.count, 2)
        XCTAssertEqual(Set(item.verbs.map(\.dict)), ["くる", "きる"])
        XCTAssertEqual(Set(item.readings.map(\.id)).count, item.readings.count, "reading ids must be unique for the picker")
    }

    func testAVerbNotInTheAppHasGuessesAndNoReadings() throws {
        let item = try XCTUnwrap(items("雨 が 降っ たら").first)
        XCTAssertEqual(item.status, .notInApp)
        XCTAssertEqual(item.surface, "降ったら")
        XCTAssertEqual(item.readings, [])
        XCTAssertEqual(item.guesses.first, "降る")
    }

    func testTheDictionaryFormIsFlagged() throws {
        XCTAssertEqual(items("食べる").first?.readings.first?.isDictionaryForm, true)
        XCTAssertEqual(items("食べ た").first?.readings.first?.isDictionaryForm, false)
    }

    func testACandidateForAVerbThatIsGoneIsDropped() {
        let span = VerbSpan(
            range: "x".startIndex..<"x".endIndex, surface: "x", status: .known,
            candidates: [VerbCandidate(verbID: "no-such-verb", chain: [ChainPart(surface: "x", kind: .form("te"), isRuleBuilt: false)])]
        )
        XCTAssertEqual(FormLookup(verbs: Self.verbs, catalogue: .bundled).items(for: [span]), [])
    }

    // MARK: Word Bank

    func testTheWordBankOffersTheDictionaryFormOfAWholeConjugatedVerb() throws {
        let text = "食べさせられなかった"
        XCTAssertEqual(FormLookup.dictionaryForms(of: text, in: items("食べ させ られ なかっ た")), [try verb("たべる")])
        XCTAssertEqual(FormLookup.dictionaryForms(of: " 食べさせられなかった\n", in: items("食べ させ られ なかっ た")), [try verb("たべる")])
    }

    func testTheWordBankOffersNothingForTheDictionaryFormASentenceOrAnUnknownVerb() {
        XCTAssertEqual(FormLookup.dictionaryForms(of: "食べる", in: items("食べる")), [])
        XCTAssertEqual(FormLookup.dictionaryForms(of: "野菜を食べた", in: items("野菜 を 食べ た")), [])
        XCTAssertEqual(FormLookup.dictionaryForms(of: "降ったら", in: items("降っ たら")), [])
        XCTAssertEqual(FormLookup.dictionaryForms(of: "", in: []), [])
    }

    // MARK: Furigana and links

    func testTheDictionaryFormAsRubyUnits() throws {
        XCTAssertEqual(try verb("たべる").dictionaryUnits, [TextUnit(text: "食", reading: "た"), TextUnit(text: "べる")])
        XCTAssertEqual(try verb("くる").dictionaryUnits, [TextUnit(text: "来", reading: "く"), TextUnit(text: "る")])
        XCTAssertEqual(try verb("する").dictionaryUnits, [TextUnit(text: "する")])
    }

    func testTheSuggestAVerbLinkPrefillsTheGuess() {
        XCTAssertEqual(IssueReportURL.suggestVerb().absoluteString,
                       "https://github.com/martinloesethjensen/jp-verb-conjugation-app/issues/new?template=add-verb.yml")
        let url = IssueReportURL.suggestVerb(kanji: "降る")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "kanji" }?.value, "降る")
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "[VERB] 降る — ")
        XCTAssertEqual(items.first { $0.name == "template" }?.value, "add-verb.yml")
    }

    // MARK: Store

    func testTheStoreBuildsTheIndexOnceForTheSameData() {
        let store = FormLookupStore()
        XCTAssertFalse(store.isReady)
        XCTAssertEqual(store.items(in: "食べた"), [])
        store.update(verbs: [], verbsVersion: nil)
        XCTAssertFalse(store.isReady)
        store.update(verbs: Self.verbs, verbsVersion: "1.0.0")
        store.update(verbs: Self.verbs, verbsVersion: "1.0.0")
        XCTAssertTrue(store.isReady)
        XCTAssertEqual(store.builds, 1)
        store.update(verbs: Self.verbs, verbsVersion: "1.0.1")
        XCTAssertEqual(store.builds, 2)
        store.update(verbs: Self.verbs, verbsVersion: "1.0.1", catalogueVersion: "2")
        XCTAssertEqual(store.builds, 3)
        // Without a recorded version the verb ids stand in for it.
        store.update(verbs: Self.verbs, verbsVersion: nil)
        store.update(verbs: Self.verbs, verbsVersion: nil)
        XCTAssertEqual(store.builds, 4)
    }

    func testOneTypedWordWithTheSystemTokenizer() throws {
        let store = FormLookupStore()
        store.update(verbs: Self.verbs, verbsVersion: "test")
        for word in ["食べさせられなかった", "たべさせられなかった", "呼ばれました", "忘れてしまいました", "  食べた  "] {
            let items = store.items(in: word)
            XCTAssertEqual(items.count, 1, word)
            XCTAssertEqual(items.first?.surface, word.trimmingCharacters(in: .whitespaces), word)
            XCTAssertEqual(items.first?.status, .known, word)
        }
        XCTAssertEqual(store.items(in: "食べさせられなかった").first?.readings.first?.verb.id, "たべる")
        XCTAssertEqual(store.items(in: "   "), [])
    }
}
