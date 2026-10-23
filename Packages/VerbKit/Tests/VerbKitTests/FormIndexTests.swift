import XCTest
@testable import VerbKit

final class FormIndexTests: XCTestCase {
    /// A ru-verb with the forms the tests need: passive = potential, as in the real data.
    private func ruVerb(_ dict: String, _ kanji: String?, id: String? = nil) -> Verb {
        let stem = String(dict.dropLast())
        return Verb(
            type: .ru, label: "Ru-verb", dict: dict, kanji: kanji, meaning: "m", description: "d",
            forms: VerbForms(
                masuPos: stem + "ます", masuNeg: stem + "ません", masuPast: stem + "ました",
                masuPastNeg: stem + "ませんでした", te: stem + "て", shortPos: dict,
                shortNeg: stem + "ない", shortPast: stem + "た", shortPastNeg: stem + "なかった",
                potential: stem + "られる", passive: stem + "られる", tai: stem + "たい"
            ),
            examples: [],
            id: id
        )
    }

    private var taberu: Verb { ruVerb("たべる", "食べる") }
    /// Same kana as 着る, which keeps the bare id, so the id is what tells them apart.
    private var kiruWear: Verb { ruVerb("きる", "着る") }
    private var kiruOther: Verb { ruVerb("きる", "斬る", id: "きる:斬る") }
    private var iru: Verb { ruVerb("いる", nil) }

    private func catalogue(_ ids: [String]) throws -> FormCatalogue {
        let forms = ids.map { id in
            #"{"id": "\#(id)", "family": "basic", "label": "\#(id)", "role": "finite", "applies_to": ["verb"], "source": "derived"}"#
        }
        let json = #"{"schema": 1, "families": [{"id": "basic", "title": "Basic"}], "forms": [\#(forms.joined(separator: ","))]}"#
        return try FormCatalogue(data: Data(json.utf8))
    }

    func testEveryFormIsIndexedInKanaAndKanji() {
        let index = FormIndex(verbs: [taberu], catalogue: .bundled)
        XCTAssertEqual(index.hits(for: "たべました"), [FormHit(verbID: "たべる", formID: "masu_past", script: .kana)])
        XCTAssertEqual(index.hits(for: "食べました"), [FormHit(verbID: "たべる", formID: "masu_past", script: .kanji)])
        XCTAssertEqual(index.hits(for: "食べ"), [])
        XCTAssertEqual(index.statistics.forms, 12)
        XCTAssertEqual(index.statistics.spellingFailures, 0)
    }

    func testAVerbWithoutKanjiIsIndexedInKanaOnly() {
        let index = FormIndex(verbs: [iru], catalogue: .bundled)
        XCTAssertEqual(index.hits(for: "います").map(\.script), [.kana])
        XCTAssertEqual(index.statistics.kanjiSurfaces, 0)
        XCTAssertEqual(index.statistics.surfaces, index.statistics.kanaSurfaces)
    }

    func testPassiveAndPotentialAreOneVerbsAmbiguity() {
        let hits = FormIndex(verbs: [taberu], catalogue: .bundled).hits(for: "食べられる")
        XCTAssertEqual(hits.map(\.formID), ["potential", "passive"])
        XCTAssertEqual(hits.ambiguity, .sameVerb)
        XCTAssertEqual(hits.verbIDs, ["たべる"])
    }

    func testHomophonesStayApartByID() {
        let index = FormIndex(verbs: [kiruWear, kiruOther], catalogue: .bundled)
        let kana = index.hits(for: "きた")
        XCTAssertEqual(kana.verbIDs, ["きる", "きる:斬る"])
        XCTAssertEqual(kana.ambiguity, .crossVerb)
        XCTAssertEqual(index.hits(for: "着た").verbIDs, ["きる"])
        XCTAssertEqual(index.hits(for: "斬た").verbIDs, ["きる:斬る"])
        XCTAssertEqual(index.ambiguousSurfaces(.crossVerb).count, index.statistics.crossVerbAmbiguous)
    }

    func testMatchesFindEverySurfaceAtAPositionLongestFirst() throws {
        let index = FormIndex(verbs: [taberu], catalogue: .bundled)
        let text = "もう食べたい。"
        let start = try XCTUnwrap(text.firstIndex(of: "食"))
        let matches = index.matches(in: text, from: start)
        XCTAssertEqual(matches.map(\.surface), ["食べたい", "食べた"])
        XCTAssertEqual(matches.map { $0.hits.map(\.formID) }, [["tai"], ["short_past"]])
        XCTAssertEqual(index.longestMatch(in: text, from: start)?.surface, "食べたい")
        XCTAssertEqual(String(text[matches[0].range]), "食べたい")
        XCTAssertNil(index.longestMatch(in: text, from: text.startIndex))
        XCTAssertTrue(index.matches(in: text, from: text.endIndex).isEmpty)
    }

    func testStemsOfDerivedFormsTakeTheTailRules() throws {
        let index = FormIndex(verbs: [taberu], catalogue: .bundled)
        XCTAssertEqual(Set(index.stemHits(for: "食べられ").map(\.formID)), ["passive", "potential"])
        XCTAssertEqual(index.stemHits(for: "食べられ").map(\.pattern), [.ruVerb, .ruVerb])
        XCTAssertEqual(index.stemHits(for: "たべた").map(\.formID), ["tai"])
        XCTAssertEqual(index.stemHits(for: "食べな").map(\.pattern), [.iAdjective])
        XCTAssertEqual(index.stemHits(for: "食べ"), [])

        let text = "食べられなかった"
        let stems = index.stemMatches(in: text, from: text.startIndex)
        XCTAssertEqual(stems.map(\.stem), ["食べられ"])
        XCTAssertEqual(String(text[stems[0].range]), "食べられ")
    }

