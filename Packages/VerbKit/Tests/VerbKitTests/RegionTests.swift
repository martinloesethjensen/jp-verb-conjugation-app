import XCTest
@testable import VerbKit

final class RegionTests: XCTestCase {
    func testThereAreFortySevenPrefecturesEachInOneRegion() {
        XCTAssertEqual(Prefecture.allCases.count, 47)
        let listed = Region.allCases.flatMap(\.prefectures)
        XCTAssertEqual(listed.count, 47)
        XCTAssertEqual(Set(listed), Set(Prefecture.allCases))
        for prefecture in Prefecture.allCases {
            XCTAssertTrue(prefecture.region.prefectures.contains(prefecture), prefecture.rawValue)
        }
    }

    func testEveryRegionHasPrefectures() {
        XCTAssertEqual(Region.allCases.count, 8)
        for region in Region.allCases {
            XCTAssertFalse(region.prefectures.isEmpty, region.rawValue)
        }
    }

    func testKnownRegions() {
        XCTAssertEqual(Prefecture.gifu.region, .chubu)
        XCTAssertEqual(Prefecture.kumamoto.region, .kyushuOkinawa)
        XCTAssertEqual(Prefecture.okinawa.region, .kyushuOkinawa)
        XCTAssertEqual(Prefecture.osaka.region, .kansai)
        XCTAssertEqual(Prefecture.hokkaido.region, .hokkaido)
        XCTAssertEqual(Prefecture.tokyo.region, .kanto)
    }

    func testJISOrder() {
        XCTAssertEqual(Prefecture.allCases.first, .hokkaido)
        XCTAssertEqual(Prefecture.allCases.last, .okinawa)
        XCTAssertEqual(Prefecture.allCases.firstIndex(of: .kumamoto), 42)   // JIS code 43
    }

    func testNamesAreUniqueAndFilled() {
        let all = Prefecture.allCases
        XCTAssertEqual(Set(all.map(\.name)).count, 47)
        XCTAssertEqual(Set(all.map(\.kana)).count, 47)
        XCTAssertEqual(Set(all.map(\.romaji)).count, 47)
        XCTAssertEqual(Prefecture.kumamoto.name, "熊本県")
        XCTAssertEqual(Prefecture.tokyo.name, "東京都")
        XCTAssertEqual(Prefecture.kyoto.name, "京都府")
        XCTAssertEqual(Prefecture.kumamoto.romaji, "Kumamoto")
        XCTAssertEqual(Set(Region.allCases.map(\.name)).count, 8)
        XCTAssertEqual(Region.kyushuOkinawa.name, "九州・沖縄")
    }

    func testValueTypesRoundTripThroughJSON() throws {
        let entry = WordBankEntryValue(
            text: "おおきに", reading: "おおきに", kind: .word, wordClass: nil,
            senses: [Sense(meaning: "thank you")],
            equivalents: [StandardEquivalent(written: "ありがとう")]
        )
        let senses = try JSONDecoder().decode([Sense].self, from: JSONEncoder().encode(entry.senses))
        XCTAssertEqual(senses, entry.senses)
        let equivalents = try JSONDecoder().decode([StandardEquivalent].self, from: JSONEncoder().encode(entry.equivalents))
        XCTAssertEqual(equivalents, entry.equivalents)
        XCTAssertEqual(entry.createdAt, entry.updatedAt)
    }
}
