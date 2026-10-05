import XCTest
@testable import VerbKit

final class WordBankSearchTests: XCTestCase {
    // MARK: fixture

    private let kansai = DialectTagValue(name: "関西弁", romaji: "Kansai-ben", prefectures: [.osaka, .kyoto], region: .kansai)
    private let izumo = DialectTagValue(name: "出雲弁", romaji: "Izumo-ben", prefectures: [.shimane], region: .chugoku)
    private let kumamoto = DialectTagValue(name: "熊本弁", romaji: "Kumamoto-ben", prefectures: [.kumamoto], region: .kyushuOkinawa)
    private let hakata = DialectTagValue(name: "博多弁", romaji: "Hakata-ben", prefectures: [.fukuoka], region: .kyushuOkinawa)
    private let food = CustomTagValue(name: "food", color: .orange)
    private let slang = CustomTagValue(name: "slang", color: .purple)
    private let trip = WordBankFolderValue(name: "Trip 2026")
    private lazy var takayama = WordBankFolderValue(name: "Takayama", parentID: trip.id)
    private lazy var market = WordBankFolderValue(name: "Morning market", parentID: takayama.id)

    private func at(_ minutes: Double) -> Date { Date(timeIntervalSince1970: minutes * 60) }

    private lazy var ookini = WordBankEntryValue(
        text: "おおきに", reading: "おおきに", senses: [Sense(meaning: "thank you")],
        equivalents: [StandardEquivalent(written: "ありがとう")], dialectTagIDs: [kansai.id], createdAt: at(1), updatedAt: at(20))
    private lazy var naosu = WordBankEntryValue(
        text: "なおす", senses: [Sense(meaning: "put away", note: "≠ standard 直す (fix)")],
        equivalents: [StandardEquivalent(written: "片付ける", reading: "かたづける")], dialectTagIDs: [kansai.id], createdAt: at(2))
    private lazy var dandan = WordBankEntryValue(
        text: "だんだん", senses: [Sense(meaning: "thank you")], equivalents: [StandardEquivalent(written: "ありがとう")],
        dialectTagIDs: [izumo.id], createdAt: at(3))
    private lazy var menkoi = WordBankEntryValue(
        text: "めんこい", senses: [Sense(meaning: "cute")], equivalents: [StandardEquivalent(written: "可愛い", reading: "かわいい")],
        customTagIDs: [slang.id], createdAt: at(4))
    private lazy var yokitana = WordBankEntryValue(
        text: "よう来たな", kind: .phrase, senses: [Sense(meaning: "welcome")], folderID: takayama.id, createdAt: at(5))
    private lazy var umaka = WordBankEntryValue(
        text: "うまか", senses: [Sense(meaning: "delicious")],
        notes: "We had dinner with friends and then heard it from Yuki at the izakaya in Kumamoto after the summer festival ended late",
        dialectTagIDs: [kumamoto.id], customTagIDs: [food.id], createdAt: at(6))
    private lazy var suitou = WordBankEntryValue(
        text: "すいとう", senses: [Sense(meaning: "I like (you)")], folderID: market.id, dialectTagIDs: [hakata.id], createdAt: at(7))
    private lazy var okiniiri = WordBankEntryValue(text: "おきにいり", senses: [Sense(meaning: "favourite")], createdAt: at(8))
    private lazy var atama = WordBankEntryValue(text: "頭が痛い", kind: .sentence, senses: [Sense(meaning: "my head hurts")], createdAt: at(9))
    private lazy var gohan = WordBankEntryValue(text: "ご飯", kind: .word, wordClass: .noun, senses: [Sense(meaning: "meal")], createdAt: at(10))
    private lazy var ikahen = WordBankEntryValue(
        text: "いかへん", kind: .word, wordClass: .verb, equivalents: [StandardEquivalent(written: "行かない")],
        dialectTagIDs: [kansai.id], createdAt: at(11))
    private lazy var meccha = WordBankEntryValue(text: "めっちゃ寒い", kind: .sentence, dialectTagIDs: [kansai.id], createdAt: at(12))
    private lazy var honma = WordBankEntryValue(
        text: "ほんま", senses: [Sense(meaning: "really", note: "thank goodness, you know")], createdAt: at(13))
    private lazy var coffee = WordBankEntryValue(text: "コーヒー", senses: [Sense(meaning: "coffee")], createdAt: at(14))

    private var allEntries: [WordBankEntryValue] {
        [ookini, naosu, dandan, menkoi, yokitana, umaka, suitou, okiniiri, atama, gohan, ikahen, meccha, honma, coffee]
    }

