import XCTest
@testable import VerbKit

/// The golden sentences of the Sentence lens (#142) against the real data: the 41 test
/// sentences of the voice research and every distinct lesson sentence in `data/grammar.json`.
/// Each lists its verbs by hand. The index alone settles the exact-match ones; `VerbMatcher`
/// (#145) is scored on all of them, with the tokens recorded in `lens-sentence-tokens.json`.
/// Android can share the fixtures.
final class RealLensSentenceTests: XCTestCase {
    struct Fixture: Decodable {
        struct Sentence: Decodable {
            var text: String
            var set: String?
            var verbs: [Expected]
        }

        struct Expected: Decodable {
            enum Match: String, Decodable {
                /// A generated form of `verb`; `forms` are every form the index lists for it.
                case exact
                /// `verb`, but the surface needs #145's tail rules, stems or contractions.
                case rule
                /// A verb the app doesn't have.
                case notInApp
                /// An index surface whose real verb the app doesn't have (経つ read as 立つ).
                case homograph
                /// Not a verb here, though it looks like one (すみません, じゃない).
                case notAVerb
            }

            var surface: String
            var verb: String?
            var match: Match
            var forms: [FormID]?
        }

        var sentences: [Sentence]
    }

    private static var index: FormIndex!
    private static var matcher: VerbMatcher!
    private static var verbIDs: Set<String> = []

    override class func setUp() {
        super.setUp()
        let verbs = (try? RealVerbs.load()) ?? []
        verbIDs = Set(verbs.map(\.id))
        index = FormIndex(verbs: verbs, catalogue: .bundled)
        matcher = VerbMatcher(index: index, verbs: verbs, tokenizer: (try? FixedTokenizer.recorded()) ?? FixedTokenizer([:]))
    }

    private func load(_ name: String) throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    /// Checks every expected verb the index can speak to, and returns how many of each match kind.
    @discardableResult
    private func check(_ fixture: Fixture) -> [Fixture.Expected.Match: Int] {
        var counts: [Fixture.Expected.Match: Int] = [:]
        for sentence in fixture.sentences {
            for expected in sentence.verbs {
                counts[expected.match, default: 0] += 1
                let context = "\(expected.surface) in \(sentence.text)"
                guard let range = sentence.text.range(of: expected.surface) else {
                    XCTFail("\(expected.surface) is not in \(sentence.text)")
                    continue
                }
                let hits = Self.index.hits(for: expected.surface)
                if let verb = expected.verb {
                    XCTAssertTrue(Self.verbIDs.contains(verb), "no verb \(verb): \(context)")
                }
                switch expected.match {
                case .exact:
                    let verb = expected.verb ?? ""
                    XCTAssertEqual(Set(hits.filter { $0.verbID == verb }.map(\.formID)), Set(expected.forms ?? []), context)
                    XCTAssertFalse(expected.forms?.isEmpty ?? true, context)
                    // Found in place too, as one of the surfaces that start there.
                    let found = Self.index.matches(in: sentence.text, from: range.lowerBound)
                    XCTAssertTrue(found.contains { $0.range == range && $0.hits == hits }, context)
                case .notInApp:
                    XCTAssertEqual(hits, [], context)
                case .homograph:
                    XCTAssertFalse(hits.isEmpty, context)
                case .rule, .notAVerb:
                    break
                }
            }
        }
        return counts
    }

    func testTheFortyOneTestSentences() throws {
        let fixture = try load("lens-test-sentences")
        XCTAssertEqual(fixture.sentences.count, 41)
        XCTAssertEqual(fixture.sentences.filter { $0.set == "dev" }.count, 23)
        XCTAssertEqual(fixture.sentences.filter { $0.set == "heldout" }.count, 18)
        // 46 verbs in the app (32 exact forms, 14 chains for #145) and 8 the app lacks.
        XCTAssertEqual(check(fixture), [.exact: 32, .rule: 14, .notInApp: 8])
    }

