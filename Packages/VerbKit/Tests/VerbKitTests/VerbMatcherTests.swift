import XCTest
@testable import VerbKit

/// `VerbMatcher` on the real verbs, with tokens fixed in each test so the results don't
/// depend on the OS tokenizer; one test runs the real `CFStringTokenizer`. The golden
/// sentences are in `RealLensSentenceTests`.
final class VerbMatcherTests: XCTestCase {
    private static var verbs: [Verb] = []
    private static var index: FormIndex!

    override class func setUp() {
        super.setUp()
        verbs = (try? RealVerbs.load()) ?? []
        index = FormIndex(verbs: verbs, catalogue: .bundled)
    }

    /// The spans of one sentence, given as space-separated `surface` or `surface/reading` tokens.
    private func spans(_ tokens: String) -> [VerbSpan] {
        let tokenizer = FixedTokenizer([tokens])
        let text = tokenizer.tokens.keys.first ?? ""
        return VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: tokenizer).spans(in: text)
    }

    private func part(_ surface: String, _ kind: ChainPart.Kind, rule: Bool = false) -> ChainPart {
        ChainPart(surface: surface, kind: kind, isRuleBuilt: rule)
    }

    // MARK: Chains

    func testACausativePassiveChainEndsInARuleBuiltPart() throws {
        let spans = spans("母 に 野菜 を 食べ させ られ なかっ た 。")
        let span = try XCTUnwrap(spans.first)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(span.surface, "食べさせられなかった")
        XCTAssertEqual(span.status, .known)
        XCTAssertEqual(span.candidates, [VerbCandidate(verbID: "たべる", chain: [
            part("食べさせられ", .form("causative_passive")),
            part("なかった", .form("short_past_neg"), rule: true),
        ])])
        XCTAssertNil(span.candidates[0].formID)
        XCTAssertTrue(span.candidates[0].isRuleBuilt)
    }

    func testAnExactFormHasItsFormID() throws {
        let span = try XCTUnwrap(spans("毎朝 コーヒー を 飲み ます 。").first)
        XCTAssertEqual(span.surface, "飲みます")
        XCTAssertEqual(span.candidates.map(\.formID), ["masu_pos"])
        XCTAssertFalse(span.candidates[0].isRuleBuilt)
    }

    func testTeAuxiliariesChain() throws {
        XCTAssertEqual(spans("宿題 を 忘れ て しまい まし た 。").first?.candidates.first?.chain, [
            part("忘れて", .form("te")), part("しまいました", .auxiliary("てしまう · polite past"), rule: true),
        ])
        XCTAssertEqual(spans("この 料理 を 食べ て み て ください 。").first?.surface, "食べてみてください")
        XCTAssertEqual(spans("新しい 服 を 着 て み たい です 。").first?.surface, "着てみたいです")
        XCTAssertEqual(spans("窓 を 開け て も いい です か 。").first?.surface, "開けてもいいです")
    }

    func testMorauChainsGetTheWholeSpan() {
        XCTAssertEqual(spans("友達 に 日本 語 を 教え て もらい まし た 。").map(\.surface), ["教えてもらいました"])
        XCTAssertEqual(spans("窓 を 閉め て もらえ ます か 。").map(\.surface), ["閉めてもらえます"])
        XCTAssertEqual(spans("窓 を 閉め て もらえ ます か 。").first?.candidates.first?.chain.last,
                       part("もらえます", .auxiliary("てもらえる · polite"), rule: true))
    }

    func testStemsTheIndexDoesNotDerive() {
        // すぎる, やすい and にくい stems; the ちゃう contraction; the ら-less potential.
        XCTAssertEqual(spans("昨日 は 食べ すぎ まし た 。").map(\.surface), ["食べすぎました"])
        XCTAssertEqual(spans("この 道 は 歩き にくく なかっ た 。").map(\.surface), ["歩きにくくなかった"])
        XCTAssertEqual(spans("あ 全部 食べ ちゃっ た 。").map(\.surface), ["食べちゃった"])
        XCTAssertEqual(spans("ジュース を 飲ん じゃっ た 。").map(\.surface), ["飲んじゃった"])
        let ranuki = spans("朝 は 早く 起きれ ない 。")
        XCTAssertEqual(ranuki.map(\.surface), ["起きれない"])
        XCTAssertEqual(ranuki.first?.candidates.first?.chain.first, part("起きれ", .form("potential"), rule: true))
    }

    func testAListedFormBeatsTheSameSpanBuiltByRule() throws {
        // 食べられます is the potential's pot_masu_pos; the passive stem + ます isn't offered too.
        let span = try XCTUnwrap(spans("野菜 が 食べ られ ます 。").first)
        XCTAssertEqual(span.status, .known)
        XCTAssertEqual(span.candidates.map(\.formID), ["pot_masu_pos"])
    }

    // MARK: Boundaries

    func testAMatchStartsAndEndsOnATokenBoundary() {
        // 十分かかります holds 借ります's かります; 面白かった holds 買った.
        XCTAssertEqual(spans("駅 まで 歩い て 十分 かかり ます 。").map(\.surface), ["歩いて"])
        XCTAssertEqual(spans("本 は 面白かっ た です 。").map(\.surface), [])
    }

    func testTranscriptsWithDigitsSpacesAndNoCommas() throws {
        // SpeechTranscriber writes 十分 as 10分, puts a space before the digits, and drops 、.
        let text = "駅まで歩いて 10分かかります"
        let tokenizer = FixedTokenizer(["駅 まで 歩い て 10 分 かかり ます"])
        let spans = VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: tokenizer).spans(in: text)
        XCTAssertEqual(spans.map(\.surface), ["歩いて"])
        XCTAssertEqual(spans.first.map { String(text[$0.range]) }, "歩いて")

        // A space inside a chain doesn't break it; the range covers it in the original text.
        let spaced = "毎日 食べて います"
        let chain = VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: FixedTokenizer(["毎日 食べ て い ます"]))
            .spans(in: spaced)
        XCTAssertEqual(chain.map(\.surface), ["食べています"])
        XCTAssertEqual(chain.first.map { String(spaced[$0.range]) }, "食べて います")
    }

    // MARK: Ambiguity

    func testKanaKitaIsAmbiguous() throws {
        let span = try XCTUnwrap(spans("ともだち が うち に き た 。").first)
        XCTAssertEqual(span.status, .ambiguous)
        XCTAssertEqual(Set(span.verbIDs), ["くる", "きる"])
    }

    func testPassiveAndPotentialAreAmbiguous() throws {
        let span = try XCTUnwrap(spans("これ は 食べ られる 。").first)
        XCTAssertEqual(span.status, .ambiguous)
        XCTAssertEqual(Set(span.candidates.compactMap(\.formID)), ["passive", "potential"])
    }

    func testTheReadingBreaksKanjiTies() throws {
        // 入れる (いれる) and 入る's potential (はいれる) are both 入れる in kanji.
        XCTAssertEqual(spans("箱 に 入れ/いれ ます/ます 。").first?.verbIDs, ["いれる"])
        XCTAssertEqual(spans("ここ から 入れ/はいれ ます/ます 。").first?.verbIDs, ["はいる"])
        XCTAssertEqual(spans("ここ から 入れ/はいれ ます/ます 。").first?.status, .known)
        // Without a reading both stay.
        let unread = try XCTUnwrap(spans("箱 に 入れ ます 。").first)
        XCTAssertEqual(unread.status, .ambiguous)
        XCTAssertEqual(Set(unread.verbIDs), ["いれる", "はいる"])
        // 出させる: 出す's causative (ださせる) or 出る's (でさせる).
        XCTAssertEqual(spans("声 を 出さ/ださ せる/せる 。").first?.verbIDs, ["だす"])
        XCTAssertEqual(spans("外 に 出/で させる/させる 。").first?.verbIDs, ["でる"])
    }

    // MARK: Stems, stoplist and context

    func testABareMasuStemOnlyCountsBeforeNi() throws {
        let purpose = try XCTUnwrap(spans("映画 を 見 に 行き まし た 。").first)
        XCTAssertEqual(purpose.surface, "見")
        XCTAssertEqual(purpose.candidates, [VerbCandidate(verbID: "みる", chain: [part("見", .stem)])])
        XCTAssertEqual(spans("遊び に 行き たい 。").map(\.surface), ["遊び", "行きたい"])
        // The nouns 休み and 話 aren't 休む and 話す.
        XCTAssertEqual(spans("明日 は 休み です 。").map(\.surface), [])
        XCTAssertEqual(spans("その 話 は 聞い た 。").map(\.surface), ["聞いた"])
    }

    func testStoplistedWordsAreNeverHighlighted() {
        XCTAssertEqual(spans("すみ ませ ん 道 を 聞き たい ん です が 。").map(\.surface), ["聞きたい"])
        // どうして isn't する; 遅れたんです is 遅れる (#4).
        XCTAssertEqual(spans("どう して 遅れ た ん です か 。").filter { $0.status != .notInApp }.map(\.surface), ["遅れたんです"])
    }

    func testNaiIsNotAruAfterAnAdjectiveANounOrAPattern() {
        for tokens in [
            "安っぽく ない です ね 。", "水 じゃ ない 。", "雨 が 降る か も しれ ない 。",
            "そんな こと は あり え ない 。", "悪口 を 言う もの で は ありま せん 。",
        ] {
            XCTAssertFalse(spans(tokens).contains { $0.verbIDs.contains("ある") }, tokens)
        }
        XCTAssertEqual(spans("お 金 が ない から 。").first?.verbIDs, ["ある"])
    }

    func testIkenaiInsideAPatternIsNotIku() {
        XCTAssertFalse(spans("ここ で やっ て は いけ ませ ん 。").contains { $0.verbIDs.contains("いく") })
        XCTAssertEqual(spans("約束 を 忘れ ちゃ いけ ない よ 。").map(\.surface), ["忘れちゃいけない"])
        XCTAssertEqual(spans("漢字 を 覚え なけれ ば いけ ませ ん 。").map(\.surface), ["覚えなければいけません"])
        XCTAssertEqual(spans("明日 は 学校 へ いけ ない 。").first?.verbIDs, ["いく"])
    }

    func testMitaiAfterAnAdjectiveOrANounIsNotMiru() {
        XCTAssertEqual(spans("外 は 寒い みたい だ 。").map(\.surface), [])
        XCTAssertEqual(spans("夢 みたい な 話 です ね 。").map(\.surface), [])
        // Kana み… after て is the auxiliary of a verb the app lacks.
        XCTAssertEqual(spans("もう 一 度 やっ て み ます 。").map(\.surface), [])
        XCTAssertEqual(spans("映画 が みたい 。").first?.verbIDs, ["みる"])
    }

    // MARK: Verbs the app lacks

    func testAConjugatedVerbTheAppLacksIsGreyed() throws {
        let spans = spans("約束 を 守っ たら 一緒 に 遊び ましょう 。")
        XCTAssertEqual(spans.map(\.surface), ["守ったら", "遊びましょう"])
        XCTAssertEqual(spans.map(\.status), [.notInApp, .known])
        XCTAssertEqual(spans[0].guesses, ["守る", "守う", "守つ"])
        XCTAssertEqual(spans[0].candidates, [])
    }

    func testGreyedSpansRunOnThroughThePattern() {
        XCTAssertEqual(spans("ここ で たばこ を 吸っ て は いけ ませ ん 。").map(\.surface), ["吸ってはいけません"])
        XCTAssertEqual(spans("子供 が 泣い て いる 。").map(\.surface), ["泣いている"])
    }

    func testNounsAndAdjectivesAreNotGreyed() {
        // A lone kanji + で, a noun + だ, an adjective's かっ.
        XCTAssertEqual(spans("昨日 は 雨 で どこ に も 行か なかっ た 。").map(\.surface), ["行かなかった"])
        XCTAssertEqual(spans("子供っぽい 考え だ 。").map(\.surface), [])
        XCTAssertEqual(spans("とても 面白かっ た 。").map(\.surface), [])
    }

    func testDictionaryGuesses() {
        XCTAssertEqual(VerbMatcher.dictionaryGuesses(stem: "降っ", before: "た"), ["降る", "降う", "降つ"])
        XCTAssertEqual(VerbMatcher.dictionaryGuesses(stem: "泣い", before: "て"), ["泣く"])
        XCTAssertEqual(VerbMatcher.dictionaryGuesses(stem: "泳い", before: "で"), ["泳ぐ"])
        XCTAssertEqual(VerbMatcher.dictionaryGuesses(stem: "思い", before: "ます"), ["思う"])
        XCTAssertEqual(VerbMatcher.dictionaryGuesses(stem: "置き", before: "ます"), ["置く", "置きる"])
        XCTAssertEqual(VerbMatcher.dictionaryGuesses(stem: "遅れ", before: "た"), ["遅れる"])
        XCTAssertEqual(VerbMatcher.dictionaryGuesses(stem: "守ら", before: "ない"), ["守る"])
        XCTAssertEqual(VerbMatcher.dictionaryGuesses(stem: "死ん", before: "だ"), ["死む", "死ぶ", "死ぬ"])
        XCTAssertEqual(VerbMatcher.dictionaryGuesses(stem: "話し", before: "た"), ["話す"])
    }

    // MARK: The real tokenizer

    func testTheSystemTokenizer() throws {
        let tokens = SystemTokenizer().tokens(in: "箱に入れます。")
        XCTAssertEqual(tokens.map(\.surface), ["箱", "に", "入れ", "ます"])
        XCTAssertEqual(tokens.first { $0.surface == "入れ" }?.reading, "いれ")
        XCTAssertTrue(SystemTokenizer().tokens(in: "").isEmpty)

        let matcher = VerbMatcher(index: Self.index, verbs: Self.verbs)
        for (text, surfaces) in [
            ("母に野菜を食べさせられなかった。", ["食べさせられなかった"]),
            ("友達に日本語を教えてもらいました。", ["教えてもらいました"]),
            ("駅まで歩いて 10分かかります", ["歩いて"]),
            ("箱に入れます。", ["入れます"]),
            ("雨が降ったら、家で本を読みましょう。", ["降ったら", "読みましょう"]),
        ] {
            XCTAssertEqual(matcher.spans(in: text).map(\.surface), surfaces, text)
        }
        XCTAssertEqual(matcher.spans(in: "箱に入れます。").first?.verbIDs, ["いれる"])
    }

    // MARK: Scaling

    func testMatchingScalesLinearlyWithTheTextLength() throws {
        // A ~40-character sentence, repeated: tokens are recorded once outside the timing.
        let sentence = "先生に名前を呼ばれました。母に野菜を食べさせられなかった。雨が降ったら、家で本を読みましょう。"
        let tokens = SystemTokenizer().tokens(in: sentence).map { (surface: $0.surface, reading: $0.reading) }
        XCTAssertScalesLinearly(small: 20, runs: 3, prepare: { count in
            let text = String(repeating: sentence, count: count)
            let tokenizer = FixedTokenizer([text: Array(repeating: tokens, count: count).flatMap { $0 }])
            return (VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: tokenizer), text)
        }) { input in
            _ = input.0.spans(in: input.1)
        }
        let matcher = VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: FixedTokenizer([sentence: tokens]))
        XCTAssertEqual(matcher.spans(in: sentence).count, 4)
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<100 { _ = matcher.spans(in: sentence) }
        }
    }
}