    private func index(
        entries: [WordBankEntryValue]? = nil, derivedReading: (String) -> String? = { _ in nil }
    ) -> WordBankSearchIndex {
        WordBankSearchIndex(
            entries: entries ?? allEntries, folders: [trip, takayama, market],
            dialectTags: [kansai, izumo, kumamoto, hakata], customTags: [food, slang], derivedReading: derivedReading
        )
    }

    private func texts(_ query: WordBankQuery, in index: WordBankSearchIndex? = nil) -> [String] {
        (index ?? self.index()).search(query).map(\.entry.text)
    }

    private func q(_ text: String = "", _ tokens: [WordBankToken] = [], scope: UUID? = nil) -> WordBankQuery {
        WordBankQuery(text: text, tokens: tokens, scopeFolder: scope)
    }

    // MARK: text matching

    func testRomajiKanaAndKatakanaFindTheEntryFirst() {
        for query in ["ookini", "おおきに", "オオキニ", "ＯＯＫＩＮＩ"] {
            XCTAssertEqual(texts(q(query)).first, "おおきに", query)
        }
    }

    func testEnglishMatchesSenses() {
        let results = texts(q("thank you"))
        XCTAssertEqual(Array(results.prefix(2)), ["おおきに", "だんだん"], "most recently updated first on a tie")
        XCTAssertTrue(results.contains("ほんま"), "words may match in different places")
    }

    func testAPrefixRanksAboveAContainsMatch() {
        XCTAssertEqual(Array(texts(q("okini")).prefix(2)), ["おきにいり", "おおきに"])
    }

    func testLooseFallbackFindsLongVowels() throws {
        let index = index()
        let loose = try XCTUnwrap(index.search(q("kohi")).first)
        XCTAssertEqual(loose.entry.text, "コーヒー")
        let exact = try XCTUnwrap(index.search(q("こーひー")).first)
        XCTAssertLessThan(loose.score, exact.score)
    }

    func testEquivalentMatchesAreExplained() throws {
        let results = index().search(q("ありがとう"))
        XCTAssertEqual(results.map(\.entry.text), ["おおきに", "だんだん"])
        XCTAssertEqual(results.first?.explanation?.field, .equivalent)
        XCTAssertEqual(results.first?.explanation?.snippet, "ありがとう")
    }

    func testATextMatchNeedsNoExplanation() {
        XCTAssertNil(index().search(q("おおきに")).first?.explanation)
    }

    func testSeveralWordsMustAllMatchAndNotesGetASnippet() throws {
        let results = index().search(q("yuki izakaya"))
        XCTAssertEqual(results.map(\.entry.text), ["うまか"])
        let explanation = try XCTUnwrap(results.first?.explanation)
        XCTAssertEqual(explanation.field, .notes)
        XCTAssertTrue(explanation.snippet.hasPrefix("…"), explanation.snippet)
        XCTAssertTrue(explanation.snippet.localizedCaseInsensitiveContains("yuki"))
        let range = try XCTUnwrap(explanation.range)
        XCTAssertEqual(explanation.snippet[range].lowercased(), "yuki")
        XCTAssertEqual(texts(q("yuki karaoke")), [])
    }

    func testAQuotedPhraseMustMatchWhole() {
        let quoted = texts(q("\"thank you\""))
        XCTAssertTrue(quoted.contains("おおきに"))
        XCTAssertFalse(quoted.contains("ほんま"))
    }

    func testTagNamesAreSearchedWithoutAToken() {
        let results = index().search(q("kansai"))
        XCTAssertEqual(Set(results.map(\.entry.text)), ["おおきに", "なおす", "いかへん", "めっちゃ寒い"])
        XCTAssertEqual(results.first?.explanation?.field, .tag)
        XCTAssertEqual(results.first?.explanation?.snippet, "関西弁")
    }

    func testFieldWeightsOrderResults() {
        let results = texts(q("thank"))
        XCTAssertLessThan(results.firstIndex(of: "おおきに")!, results.firstIndex(of: "ほんま")!, "sense before sense note")
    }

    func testDerivedReadingFindsKanjiText() {
        XCTAssertEqual(texts(q("atama")), [])
        let derived = index(derivedReading: { $0 == "頭が痛い" ? "あたまがいたい" : nil })
        XCTAssertEqual(texts(q("atama"), in: derived), ["頭が痛い"])
    }

    func testEmptyTextKeepsTheOriginalOrder() {
        XCTAssertEqual(texts(q()), allEntries.map(\.text))
        XCTAssertTrue(index().search(q()).allSatisfy { $0.score == 0 && $0.explanation == nil })
    }

    // MARK: tokens