    func testTheLessonSentences() throws {
        let fixture = try load("lens-lesson-sentences")
        XCTAssertEqual(fixture.sentences.count, 276)
        XCTAssertEqual(Set(fixture.sentences.map(\.text)).count, 276)
        XCTAssertEqual(check(fixture), [.exact: 157, .rule: 56, .notInApp: 67, .homograph: 3, .notAVerb: 21])
    }

    func testExactSurfacesKeepTheirAmbiguity() throws {
        // ともだちがうちにきた: the index can't tell 来る from 着る in kana; the sheet shows both.
        let fixture = try load("lens-test-sentences")
        let kita = try XCTUnwrap(fixture.sentences.first { $0.text == "ともだちがうちにきた。" }?.verbs.first)
        XCTAssertEqual(kita.verb, "くる")
        XCTAssertEqual(Set(Self.index.hits(for: kita.surface).verbIDs), ["くる", "きる"])
    }

    // MARK: The matcher (#145)

    /// How `VerbMatcher` does on a fixture, in the research's terms, plus what it missed.
    /// A verb counts where a span overlaps its labelled surface; the whole chain counts
    /// where the span is exactly that surface.
    struct Score: Equatable {
        /// Verbs in the app (`exact` and `rule`): how many a span names, and covers exactly.
        var inApp = 0
        var rightVerb = 0
        var wholeChain = 0
        /// Highlights (known or ambiguous spans), and how many name a labelled verb.
        var highlights = 0
        var correctHighlights = 0
        /// Highlights where nothing is labelled.
        var falsePositives: [String] = []
        /// Verbs the app lacks: how many are greyed, and which are highlighted as an app verb.
        /// The rest are left alone.
        var notInApp = 0
        var greyed = 0
        var notInAppHighlighted: [String] = []
        /// Grey spans where no missing verb is labelled.
        var wrongGreys: [String] = []
        /// Stoplist and context cases that were highlighted anyway.
        var notAVerbHighlighted: [String] = []
        /// Homographs of verbs the app lacks (経つ read as 立つ): known failures.
        var homographsHighlighted: [String] = []
        /// In-app verbs not named, and not covered whole.
        var wrongVerb: [String] = []
        var partialChain: [String] = []

        var precision: Double { highlights == 0 ? 1 : Double(correctHighlights) / Double(highlights) }
    }

    private func score(_ fixture: Fixture) -> Score {
        var score = Score()
        for sentence in fixture.sentences {
            let text = sentence.text
            let spans = Self.matcher.spans(in: text)
            let highlighted = spans.filter { $0.status != .notInApp }
            let greyed = spans.filter { $0.status == .notInApp }
            // The verbs are listed in sentence order, so each is looked for after the one
            // before: in 知らないはずがない, the second ない is ある's.
            var located: [(Fixture.Expected, Range<String.Index>)] = []
            var from = text.startIndex
            for expected in sentence.verbs {
                guard let range = text.range(of: expected.surface, range: from..<text.endIndex)
                        ?? text.range(of: expected.surface) else { continue }
                located.append((expected, range))
                from = range.upperBound
            }
            func ranges(_ matches: Fixture.Expected.Match...) -> [(Fixture.Expected, Range<String.Index>)] {
                located.filter { matches.contains($0.0.match) }
            }
            for (expected, range) in ranges(.exact, .rule) {
                let context = "\(expected.surface) in \(text)"
                score.inApp += 1
                let named = highlighted.filter { $0.range.overlaps(range) && $0.verbIDs.contains(expected.verb ?? "") }
                if named.isEmpty { score.wrongVerb.append(context) } else { score.rightVerb += 1 }
                if named.contains(where: { $0.range == range }) {
                    score.wholeChain += 1
                } else {
                    let found = highlighted.filter { $0.range.overlaps(range) }.map(\.surface)
                    score.partialChain.append("\(context) → \(found)")
                }
            }
            for (expected, range) in ranges(.notInApp) {
                score.notInApp += 1
                if highlighted.contains(where: { $0.range.overlaps(range) }) {
                    score.notInAppHighlighted.append("\(expected.surface) in \(text)")
                } else if greyed.contains(where: { $0.range.overlaps(range) }) {
                    score.greyed += 1
                }
            }
            for (expected, range) in ranges(.homograph) where highlighted.contains(where: { $0.range.overlaps(range) }) {
                score.homographsHighlighted.append("\(expected.surface) in \(text)")
            }
            for (expected, range) in ranges(.notAVerb) where highlighted.contains(where: { $0.range.overlaps(range) }) {
                score.notAVerbHighlighted.append("\(expected.surface) in \(text)")
            }
            let labelled = ranges(.exact, .rule, .notInApp, .homograph)
            for span in highlighted {
                score.highlights += 1
                let right = ranges(.exact, .rule).contains { expected, range in
                    span.range.overlaps(range) && span.verbIDs.contains(expected.verb ?? "")
                }
                if right { score.correctHighlights += 1 }
                if !labelled.contains(where: { $0.1.overlaps(span.range) }) {
                    score.falsePositives.append("\(span.surface) in \(text)")
                }
            }
            for span in greyed where !ranges(.notInApp).contains(where: { $0.1.overlaps(span.range) }) {
                score.wrongGreys.append("\(span.surface) in \(text)")
            }
        }
        return score
    }

