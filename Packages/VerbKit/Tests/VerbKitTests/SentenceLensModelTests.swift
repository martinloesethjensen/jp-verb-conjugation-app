import XCTest
@testable import VerbKit

/// The Sentence lens state (#147) on the real verbs, with fixed tokens as in
/// `FormLookupTests`: segments, highlight styles, VoiceOver labels, the tapped verb's
/// transforms and preview, and the transcript clean-up.
@MainActor
final class SentenceLensModelTests: XCTestCase {
    private static var verbs: [Verb] = []

    override class func setUp() {
        super.setUp()
        verbs = (try? RealVerbs.load()) ?? []
    }

    /// A lens over the sentence the space-separated tokens spell.
    private func lens(_ tokens: String...) -> SentenceLensModel {
        let store = FormLookupStore(tokenizer: FixedTokenizer(tokens))
        store.update(verbs: Self.verbs, verbsVersion: "test")
        return SentenceLensModel(store: store, text: tokens[0].replacingOccurrences(of: " ", with: ""))
    }

    private func verbItem(_ lens: SentenceLensModel, _ surface: String) throws -> FormLookup.Item {
        try XCTUnwrap(lens.items.first { $0.surface == surface }, "no verb \(surface) in \(lens.sentence)")
    }

    // MARK: Segments

