import XCTest
@testable import VerbKit

/// Builds the reverse form index over the real `data/verbs.json` and the bundled catalogue.
/// The counts are pinned as a regression check: when the data grows they change, and the
/// new numbers should be read and updated on purpose, not waved through.
final class RealFormIndexTests: XCTestCase {
    private static var verbs: [Verb] = []
    private static var index: FormIndex!

    override class func setUp() {
        super.setUp()
        verbs = (try? RealVerbs.load()) ?? []
        index = FormIndex(verbs: verbs, catalogue: .bundled)
    }

    private var index: FormIndex { Self.index }

    // MARK: Round trip

    func testEveryFormOfEveryVerbResolvesInKanaAndKanji() throws {
        var forms = 0
        var withoutKanji: [String] = []
        for verb in Self.verbs {
            let spelling = KanjiSpelling(verb)
            if spelling == nil { withoutKanji.append(verb.id) }
            for (spec, kana) in FormCatalogue.bundled.available(in: Word(verb).forms, for: .verb) {
                forms += 1
                XCTAssertTrue(index.hits(for: kana).contains(FormHit(verbID: verb.id, formID: spec.id, script: .kana)), "\(verb.id) \(spec.id) \(kana)")
                guard let spelling else { continue }
                let kanji = try XCTUnwrap(spelling.spell(kana), "\(verb.id) \(spec.id) \(kana) has no kanji spelling")
                XCTAssertTrue(index.hits(for: kanji).contains(FormHit(verbID: verb.id, formID: spec.id, script: .kanji)), "\(verb.id) \(spec.id) \(kanji)")
            }
        }
        XCTAssertEqual(forms, 4_570)
        XCTAssertEqual(index.statistics.forms, 4_570)
        XCTAssertEqual(index.statistics.spellingFailures, 0)
        // Kana only: 付ける, 貰う and 出来る won't match until the data has their kanji.
        XCTAssertEqual(withoutKanji, ["する", "ある", "つける", "もらう"])
    }

    // MARK: Pinned counts

    func testSurfaceCountsArePinned() {
        let stats = index.statistics
        XCTAssertEqual(Self.verbs.count, 65)
        XCTAssertEqual(stats.surfaces, 8_735)
        XCTAssertEqual(stats.kanaSurfaces, 4_450)
        XCTAssertEqual(stats.kanjiSurfaces, 4_285)
        XCTAssertEqual(stats.stems, 880)
        let surfaces = index.surfaces
        XCTAssertEqual(surfaces.map(\.count).min(), 2)
        XCTAssertEqual(surfaces.map(\.count).max(), 12)
        // 食べ… is a proper prefix of 食べた, 食べたい…: longest match has to choose.
        let prefixes = Set(surfaces.flatMap { surface in (1..<surface.count).map { String(surface.prefix($0)) } })
        XCTAssertEqual(surfaces.filter(prefixes.contains).count, 1_558)
    }

    func testAmbiguityCountsArePinned() {
        XCTAssertEqual(index.statistics.ambiguous, 149)
        XCTAssertEqual(index.statistics.sameVerbAmbiguous, 38)
        XCTAssertEqual(index.statistics.crossVerbAmbiguous, 111)
        XCTAssertEqual(index.ambiguousSurfaces(.sameVerb).count, 38)
        XCTAssertEqual(index.ambiguousSurfaces(.crossVerb).count, 111)
    }

    func testEverySameVerbAmbiguityIsPassiveEqualsPotential() {
        for surface in index.ambiguousSurfaces(.sameVerb) {
            XCTAssertEqual(Set(index.hits(for: surface).map(\.formID)), ["passive", "potential"], surface)
        }
    }

