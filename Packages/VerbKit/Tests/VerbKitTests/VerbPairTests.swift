import XCTest
import SwiftData
@testable import VerbKit

final class VerbPairTests: XCTestCase {
    private let forms = VerbForms(
        masuPos: "あけます", masuNeg: "あけません", masuPast: "あけました",
        masuPastNeg: "あけませんでした", te: "あけて", shortPos: "あける",
        shortNeg: "あけない", shortPast: "あけた", shortPastNeg: "あけなかった"
    )

    private var akeru: Verb {
        Verb(type: .ru, label: "Ru-verb", dict: "あける", kanji: "開ける", meaning: "to open",
             description: "d", forms: forms, examples: [],
             pair: VerbPair(verb: "あく", transitivity: .transitive, jp: "ドアを開ける", en: "open the door"))
    }

    private var aku: Verb {
        Verb(type: .u, label: "U-verb", dict: "あく", kanji: "開く", meaning: "to open (by itself)",
             description: "d", forms: forms, examples: [],
             pair: VerbPair(verb: "あける", transitivity: .intransitive, jp: "ドアが開く", en: "the door opens"))
    }

    func testAVerbWithoutAPairDecodesWithNone() throws {
        let json = Data("""
        {"type": "ru", "label": "Ru-verb", "dict": "あける", "meaning": "m", "description": "d",
         "forms": {"masu_pos": "a", "masu_neg": "a", "masu_past": "a", "masu_past_neg": "a", "te": "a",
         "short_pos": "a", "short_neg": "a", "short_past": "a", "short_past_neg": "a"}, "examples": []}
        """.utf8)
        XCTAssertNil(try JSONDecoder().decode(Verb.self, from: json).pair)
    }

    func testAPairDecodes() throws {
        let json = Data("""
        {"type": "ru", "label": "Ru-verb", "dict": "あける", "meaning": "m", "description": "d",
         "forms": {"masu_pos": "a", "masu_neg": "a", "masu_past": "a", "masu_past_neg": "a", "te": "a",
         "short_pos": "a", "short_neg": "a", "short_past": "a", "short_past_neg": "a"}, "examples": [],
         "pair": {"verb": "あく", "transitivity": "transitive", "jp": "ドアを開ける", "en": "open the door"}}
        """.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Verb.self, from: json).pair, akeru.pair)
    }

    func testEncodingRoundTrips() throws {
        XCTAssertEqual(try JSONDecoder().decode(Verb.self, from: JSONEncoder().encode(akeru)), akeru)
    }

    func testTheParticleFollowsTheTransitivity() {
        XCTAssertEqual(Transitivity.transitive.particle, "を")
        XCTAssertEqual(Transitivity.intransitive.particle, "が")
    }

    func testThePartnerIsFoundById() {
        XCTAssertEqual(akeru.pairPartner(in: [akeru, aku])?.id, "あく")
        XCTAssertEqual(aku.pairPartner(in: [akeru, aku])?.id, "あける")
        XCTAssertNil(akeru.pairPartner(in: [akeru]), "no partner in the data, no card")
    }

    @MainActor
    func testPairsSurviveSwiftDataRoundTrip() throws {
        let persisting = SwiftDataVerbPersisting(modelContext: ModelContext(try VerbModelContainer.makeInMemory()))
        try persisting.replaceAllVerbs(with: [akeru, aku])
        let loaded = try persisting.loadAllVerbs()
        XCTAssertEqual(loaded.first { $0.id == "あける" }?.pair, akeru.pair)
        XCTAssertEqual(loaded.first { $0.id == "あく" }?.pair, aku.pair)
    }

    func testAnEntityWithoutAPairReadsAsNone() {
        var verb = akeru
        verb.pair = nil
        XCTAssertNil(VerbEntity(verb).toVerb()?.pair)
    }

    func testRealDataPairsAreSymmetric() throws {
        let verbs = try RealVerbs.load()
        let paired = verbs.filter { $0.pair != nil }
        XCTAssertEqual(paired.count, 14)
        for verb in paired {
            let partner = try XCTUnwrap(verb.pairPartner(in: verbs), verb.id)
            XCTAssertEqual(partner.pair?.verb, verb.id)
            XCTAssertNotEqual(partner.pair?.transitivity, verb.pair?.transitivity)
        }
        let tsuku = try XCTUnwrap(verbs.first { $0.id == "つく:点く" })
        XCTAssertEqual(tsuku.pair?.verb, "つける")
    }
}