    func testTheSentenceIsCutIntoTextAndVerbs() throws {
        let lens = lens("母 に 野菜 を 食べ させ られ なかっ た 。")
        let segments = lens.segments
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.first, .text("母に野菜を"))
        guard case .verb(let item) = segments[1] else { return XCTFail("expected a verb, got \(segments[1])") }
        XCTAssertEqual(item.surface, "食べさせられなかった")
        XCTAssertEqual(segments.last, .text("。"))
    }

    func testSpacesAroundTheTextDontShiftTheHighlights() throws {
        let lens = lens("毎朝 コーヒー を 飲み ます 。")
        lens.text = "\n  毎朝コーヒーを飲みます。  "
        XCTAssertEqual(lens.sentence, "毎朝コーヒーを飲みます。")
        XCTAssertEqual(lens.segments, [.text("毎朝コーヒーを"), .verb(try verbItem(lens, "飲みます")), .text("。")])
    }

    func testBlankTextHasNoSegments() {
        let lens = lens("飲み ます")
        lens.text = "   "
        XCTAssertTrue(lens.isBlank)
        XCTAssertEqual(lens.segments, [])
    }

    // MARK: Highlights

    func testEachKindOfFormHasItsOwnUnderline() throws {
        XCTAssertEqual(try verbItem(lens("飲み まし た"), "飲みました").highlight, .basic)
        XCTAssertEqual(try verbItem(lens("食べ て い ます"), "食べています").highlight, .chain)
        XCTAssertEqual(try verbItem(lens("忘れ て しまい まし た"), "忘れてしまいました").highlight, .chain)
        XCTAssertEqual(try verbItem(lens("泳げ ます"), "泳げます").highlight, .voice)
        XCTAssertEqual(try verbItem(lens("食べ させ られ なかっ た"), "食べさせられなかった").highlight, .voice)
        XCTAssertEqual(try verbItem(lens("約束 を 守っ たら"), "守ったら").highlight, .notInApp)
    }

    // MARK: VoiceOver

    func testAHighlightReadsItsVerbGroupAndForm() throws {
        let item = try verbItem(lens("食べ させ られ なかっ た"), "食べさせられなかった")
        XCTAssertEqual(item.accessibilityDescription, "食べさせられなかった, verb 食べる, ru-verb, causative-passive, plain past negative")
        let polite = try verbItem(lens("飲み まし た"), "飲みました")
        XCTAssertEqual(polite.accessibilityDescription, "飲みました, verb 飲む, u-verb, polite past")
    }

    func testAGreyedHighlightSaysItIsNotInTheApp() throws {
        XCTAssertEqual(try verbItem(lens("約束 を 守っ たら"), "守ったら").accessibilityDescription, "守ったら, verb not in the app yet")
    }

    func testAnAmbiguousHighlightReadsEveryReading() throws {
        let item = try verbItem(lens("きた"), "きた")
        XCTAssertTrue(item.accessibilityDescription.hasPrefix("きた, \(item.readings.count) possible readings: verb "))
        XCTAssertTrue(item.accessibilityDescription.contains("; or verb "))
    }

    // MARK: Transforms and preview

    func testATransformPreviewsTheRewrittenSentenceAndOriginalResetsIt() throws {
        let lens = lens("毎朝 コーヒー を 飲み ます 。")
        lens.selected = try verbItem(lens, "飲みます")
        let transforms = lens.transforms.transforms
        XCTAssertEqual(transforms.map(\.step.facet), [.register, .polarity, .tense])
        let negative = try XCTUnwrap(transforms.first { $0.step.facet == .polarity })
        XCTAssertEqual(lens.label(for: negative.step.to), "Polite · negative")

        lens.apply(negative)
        let preview = try XCTUnwrap(lens.preview)
        XCTAssertEqual(preview.before, "毎朝コーヒーを")
        XCTAssertEqual(preview.replacement, "飲みません")
        XCTAssertEqual(preview.after, "。")
        XCTAssertEqual(lens.outputText, "毎朝コーヒーを飲みません。")

        lens.resetPreview()
        XCTAssertNil(lens.preview)
        XCTAssertEqual(lens.outputText, "毎朝コーヒーを飲みます。")
    }

    func testADisabledTransformIsNotApplied() throws {
        let lens = lens("飲み ます か 。")
        lens.selected = try verbItem(lens, "飲みます")
        let disabled = FormTransform(
            verbID: "のむ", step: FormStep(facet: .tense, from: "masu_pos", to: "masu_past"), outcome: .disabled(.notInData)
        )
        lens.apply(disabled)
        XCTAssertNil(lens.applied)
    }

    func testTappingAnotherVerbOrReadingClearsThePreview() throws {
        let lens = lens("毎朝 コーヒー を 飲み ます 。")
        lens.selected = try verbItem(lens, "飲みます")
        lens.apply(try XCTUnwrap(lens.transforms.transforms.first { $0.rewrite != nil }))
        XCTAssertNotNil(lens.preview)
        lens.chosenReadingID = "something else"
        XCTAssertNil(lens.applied)

        lens.apply(try XCTUnwrap(lens.transforms.transforms.first { $0.rewrite != nil }))
        lens.selected = nil
        XCTAssertNil(lens.applied)
        XCTAssertNil(lens.chosenReading)
    }

    func testAnAmbiguousVerbTransformsTheChosenReading() throws {
        let lens = lens("ともだち が うち に きた 。")
        let item = try verbItem(lens, "きた")
        lens.selected = item
        XCTAssertEqual(lens.chosenReading, item.readings.first)
        let other = try XCTUnwrap(item.readings.last)
        lens.chosenReadingID = other.id
        XCTAssertEqual(lens.chosenReading, other)
        for transform in lens.transforms.transforms {
            XCTAssertEqual(transform.verbID, other.verb.id)
        }
    }

    func testAGreyedVerbHasNoTransforms() throws {
        let lens = lens("約束 を 守っ たら")
        lens.selected = try verbItem(lens, "守ったら")
        XCTAssertEqual(lens.transforms, .unavailable(.notInApp))
    }

    // MARK: Transcripts

    func testATranscriptLosesTheSpacesSpeechPutsBeforeDigits() {
        XCTAssertEqual(LensText.transcript("駅まで歩いて 10分かかります。"), "駅まで歩いて10分かかります。")
        XCTAssertEqual(LensText.transcript(" 3年 前 に "), "3年前に")
        // Between two Latin words the space stays.
        XCTAssertEqual(LensText.transcript("iPhone 17 で"), "iPhone 17で")
    }

    func testFinalisedSegmentsJoinWithoutASpace() {
        let lens = lens("飲み ます")
        lens.text = ""
        lens.appendTranscript("昨日友達と ")
        lens.appendTranscript(" 映画を見ました。")
        lens.appendTranscript("  ")
        XCTAssertEqual(lens.text, "昨日友達と映画を見ました。")
    }

    func testLineBreaksBecomeSpaces() {
        XCTAssertEqual(LensText.sentence(from: " 雨が降った。\n傘を持った。\n"), "雨が降った。 傘を持った。")
    }
}
