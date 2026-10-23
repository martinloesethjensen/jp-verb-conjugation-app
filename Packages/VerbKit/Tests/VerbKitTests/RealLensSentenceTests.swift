import XCTest
@testable import VerbKit

/// The golden sentences of the Sentence lens (#142) against the real data: the 41 test
/// sentences of the voice research and every distinct lesson sentence in `data/grammar.json`.
/// Each lists its verbs by hand. The index alone settles the exact-match ones; #145's matcher
/// extends the same fixtures to the `rule` chains, the stoplist and the greyed verbs, and
/// Android can share them.
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
    private static var verbIDs: Set<String> = []

    override class func setUp() {
        super.setUp()
        let verbs = (try? RealVerbs.load()) ?? []
        verbIDs = Set(verbs.map(\.id))
        index = FormIndex(verbs: verbs, catalogue: .bundled)
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
}