    /// The seven families from the research. 着る / 来る / 切る is one family of two pairs:
    /// 着る and 来る share きた, きて…; 着る and 切る share きる, きれば, きられる.
    func testCrossVerbAmbiguitiesFallInTheKnownFamilies() {
        var families: [Set<String>: Int] = [:]
        for surface in index.ambiguousSurfaces(.crossVerb) {
            families[Set(index.hits(for: surface).verbIDs), default: 0] += 1
        }
        XCTAssertEqual(families, [
            ["あう", "ある"]: 8,
            ["いう", "いく"]: 23,
            ["きる", "くる"]: 37,
            ["きる", "きる:切る"]: 8,
            ["よぶ", "よむ"]: 23,
            ["かう", "かえる"]: 1,
            ["いれる", "はいる"]: 9,
            ["だす", "でる"]: 2,
        ])
    }

    // MARK: Known readings

    func testTaberareruListsPassiveAndPotential() {
        let hits = index.hits(for: "食べられる")
        XCTAssertEqual(Set(hits.map(\.formID)), ["passive", "potential"])
        XCTAssertEqual(hits.verbIDs, ["たべる"])
        XCTAssertEqual(hits.ambiguity, .sameVerb)
    }

    func testKanjiTellsIttaApartAndKanaListsBoth() {
        XCTAssertEqual(index.hits(for: "言った"), [FormHit(verbID: "いう", formID: "short_past", script: .kanji)])
        XCTAssertEqual(index.hits(for: "行った"), [FormHit(verbID: "いく", formID: "short_past", script: .kanji)])
        let kana = index.hits(for: "いった")
        XCTAssertEqual(Set(kana.verbIDs), ["いう", "いく"])
        XCTAssertEqual(kana.ambiguity, .crossVerb)
    }

    func testKanaKiListsWearComeAndCut() {
        XCTAssertEqual(Set(index.hits(for: "きた").verbIDs), ["きる", "くる"])
        XCTAssertEqual(index.hits(for: "来た").verbIDs, ["くる"])
        XCTAssertEqual(index.hits(for: "着た").verbIDs, ["きる"])
        XCTAssertEqual(Set(index.hits(for: "きる").verbIDs), ["きる", "きる:切る"])
        XCTAssertEqual(index.hits(for: "切った").verbIDs, ["きる:切る"])
    }

    func testKanjiCreatesTheIreruAndDasaseruAmbiguities() {
        let ireru = index.hits(for: "入れる")
        XCTAssertEqual(Set(ireru.map { "\($0.verbID) \($0.formID.rawValue)" }), ["いれる short_pos", "はいる potential"])
        XCTAssertEqual(index.hits(for: "いれる").verbIDs, ["いれる"])
        XCTAssertEqual(index.hits(for: "はいれる").verbIDs, ["はいる"])
        XCTAssertEqual(Set(index.hits(for: "出させる").verbIDs), ["だす", "でる"])
        XCTAssertEqual(Set(index.hits(for: "かえる").map(\.formID)), ["short_pos", "potential"])
    }

    func testLongestMatchStopsAtTheLongestGeneratedSurface() throws {
        // What #145's tail rules are for: the data has no 食べさせられなかった, so the index
        // alone finds nothing at 食 and reads the end of the chain as ある.
        let text = "母に野菜を食べさせられなかった。"
        let start = try XCTUnwrap(text.firstIndex(of: "食"))
        XCTAssertNil(index.longestMatch(in: text, from: start))
        let nakatta = try XCTUnwrap(text.range(of: "なかった")).lowerBound
        XCTAssertEqual(index.longestMatch(in: text, from: nakatta)?.hits.verbIDs, ["ある"])
        // The stems are where the tail rules attach.
        let stems = index.stemMatches(in: text, from: start)
        XCTAssertEqual(stems.map(\.stem), ["食べさせられ", "食べさせ"])
        XCTAssertEqual(stems.map { $0.hits.map(\.formID) }, [["causative_passive"], ["causative"]])
    }

    func testBuildingTheRealIndex() {
        let verbs = Self.verbs
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = FormIndex(verbs: verbs, catalogue: .bundled)
        }
    }
}
