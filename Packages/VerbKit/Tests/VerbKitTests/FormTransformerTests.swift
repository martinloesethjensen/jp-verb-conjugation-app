import XCTest
@testable import VerbKit

/// `FormTransformer` and `SentenceContext` on the real verbs and catalogue, with spans from
/// `VerbMatcher` on fixed tokens. The transforms over every verb and form, and over the
/// golden sentences, are in `RealFormTransformTests`.
final class FormTransformerTests: XCTestCase {
    private static var verbs: [Verb] = []
    private static var index: FormIndex!
    private static var transformer: FormTransformer!

    override class func setUp() {
        super.setUp()
        verbs = (try? RealVerbs.load()) ?? []
        index = FormIndex(verbs: verbs, catalogue: .bundled)
        transformer = FormTransformer(verbs: verbs, catalogue: .bundled)
    }

    /// The sentence the space-separated tokens spell, and its spans.
    private func spans(_ tokens: String) -> (text: String, spans: [VerbSpan]) {
        let tokenizer = FixedTokenizer([tokens])
        let text = tokenizer.tokens.keys.first ?? ""
        return (text, VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: tokenizer).spans(in: text))
    }

    /// The transforms of the span with `surface` in the sentence the tokens spell.
    private func transforms(
        _ tokens: String, at surface: String, verb: String? = nil, file: StaticString = #filePath, line: UInt = #line
    ) throws -> SpanTransforms {
        let (text, spans) = spans(tokens)
        let span = try XCTUnwrap(spans.first { $0.surface == surface }, "no span \(surface) in \(text)", file: file, line: line)
        let candidate = verb.flatMap { id in span.candidates.first { $0.verbID == id } }
        return Self.transformer.transforms(for: span, in: text, candidate: candidate)
    }

    private func chip(_ transforms: SpanTransforms, _ facet: FormFacet, file: StaticString = #filePath, line: UInt = #line) throws -> FormTransform {
        try XCTUnwrap(transforms.transforms.first { $0.step.facet == facet }, "no \(facet) chip", file: file, line: line)
    }

    // MARK: Steps from the catalogue

    func testTheCatalogueGivesTheMeasuredNeighbours() {
        func steps(_ form: FormID) -> [FormFacet: FormID] {
            Dictionary(uniqueKeysWithValues: Self.transformer.steps(from: form).map { ($0.facet, $0.to) })
        }
        // The research's measurements, quoted in #146.
        XCTAssertEqual(steps("masu_past"), [.tense: "masu_pos", .polarity: "masu_past_neg", .register: "short_past"])
        XCTAssertEqual(steps("short_neg"), [.register: "masu_neg", .polarity: "short_pos", .tense: "short_past_neg"])
        XCTAssertEqual(steps("nd_pos"), [.polarity: "nd_neg", .tense: "nd_past", .register: "nd_casual_pos"])
        XCTAssertEqual(steps("teiru_masu_past"), [.register: "teiru_past", .tense: "teiru_masu_pos", .polarity: "teiru_masu_past_neg"])
        XCTAssertEqual(steps("pot_masu_neg"), [.polarity: "pot_masu_pos", .tense: "pot_masu_past_neg", .register: "pot_short_neg"])
        XCTAssertEqual(steps("potential"), [.register: "pot_masu_pos", .polarity: "pot_short_neg", .tense: "pot_short_past"])
        // Facet pairs outside the four grids: register only.
        XCTAssertEqual(steps("teshimau"), [.register: "teshimau_polite"])
        XCTAssertEqual(steps("sugiru_polite"), [.register: "sugiru"])
        // Steps stay in their order: register, polarity, tense.
        XCTAssertEqual(Self.transformer.steps(from: "masu_past").map(\.facet), [.register, .polarity, .tense])
    }

    func testFormsWithoutANeighbourHaveNoSteps() {
        for form: FormID in ["te", "volitional", "passive", "causative", "conditional_ba", "imperative", "tai", "nagara", "pot_te", "teiru_te"] {
            XCTAssertEqual(Self.transformer.steps(from: form), [], form.rawValue)
        }
    }

    func testEveryStepIsOneFacetAndReversible() {
        let catalogue = FormCatalogue.bundled
        var count = 0
        for spec in catalogue.forms {
            for step in Self.transformer.steps(from: spec.id) {
                count += 1
                let target = catalogue.spec(for: step.to)
                XCTAssertEqual(target?.family, spec.family)
                XCTAssertEqual(target?.name, spec.name)
                XCTAssertTrue(Self.transformer.steps(from: step.to).contains(FormStep(facet: step.facet, from: step.to, to: spec.id)),
                              "\(step.to.rawValue) doesn't step back to \(spec.id.rawValue)")
            }
        }
        // Four grids of 8 forms with 3 steps each, and six register pairs.
        XCTAssertEqual(count, 4 * 8 * 3 + 6 * 2)
    }

    // MARK: The acceptance sentences

    func testAVerbBeforeANounKeepsItsRegister() throws {
        let result = try transforms("先週 買っ た 本 は とても 面白かっ た です 。", at: "買った")
        XCTAssertEqual(try chip(result, .register).disabledReason, .midSentence)
        XCTAssertEqual(TransformReason.midSentence.message, "Mid-sentence: only the last verb changes politeness")
        XCTAssertEqual(try chip(result, .polarity).rewrite?.sentence, "先週買わなかった本はとても面白かったです。")
        XCTAssertEqual(try chip(result, .tense).rewrite?.sentence, "先週買う本はとても面白かったです。")
    }

    func testTheFinalVerbChangesRegister() throws {
        let result = try transforms("毎朝 コーヒー を 飲み ます 。", at: "飲みます")
        let plain = try XCTUnwrap(try chip(result, .register).rewrite)
        XCTAssertEqual(plain.surface, "飲む")
        XCTAssertEqual(plain.sentence, "毎朝コーヒーを飲む。")
        XCTAssertNil(plain.note)
        XCTAssertEqual(try chip(result, .tense).rewrite?.surface, "飲みました")
        XCTAssertEqual(try chip(result, .tense).rewrite?.sentence, "毎朝コーヒーを飲みました。")
        XCTAssertEqual(try chip(result, .polarity).rewrite?.surface, "飲みません")
    }

    func testAPoliteQuestionBecomesAPlainOneWithoutKa() throws {
        for (tokens, sentence) in [
            ("行き ます か", "行く？"), ("明日 行き ます か 。", "明日行く？"),
            ("明日 行き ます か ？", "明日行く？"), ("明日 行き ます か ?", "明日行く?"),
        ] {
            let plain = try XCTUnwrap(try chip(try transforms(tokens, at: "行きます"), .register).rewrite, tokens)
            XCTAssertEqual(plain.surface, "行く")
            XCTAssertEqual(plain.sentence, sentence)
            XCTAssertFalse(plain.sentence.contains("行くか"))
            XCTAssertEqual(plain.note, .plainQuestion)
        }
        XCTAssertEqual(TransformNote.plainQuestion.message, "Plain か sounds blunt: drop it and raise your intonation")
        // The other facets keep the か.
        let past = try chip(try transforms("明日 行き ます か 。", at: "行きます"), .tense).rewrite
        XCTAssertEqual(past?.sentence, "明日行きましたか。")
        XCTAssertEqual(past?.range, "明日行きますか。".range(of: "行きます"))
    }

    func testAPlainQuestionBecomesAPoliteOneWithKa() throws {
        let withKa = try chip(try transforms("本当 に 行く か 。", at: "行く"), .register).rewrite
        XCTAssertEqual(withKa?.sentence, "本当に行きますか。")
        XCTAssertNil(withKa?.note)
        let rising = try chip(try transforms("明日 行く ？", at: "行く"), .register).rewrite
        XCTAssertEqual(rising?.replacement, "行きますか")
        XCTAssertEqual(rising?.sentence, "明日行きますか？")
        let teiru = try chip(try transforms("あの 人 を 知っ て い ます か 。", at: "知っています"), .register).rewrite
        XCTAssertEqual(teiru?.sentence, "あの人を知っている？")
    }

    func testFinalParticlesCarryOver() throws {
        XCTAssertEqual(try chip(try transforms("明日 行き ます よ 。", at: "行きます"), .register).rewrite?.sentence, "明日行くよ。")
        XCTAssertEqual(try chip(try transforms("もう 食べ まし た ね", at: "食べました"), .register).rewrite?.sentence, "もう食べたね")
        XCTAssertEqual(try chip(try transforms("一緒 に 行く よ ね ？", at: "行く"), .register).rewrite?.sentence, "一緒に行きますよね？")
        // か leading on to more particles isn't the question か: only the span changes.
        XCTAssertEqual(try chip(try transforms("彼 は 来る か ね 。", at: "来る"), .register).rewrite?.sentence, "彼は来ますかね。")
    }

    // MARK: Explanatory の and んです

    func testTheExplanatoryQuestionIsMoreThanOneStep() throws {
        let nd = try transforms("どう し た ん です か 。", at: "したんです")
        XCTAssertEqual(try chip(nd, .register).disabledReason, .explanatory)
        XCTAssertEqual(try chip(nd, .polarity).rewrite?.sentence, "どうしなかったんですか。")
        let no = try transforms("明日 行く の ？", at: "行く")
        XCTAssertEqual(try chip(no, .register).disabledReason, .explanatory)
        XCTAssertEqual(try chip(no, .polarity).rewrite?.sentence, "明日行かないの？")
        XCTAssertEqual(TransformReason.explanatory.message, "…の？ and …んですか are more than one step apart")
    }

    func testNdChangesRegisterAtTheEnd() throws {
        let result = try transforms("来月 京都 に 行く ん です 。", at: "行くんです")
        XCTAssertEqual(try chip(result, .register).rewrite?.sentence, "来月京都に行くんだ。")
        XCTAssertEqual(try chip(result, .tense).rewrite?.sentence, "来月京都に行ったんです。")
        let casual = try transforms("京都 に 行く ん だ ？", at: "行くんだ")
        XCTAssertEqual(try chip(casual, .register).rewrite?.sentence, "京都に行くんですか？")
    }

    // MARK: Mid-sentence and fixed forms

    func testClausesBeforeConjunctionsKeepTheirRegister() throws {
        let kara = try transforms("明日 行く から 早く 寝 ます 。", at: "行く")
        XCTAssertEqual(try chip(kara, .register).disabledReason, .midSentence)
        XCTAssertEqual(try chip(kara, .polarity).rewrite?.sentence, "明日行かないから早く寝ます。")
        XCTAssertEqual(try chip(try transforms("学校 に 行く 時 に 会い ます 。", at: "行く"), .register).disabledReason, .midSentence)
        XCTAssertEqual(try chip(try transforms("雨 が 降る ので 行き ませ ん 。", at: "行きません"), .register).rewrite?.sentence, "雨が降るので行かない。")
        // Not a final particle: かもしれない, 〜ように, the negative imperative な.
        XCTAssertEqual(try chip(try transforms("明日 行く か も しれ ない 。", at: "行く"), .register).disabledReason, .midSentence)
        XCTAssertEqual(try chip(try transforms("読める よう に なり たい 。", at: "読める"), .register).disabledReason, .midSentence)
        // Conditionals and the negative imperative are forms of their own, without a neighbour.
        XCTAssertEqual(try transforms("行く なら 教え て 。", at: "行くなら"), .unavailable(.noOneStepTransform))
        XCTAssertEqual(try transforms("駅 に 行く と 見え ます 。", at: "行くと"), .unavailable(.noOneStepTransform))
        XCTAssertEqual(try transforms("行く な 。", at: "行くな"), .unavailable(.noOneStepTransform))
    }

    func testMaeNiAndAtoDeFixTheForm() throws {
        let mae = try transforms("友達 が 来る 前 に 、 部屋 を 掃除 し て おく 。", at: "来る")
        XCTAssertEqual(mae.transforms.map(\.disabledReason), Array(repeating: .fixedBy(marker: "前に"), count: 3))
        XCTAssertEqual(TransformReason.fixedBy(marker: "前に").message, "Before 前に, the verb keeps this form")
        let ato = try transforms("ご飯 を 食べ た 後 で 散歩 し ます 。", at: "食べた")
        XCTAssertEqual(Set(ato.transforms.map(\.disabledReason)), [.fixedBy(marker: "後で")])
        let beki = try transforms("もっと 勉強 する べき だっ た 。", at: "する")
        XCTAssertEqual(Set(beki.transforms.map(\.disabledReason)), [.fixedBy(marker: "べき")])
        // 寝たほうがいい flips to 寝ないほうがいい, two facets at once: not offered.
        let advice = try transforms("早く 寝 た ほう が いい です よ 。", at: "寝た")
        XCTAssertEqual(Set(advice.transforms.map(\.disabledReason)), [.fixedBy(marker: "ほうがいい")])
    }

    // MARK: Spans without transforms

    func testFormsWithoutANeighbourHaveNoOneStepTransform() throws {
        XCTAssertEqual(try transforms("ちょっと 待っ て 。", at: "待って"), .unavailable(.noOneStepTransform))
        XCTAssertEqual(try transforms("一緒 に 行こ う 。", at: "行こう"), .unavailable(.noOneStepTransform))
        // A chain the tail rules built, until #149.
        XCTAssertEqual(try transforms("宿題 を 忘れ て しまい まし た 。", at: "忘れてしまいました"), .unavailable(.noOneStepTransform))
        XCTAssertEqual(TransformReason.noOneStepTransform.message, "No one-step change for this form yet")
    }

    func testAFacetPairOutsideTheGridsChangesRegister() throws {
        let result = try transforms("宿題 を 忘れ て しまう 。", at: "忘れてしまう")
        XCTAssertEqual(result.transforms.map(\.step.facet), [.register])
        XCTAssertEqual(result.transforms.first?.rewrite?.sentence, "宿題を忘れてしまいます。")
    }

    func testGreyedAndUnresolvedSpansHaveNoTransforms() throws {
        XCTAssertEqual(try transforms("雨 が 降っ たら 行か ない 。", at: "降ったら"), .unavailable(.notInApp))
        // Kana きた is 来る or 着る: the learner picks first.
        XCTAssertEqual(try transforms("ともだち が うち に き た 。", at: "きた"), .unavailable(.chooseReading))
        XCTAssertEqual(TransformReason.notInApp.message, "Not in the app yet")
        XCTAssertEqual(TransformReason.chooseReading.message, "Choose a reading first")
    }

    // MARK: Homophones and script

    func testHomophonesTransformByVerbID() throws {
        let kuru = try transforms("ともだち が うち に き た 。", at: "きた", verb: "くる")
        XCTAssertEqual(try chip(kuru, .polarity).rewrite?.sentence, "ともだちがうちにこなかった。")
        XCTAssertEqual(kuru.transforms.first?.verbID, "くる")
        let kiru = try transforms("ともだち が うち に き た 。", at: "きた", verb: "きる")
        XCTAssertEqual(try chip(kiru, .polarity).rewrite?.sentence, "ともだちがうちにきなかった。")
        XCTAssertEqual(kiru.transforms.first?.verbID, "きる")
        // 切る has its own id and its own forms.
        let cut = try transforms("紙 を 切っ た 。", at: "切った")
        XCTAssertEqual(cut.transforms.first?.verbID, "きる:切る")
        XCTAssertEqual(try chip(cut, .polarity).rewrite?.surface, "切らなかった")
        XCTAssertEqual(try chip(try transforms("服 を 着 た 。", at: "着た"), .polarity).rewrite?.surface, "着なかった")
    }

    func testAPickedReadingMustBeTheSpans() throws {
        let (text, spans) = spans("ともだち が うち に き た 。")
        let span = try XCTUnwrap(spans.first)
        let foreign = VerbCandidate(verbID: "たべる", chain: [ChainPart(surface: "きた", kind: .form("short_past"), isRuleBuilt: false)])
        XCTAssertEqual(Self.transformer.transforms(for: span, in: text, candidate: foreign), .unavailable(.chooseReading))
    }

    func testTheSpanKeepsItsScript() throws {
        XCTAssertEqual(try chip(try transforms("ご飯 を 食べ まし た 。", at: "食べました"), .polarity).rewrite?.surface, "食べませんでした")
        XCTAssertEqual(try chip(try transforms("ごはん を たべ まし た 。", at: "たべました"), .polarity).rewrite?.surface, "たべませんでした")
        // 来る's stem changes reading; the kanji stays.
        XCTAssertEqual(try chip(try transforms("友達 が 来 ます 。", at: "来ます"), .polarity).rewrite?.surface, "来ません")
        XCTAssertEqual(try chip(try transforms("友達 が 来 ます 。", at: "来ます"), .register).rewrite?.surface, "来る")
    }

    func testSpacesInATranscriptStayOutsideTheSpan() throws {
        let tokenizer = FixedTokenizer(["毎朝 コーヒー を 飲み ます 。"])
        let text = "毎朝 コーヒーを飲み ます。"
        let compact = VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: tokenizer)
        // The matcher looks the tokens up without spaces; the span maps back to the text.
        let span = try XCTUnwrap(compact.spans(in: text).first)
        let plain = Self.transformer.transforms(for: span, in: text).transforms.first { $0.step.facet == .register }
        XCTAssertEqual(plain?.rewrite?.sentence, "毎朝 コーヒーを飲む。")
    }

    // MARK: Data gaps

    func testAMissingTargetIsDisabledNotGuessed() throws {
        // A copy of 食べる without its polite past negative ている.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(XCTUnwrap(Self.verbs.first { $0.id == "たべる" }))
        ) as? [String: Any])
        var forms = try XCTUnwrap(object["forms"] as? [String: Any])
        forms["teiru_masu_past_neg"] = nil
        object["forms"] = forms
        let verb = try JSONDecoder().decode(Verb.self, from: JSONSerialization.data(withJSONObject: object))
        let transformer = FormTransformer(verbs: [verb], catalogue: .bundled)
        let text = "食べていました。"
        let span = VerbSpan(
            range: text.range(of: "食べていました")!, surface: "食べていました", status: .known,
            candidates: [VerbCandidate(verbID: "たべる", chain: [ChainPart(surface: "食べていました", kind: .form("teiru_masu_past"), isRuleBuilt: false)])]
        )
        let result = transformer.transforms(for: span, in: text)
        XCTAssertEqual(try chip(result, .polarity).disabledReason, .notInData)
        XCTAssertEqual(try chip(result, .tense).rewrite?.surface, "食べています")
        XCTAssertEqual(TransformReason.notInData.message, "Not in the data for this verb")
    }

    // MARK: SentenceContext

    func testSentenceContextPositions() {
        func position(_ text: String, _ verb: String) -> SentenceContext.Position {
            SentenceContext(span: text.range(of: verb)!, in: text).position
        }
        XCTAssertEqual(position("行く", "行く"), .final(.statement))
        XCTAssertEqual(position("行く。次", "行く"), .final(.statement))
        XCTAssertEqual(position("「行く」と言った", "行く"), .final(.statement))
        XCTAssertEqual(position("行く ！", "行く"), .final(.statement))
        XCTAssertEqual(position("行くよね", "行く"), .final(.statement))
        XCTAssertEqual(position("行くかな？", "行く"), .final(.statement))
        XCTAssertEqual(position("行く？", "行く"), .final(.questionMark))
        XCTAssertEqual(position("行くの", "行く"), .final(.explanatory))
        let text = "行きますか。次"
        let ka = text.range(of: "か。")!
        XCTAssertEqual(position(text, "行きます"), .final(.question(range: ka)))
        XCTAssertEqual(position("行きますか", "行きます"), .final(.question(range: "行きますか".range(of: "か")!)))
        XCTAssertEqual(position("行くかもしれない", "行く"), .midSentence)
        XCTAssertEqual(position("行くのが好き", "行く"), .midSentence)
        XCTAssertEqual(position("行くな", "行く"), .midSentence)
        XCTAssertEqual(position("行くよう", "行く"), .midSentence)
        XCTAssertEqual(position("行った本", "行った"), .midSentence)
        XCTAssertEqual(position("行く、", "行く"), .midSentence)
        XCTAssertEqual(position("行く前に", "行く"), .fixed(marker: "前に"))
        XCTAssertEqual(position("行った後、", "行った"), .fixed(marker: "後"))
        XCTAssertEqual(position("行くべきだ", "行く"), .fixed(marker: "べき"))
        XCTAssertTrue(SentenceContext(span: "行く".range(of: "行く")!, in: "行く").isFinal)
    }
}