    func testTheMatcherOnTheTestSentences() throws {
        let score = score(try load("lens-test-sentences"))
        // The research's hybrid: 46/46 right verbs, 44/46 whole chains, 1 false positive,
        // 7/8 missing verbs greyed or left alone. The もらう chains now get whole spans too.
        XCTAssertEqual(score.inApp, 46)
        XCTAssertEqual(score.rightVerb, 46, "\(score.wrongVerb)")
        XCTAssertEqual(score.wholeChain, 46, "\(score.partialChain)")
        XCTAssertEqual(score.falsePositives, [])
        // The one false positive: かける isn't in the app, and かけない is 書く's potential.
        XCTAssertEqual(score.notInAppHighlighted, ["かけないでください in 電車の中で電話をかけないでください。"])
        XCTAssertEqual(score.notInApp, 8)
        // 降ったら, 吸ってはいけません, 思っています, 泣いている and 間に合います are greyed;
        // the kana かかります and なります are left alone.
        XCTAssertEqual(score.greyed, 5)
        XCTAssertEqual(score.wrongGreys, [])
        XCTAssertEqual(score.highlights, 47)
    }

    func testTheMatcherOnTheLessonSentences() throws {
        let score = score(try load("lens-lesson-sentences"))
        XCTAssertEqual(score.inApp, 213)
        XCTAssertEqual(score.rightVerb, 213, "\(score.wrongVerb)")
        XCTAssertEqual(score.wholeChain, 213, "\(score.partialChain)")
        // No false positives from the stoplist and context rules (すみません, どうして,
        // じゃない, かもしれない, 〜みたい, ではありません…), and none elsewhere.
        XCTAssertEqual(score.notAVerbHighlighted, [])
        XCTAssertEqual(score.falsePositives, [])
        XCTAssertEqual(score.notInAppHighlighted, [])
        // Expected failures: homographs of verbs the app lacks. More verbs (#4) fix them.
        XCTAssertEqual(score.homographsHighlighted, [
            "たつ in 時間がたつのは早いものですね。",
            "かける in 夜遅くに電話をかけるものではない。",
            "できる in 駅の前に新しい店ができるらしいです。",
        ])
        // 213 of 216 highlights are right: 98.6%, the research's estimate with the stoplist.
        XCTAssertEqual(score.highlights, 216)
        XCTAssertEqual(score.correctHighlights, 213)
        XCTAssertGreaterThan(score.precision, 0.98)
        // 40 of the 67 missing verbs are greyed; the rest, kana-only (いる, なる, やる…) or
        // not conjugated, are left alone.
        XCTAssertEqual(score.notInApp, 67)
        XCTAssertEqual(score.greyed, 40)
        XCTAssertEqual(score.wrongGreys, [])
    }
}