    // MARK: Rebuilding

    func testTheCacheRebuildsWhenEitherDataVersionChanges() throws {
        let both = try catalogue(["short_pos", "passive", "potential"])
        let potentialOnly = try catalogue(["short_pos", "potential"])
        var cache = FormIndexCache()

        let first = cache.index(verbs: [taberu], catalogue: both, key: .init(verbs: "1.0.0", catalogue: "1"))
        XCTAssertEqual(first.hits(for: "食べられる").map(\.formID), ["passive", "potential"])

        // Same versions: the cached index, even if a caller hands over other data.
        let cached = cache.index(verbs: [taberu, iru], catalogue: potentialOnly, key: .init(verbs: "1.0.0", catalogue: "1"))
        XCTAssertEqual(cached.hits(for: "食べられる").map(\.formID), ["passive", "potential"])
        XCTAssertEqual(cached.hits(for: "いる"), [])

        // A new catalogue version: rebuilt, so the passive is gone.
        let newCatalogue = cache.index(verbs: [taberu], catalogue: potentialOnly, key: .init(verbs: "1.0.0", catalogue: "2"))
        XCTAssertEqual(newCatalogue.hits(for: "食べられる").map(\.formID), ["potential"])
        XCTAssertEqual(cache.key, .init(verbs: "1.0.0", catalogue: "2"))

        // A new verbs version: rebuilt, so the new verb is in.
        let newVerbs = cache.index(verbs: [taberu, iru], catalogue: potentialOnly, key: .init(verbs: "1.1.0", catalogue: "2"))
        XCTAssertEqual(newVerbs.hits(for: "いる").map(\.verbID), ["いる"])
    }

    func testOnlyTheCataloguesFormsAreIndexed() throws {
        let index = FormIndex(verbs: [taberu], catalogue: try catalogue(["short_pos"]))
        XCTAssertEqual(index.surfaces.sorted(), ["たべる", "食べる"])
        XCTAssertEqual(index.statistics.stems, 0)
    }

    // MARK: Scaling

    /// `count` verbs cycled from the real data, each copy behind its own kana prefix so its
    /// surfaces don't collide with the other copies'. 1,000 verbs is about 130k surfaces,
    /// the size #4 aims for.
    private static func verbs(_ count: Int, from real: [Verb]) -> [Verb] {
        let kana = Array("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわ")
        return (0..<count).map { n in
            var verb = real[n % real.count]
            let copy = n / real.count
            let prefix = String([kana[copy / kana.count % kana.count], kana[copy % kana.count]])
            let data = (try? JSONEncoder().encode(verb.forms)) ?? Data()
            var object = (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
            for (key, value) in object { object[key] = prefix + value }
            if let prefixed = try? JSONSerialization.data(withJSONObject: object),
               let forms = try? JSONDecoder().decode(VerbForms.self, from: prefixed) {
                verb.forms = forms
            }
            verb.dict = prefix + verb.dict
            verb.kanji = verb.kanji.map { prefix + $0 }
            verb.explicitID = "\(prefix):\(verb.id)"
            return verb
        }
    }

    func testBuildingScalesLinearlyWithTheVerbCount() throws {
        let real = try RealVerbs.load()
        let small = FormIndex(verbs: Self.verbs(100, from: real), catalogue: .bundled).statistics
        let large = FormIndex(verbs: Self.verbs(1_000, from: real), catalogue: .bundled).statistics
        // Memory: what the index holds grows with the verbs, about 10× for 10× the verbs.
        XCTAssertGreaterThan(large.surfaces, 125_000)
        XCTAssertEqual(large.spellingFailures, 0)
        for (name, ratio) in [
            ("surfaces", Double(large.surfaces) / Double(small.surfaces)),
            ("nodes", Double(large.nodes) / Double(small.nodes)),
            ("stems", Double(large.stems) / Double(small.stems)),
        ] {
            XCTAssertEqual(ratio, 10, accuracy: 1.5, name)
        }
        // Time: 1,000 verbs take about 10× what 100 do, not the 100× of an O(n²) slip.
        XCTAssertScalesLinearly(small: 100, runs: 3, prepare: { Self.verbs($0, from: real) }) {
            _ = FormIndex(verbs: $0, catalogue: .bundled)
        }
        let thousand = Self.verbs(1_000, from: real)
        measure(metrics: [XCTClockMetric()]) { _ = FormIndex(verbs: thousand, catalogue: .bundled) }
    }

    func testMatchingCostsTheSurfaceLengthNotTheIndexSize() throws {
        let real = try RealVerbs.load()
        let text = "母に野菜を食べさせられなかった。先生に名前を呼ばれました。"
        XCTAssertScalesLinearly(small: 100, runs: 3, prepare: { count in
            (FormIndex(verbs: Self.verbs(count, from: real), catalogue: .bundled), count)
        }) { input in
            // Run the same lookups count times: linear in count only if each lookup is
            // independent of the index size.
            for _ in 0..<input.1 {
                var i = text.startIndex
                while i < text.endIndex {
                    _ = input.0.matches(in: text, from: i)
                    i = text.index(after: i)
                }
            }
        }
    }
}