    func testEveryToken() {
        XCTAssertEqual(Set(texts(q("", [.dialectTag(kansai.id)]))), ["おおきに", "なおす", "いかへん", "めっちゃ寒い"])
        XCTAssertEqual(Set(texts(q("", [.region(.kyushuOkinawa)]))), ["うまか", "すいとう"])
        XCTAssertEqual(texts(q("", [.prefecture(.shimane)])), ["だんだん"])
        XCTAssertEqual(texts(q("", [.customTag(slang.id)])), ["めんこい"])
        XCTAssertEqual(Set(texts(q("", [.folder(trip.id)]))), ["よう来たな", "すいとう"], "includes subfolders")
        XCTAssertEqual(texts(q("", [.kind(.phrase)])), ["よう来たな"])
        XCTAssertEqual(texts(q("", [.wordClass(.verb)])), ["いかへん"])
        XCTAssertFalse(texts(q("", [.unfiled])).contains("よう来たな"))
        XCTAssertEqual(texts(q("", [.unfiled])).count, allEntries.count - 2)
        XCTAssertEqual(
            Set(texts(q("", [.noDialectTag]))),
            ["めんこい", "よう来たな", "おきにいり", "頭が痛い", "ご飯", "ほんま", "コーヒー"]
        )
    }

    func testTokensCombineWithAnd() {
        XCTAssertEqual(texts(q("", [.region(.kyushuOkinawa), .customTag(food.id)])), ["うまか"])
        XCTAssertEqual(texts(q("ありがとう", [.dialectTag(izumo.id)])), ["だんだん"])
    }

    func testScopeLimitsToTheFolderSubtree() {
        XCTAssertEqual(Set(texts(q("", scope: takayama.id))), ["よう来たな", "すいとう"])
        XCTAssertEqual(texts(q("ookini", scope: takayama.id)), [])
    }

    func testCount() {
        XCTAssertEqual(index().count(q("", [.dialectTag(kansai.id)])), 4)
    }

    // MARK: suggested tokens

    func testSuggestedTokensNeedResults() {
        XCTAssertTrue(index().suggestedTokens(for: "kuma", excluding: []).contains(.dialectTag(kumamoto.id)))
        var withoutTag = umaka
        withoutTag.dialectTagIDs = []
        let bare = index(entries: [ookini, withoutTag])
        XCTAssertFalse(bare.suggestedTokens(for: "kuma", excluding: []).contains(.dialectTag(kumamoto.id)))
    }

    func testSuggestedTokensFindFoldersRegionsAndKinds() {
        let index = index()
        XCTAssertTrue(index.suggestedTokens(for: "taka", excluding: []).contains(.folder(takayama.id)))
        XCTAssertTrue(index.suggestedTokens(for: "kyushu", excluding: []).contains(.region(.kyushuOkinawa)))
        XCTAssertTrue(index.suggestedTokens(for: "phra", excluding: []).contains(.kind(.phrase)))
        XCTAssertFalse(index.suggestedTokens(for: "kuma", excluding: [.dialectTag(kumamoto.id)]).contains(.dialectTag(kumamoto.id)))
    }

    // MARK: no-results help

    func testRelaxationsOfferWaysOut() {
        let index = index()
        let none = q("", [.dialectTag(kumamoto.id), .kind(.phrase)])
        XCTAssertEqual(index.count(none), 0)
        XCTAssertEqual(Set(index.relaxations(of: none)), [
            WordBankRelaxation(dropping: .dialectTag(kumamoto.id), widenScope: false, count: 1),
            WordBankRelaxation(dropping: .kind(.phrase), widenScope: false, count: 1),
        ])
        XCTAssertEqual(
            index.relaxations(of: q("うまか", scope: takayama.id)),
            [WordBankRelaxation(dropping: nil, widenScope: true, count: 1)]
        )
    }

    // MARK: performance

    func testSearchStaysFastForFiveThousandEntries() {
        let kana = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわん")
        var generator = SystemRandomNumberGenerator()
        let entries = (0..<5_000).map { n in
            WordBankEntryValue(
                text: String((0..<4).map { _ in kana.randomElement(using: &generator)! }),
                senses: [Sense(meaning: "meaning number \(n)")],
                equivalents: [StandardEquivalent(written: String((0..<3).map { _ in kana.randomElement(using: &generator)! }))],
                notes: "a note about entry \(n) that runs on for a while",
                dialectTagIDs: n.isMultiple(of: 3) ? [kansai.id] : []
            )
        }
        let big = index(entries: entries)
        let query = q("meaning nu")
        // The spec's target is 16 ms per keystroke in the shipped (optimised) build.
        // Unoptimised code runs about 9× slower, so debug builds get a looser limit
        // that still catches a real regression without depending on machine load.
        #if DEBUG
        let limit = 0.25
        #else
        let limit = 0.016
        #endif
        let start = Date()
        _ = big.search(query)
        XCTAssertLessThan(Date().timeIntervalSince(start), limit)
        measure(metrics: [XCTClockMetric()]) { _ = big.search(query) }
    }
}
