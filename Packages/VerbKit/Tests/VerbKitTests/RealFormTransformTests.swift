import XCTest
@testable import VerbKit

/// `FormTransformer` over the real data: every one-facet step of every verb's forms, and
/// every span the matcher finds in the golden sentences (#146).
final class RealFormTransformTests: XCTestCase {
    private static var verbs: [Verb] = []
    private static var index: FormIndex!
    private static var transformer: FormTransformer!

    override class func setUp() {
        super.setUp()
        verbs = (try? RealVerbs.load()) ?? []
        index = FormIndex(verbs: verbs, catalogue: .bundled)
        transformer = FormTransformer(verbs: verbs, catalogue: .bundled)
    }

    /// A sentence that is the form alone, ended with 。, and its one-candidate span.
    private func sentence(_ surface: String, verb: String, form: FormID) -> (text: String, span: VerbSpan) {
        let text = surface + "。"
        let span = VerbSpan(
            range: text.startIndex..<text.index(text.startIndex, offsetBy: surface.count), surface: surface, status: .known,
            candidates: [VerbCandidate(verbID: verb, chain: [ChainPart(surface: surface, kind: .form(form), isRuleBuilt: false)])]
        )
        return (text, span)
    }

    func testEveryStepGivesTheStoredSurface() throws {
        XCTAssertEqual(Self.verbs.count, 84)
        var rewrites = 0
        for verb in Self.verbs {
            let forms = Word(verb).forms
            let spelling = KanjiSpelling(verb)
            for spec in FormCatalogue.bundled.specs(for: .verb) {
                guard let kana = forms[spec.id], !kana.isEmpty else { continue }
                let steps = Self.transformer.steps(from: spec.id)
                let scripts = [kana] + (spelling?.spell(kana).map { [$0] } ?? [])
                for (script, surface) in scripts.enumerated() {
                    let (text, span) = sentence(surface, verb: verb.id, form: spec.id)
                    let result = Self.transformer.transforms(for: span, in: text)
                    let context = "\(surface) (\(verb.id), \(spec.id.rawValue))"
                    guard !steps.isEmpty else {
                        XCTAssertEqual(result, .unavailable(.noOneStepTransform), context)
                        continue
                    }
                    XCTAssertEqual(result.transforms.map(\.step), steps, context)
                    for transform in result.transforms {
                        XCTAssertEqual(transform.verbID, verb.id, context)
                        let stored = try XCTUnwrap(forms[transform.step.to], context)
                        let expected = script == 0 ? stored : try XCTUnwrap(spelling?.spell(stored), context)
                        XCTAssertEqual(transform.rewrite?.surface, expected, "\(context) → \(transform.step.to.rawValue)")
                        XCTAssertEqual(transform.rewrite?.sentence, expected + "。", context)
                        XCTAssertNil(transform.rewrite?.note, context)
                        // What it writes, the index reads back as that verb in that form.
                        XCTAssertTrue(Self.index.hits(for: expected).contains { $0.verbID == verb.id && $0.formID == transform.step.to }, context)
                        rewrites += 1
                    }
                }
            }
        }
        // 108 steps for a verb with all four grids and the six register pairs (4 × 8 × 3 + 6 × 2);
        // 84 without the potential grid (分かる, 知る, 疲れる, 出来る, 見える, 聞こえる, 開く, 降る).
        // 76 verbs are written in kana and kanji; する, つける, もらう, なる and あげる in kana only,
        // and くれる too, without the potential grid. ある has the basic and んです grids and three
        // of the pairs: 54 steps; いる has no ている grid: 3 × 24 + 3 × 2 = 78 steps.
        XCTAssertEqual(rewrites, 2 * (68 * 108 + 8 * 84) + 5 * 108 + 84 + 54 + 78)
    }

    // MARK: The golden sentences

    struct Tally: Equatable {
        /// Spans the matcher finds, and how many have chips.
        var spans = 0
        var withChips = 0
        var unavailable: [TransformReason: Int] = [:]
        var rewrites = 0
        var disabled: [TransformReason: Int] = [:]
    }

