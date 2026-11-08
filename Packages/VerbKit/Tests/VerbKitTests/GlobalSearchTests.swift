import XCTest
@testable import VerbKit

/// Runs on the bundled data, so real ids are asserted.
final class GlobalSearchTests: XCTestCase {
    private static let verbs = BundledData<VerbDataFile>.load(named: "verbs")!.value.verbs
    private static let grammar = BundledData<GrammarDataFile>.load(named: "grammar")!.value.grammar
    private static let countersFile = BundledData<CountersDataFile>.load(named: "counters")!.value

    private func search(
        _ query: String, scope: SearchScope = .everything, levels: LevelSettings = LevelSettings(),
        wordBank: WordBankSearchIndex? = nil, extraVerbs: [Verb] = []
    ) -> GlobalSearchResults {
        GlobalSearch.results(
            for: query, scope: scope, levels: levels, verbs: Self.verbs, grammar: Self.grammar,
            counters: Self.countersFile.counters, groups: Self.countersFile.groups,
            wordBank: wordBank, furigana: nil, extraVerbs: extraVerbs
        )
    }

    private var nomu: Verb { Self.verbs.first { $0.id == "のむ" }! }

    func testRomajiFindsTheVerbAndReportsTheReading() {
        let results = search("nomu")
        XCTAssertTrue(results.verbs.contains { $0.id == "のむ" })
        XCTAssertEqual(results.readingAs, "のむ")
    }

    func testEnglishFindsVerbsWithoutAReading() {
        let results = search("drink")
        XCTAssertTrue(results.verbs.contains { $0.id == "のむ" })
        XCTAssertNil(results.readingAs)
    }

    func testEnglishThatIsAlsoRomajiShowsReadingOnlyForKanaOnlyHits() {
        // "make" reads as まけ, which finds nothing the English "make" does not.
        let results = search("make")
        XCTAssertFalse(results.isEmpty)
        XCTAssertNil(results.readingAs)
    }

    func testScopeLimitsSections() {
        let results = search("nomu", scope: .grammar)
        XCTAssertTrue(results.verbs.isEmpty)
        XCTAssertTrue(results.counters.isEmpty)
        XCTAssertTrue(results.wordBank.isEmpty)
        XCTAssertEqual(search("nomu", scope: .verbs).grammar, [])
    }

    func testHiddenLevelsAreCountedNotShown() {
        let hidden = search("nomu", levels: LevelSettings(hidden: [.n5]))
        XCTAssertFalse(hidden.verbs.contains { $0.id == "のむ" })
        XCTAssertGreaterThanOrEqual(hidden.hiddenCount, 1)
        XCTAssertTrue(hidden.hiddenLevels.contains(.n5))
        let all = search("nomu")
        XCTAssertTrue(all.verbs.contains { $0.id == "のむ" })
        XCTAssertEqual(all.hiddenCount, 0)
        XCTAssertEqual(all.hiddenLevels, [])
    }

    func testOnlyHiddenMatchesReportsTheHiddenCount() {
        let every = LevelSettings(hidden: Set(JLPTLevel.allCases))
        let results = search("のむ", scope: .verbs, levels: every)
        XCTAssertTrue(results.isEmpty)
        XCTAssertGreaterThan(results.hiddenCount, 0)
    }

    func testBlankAndPunctuationAreEmpty() {
        for query in ["", "   ", "?", "…"] {
            let results = search(query)
            XCTAssertEqual(results.count, 0, query)
            XCTAssertEqual(results.hiddenCount, 0, query)
            XCTAssertNil(results.readingAs, query)
        }
    }

    func testIsSearchableNeedsALetterKanaOrKanji() {
        for query in ["nomu", "飲む", "のむ", "drink party", " 本 "] {
            XCTAssertTrue(GlobalSearch.isSearchable(query), query)
        }
        for query in ["", "   ", "?", "!!", "…", "3"] {
            XCTAssertFalse(GlobalSearch.isSearchable(query), query)
        }
    }

    func testExtraVerbsAreAddedOnce() {
        XCTAssertEqual(search("飲んだ", extraVerbs: [nomu]).verbs.filter { $0.id == "のむ" }.count, 1)
        XCTAssertEqual(search("nomu", extraVerbs: [nomu]).verbs.filter { $0.id == "のむ" }.count, 1)
    }

    func testExtraVerbsRespectHiddenLevels() {
        let results = search("飲んだ", scope: .verbs, levels: LevelSettings(hidden: [.n5]), extraVerbs: [nomu])
        XCTAssertFalse(results.verbs.contains { $0.id == "のむ" })
        XCTAssertGreaterThanOrEqual(results.hiddenCount, 1)
    }

    func testWordBankMatchesAreIncludedAndIgnoreLevels() {
        let entry = WordBankEntryValue(text: "飲み会", reading: "のみかい", senses: [Sense(meaning: "drinking party")])
        let index = WordBankSearchIndex(entries: [entry], folders: [], dialectTags: [], customTags: [])
        let every = LevelSettings(hidden: Set(JLPTLevel.allCases))
        XCTAssertEqual(search("drinking party", levels: every, wordBank: index).wordBank.map(\.entry.id), [entry.id])
        XCTAssertEqual(search("nomikai", scope: .wordBank, wordBank: index).wordBank.map(\.entry.id), [entry.id])
    }

    func testCountIsTheSumOfEverySection() {
        let results = search("cup")
        let counters = results.counters
        XCTAssertEqual(results.count, results.verbs.count + results.grammar.count + counters.groups.count
                       + counters.counters.count + counters.forms.count + counters.things.count + results.wordBank.count)
    }

    func testRecentsKeyIsSeparateFromTheWordBanks() {
        XCTAssertNotEqual(GlobalSearch.recentsKey, RecentSearches.defaultsKey)
    }
}