    /// Runs the matcher and the transformer over a fixture and checks every rewrite: only its
    /// range changes, the new surface is the verb's form in the data, register changes only
    /// at the end of a sentence, and a plain question never keeps か.
    private func tally(_ name: String) throws -> Tally {
        struct Fixture: Decodable {
            struct Sentence: Decodable { var text: String }
            var sentences: [Sentence]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let matcher = VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: try FixedTokenizer.recorded())
        var tally = Tally()
        for sentence in fixture.sentences {
            let text = sentence.text
            for span in matcher.spans(in: text) {
                tally.spans += 1
                // An ambiguous span: as if the learner picked its first reading.
                let result = Self.transformer.transforms(for: span, in: text, candidate: span.candidates.first)
                if case .unavailable(let reason) = result {
                    tally.unavailable[reason, default: 0] += 1
                    continue
                }
                tally.withChips += 1
                let context = SentenceContext(span: span.range, in: text)
                for transform in result.transforms {
                    let label = "\(span.surface) → \(transform.step.to.rawValue) in \(text)"
                    guard let rewrite = transform.rewrite else {
                        tally.disabled[transform.disabledReason!, default: 0] += 1
                        if transform.disabledReason == .midSentence { XCTAssertFalse(context.isFinal, label) }
                        continue
                    }
                    tally.rewrites += 1
                    XCTAssertEqual(rewrite.range.lowerBound, span.range.lowerBound, label)
                    XCTAssertEqual(text[..<rewrite.range.lowerBound] + rewrite.replacement + text[rewrite.range.upperBound...], rewrite.sentence, label)
                    XCTAssertTrue(rewrite.replacement.hasPrefix(rewrite.surface), label)
                    XCTAssertTrue(Self.index.hits(for: rewrite.surface).contains { $0.verbID == transform.verbID && $0.formID == transform.step.to }, label)
                    if transform.step.facet == .register {
                        XCTAssertTrue(context.isFinal, label)
                        if rewrite.note == .plainQuestion { XCTAssertFalse(rewrite.sentence.contains(rewrite.surface + "か"), label) }
                    } else {
                        XCTAssertEqual(rewrite.range, span.range, label)
                    }
                }
            }
        }
        return tally
    }

    func testTheFortyOneTestSentences() throws {
        // 53 spans: 25 with chips; 25 derived forms or rule-built chains and 3 greyed without.
        let tally = try tally("lens-test-sentences")
        XCTAssertEqual(tally, Tally(
            spans: 53, withChips: 25, unavailable: [.noOneStepTransform: 25, .notInApp: 3],
            rewrites: 67, disabled: [.midSentence: 7, .explanatory: 1]
        ))
    }

    func testTheLessonSentences() throws {
        // The lessons teach many derived forms and chains, so fewer spans have chips.
        let tally = try tally("lens-lesson-sentences")
        XCTAssertEqual(tally, Tally(
            spans: 267, withChips: 139, unavailable: [.noOneStepTransform: 120, .notInApp: 8],
            rewrites: 315, disabled: [
                .midSentence: 46, .explanatory: 3, .fixedBy(marker: "前に"): 3,
                .fixedBy(marker: "べき"): 18, .fixedBy(marker: "ほうがいい"): 18,
            ]
        ))
    }

    func testGoldenSentencesFromTheIssue() throws {
        let matcher = VerbMatcher(index: Self.index, verbs: Self.verbs, tokenizer: try FixedTokenizer.recorded())
        func chips(_ text: String, _ surface: String) throws -> [FormFacet: FormTransform.Outcome] {
            let span = try XCTUnwrap(matcher.spans(in: text).first { $0.surface == surface }, "\(surface) in \(text)")
            return Dictionary(uniqueKeysWithValues: Self.transformer.transforms(for: span, in: text).transforms.map { ($0.step.facet, $0.outcome) })
        }
        let bought = try chips("先週買った本はとても面白かったです。", "買った")
        XCTAssertEqual(bought[.register], .disabled(.midSentence))
        XCTAssertNotNil(bought[.polarity].flatMap { if case .rewrite(let r) = $0 { r } else { nil } })
        let drink = try chips("毎朝コーヒーを飲みます。", "飲みます")
        guard case .rewrite(let plain) = drink[.register] else { return XCTFail("飲みます has no plain rewrite") }
        XCTAssertEqual(plain.sentence, "毎朝コーヒーを飲む。")
        let know = try chips("あの人を知っていますか。", "知っています")
        guard case .rewrite(let question) = know[.register] else { return XCTFail("知っています has no plain rewrite") }
        XCTAssertEqual(question.sentence, "あの人を知っている？")
        XCTAssertEqual(question.note, .plainQuestion)
        let come = try chips("友達が来る前に、部屋を掃除しておく。", "来る")
        XCTAssertEqual(Set(come.values), [.disabled(.fixedBy(marker: "前に"))])
    }
}
