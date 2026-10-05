import XCTest
@testable import VerbKit

final class DialectCatalogueTests: XCTestCase {
    private let catalogue = DialectCatalogue.bundled

    func testBundledCatalogueDecodes() {
        XCTAssertFalse(catalogue.dialects.isEmpty)
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(catalogue.dialects.map(\.id)).count, catalogue.dialects.count)
    }

    func testEveryPrefectureHasADialect() {
        for prefecture in Prefecture.allCases {
            XCTAssertFalse(catalogue.dialects(in: prefecture).isEmpty, prefecture.rawValue)
        }
    }

    func testEveryRecordsRegionMatchesItsPrefectures() {
        for record in catalogue.dialects {
            XCTAssertFalse(record.prefectures.isEmpty, record.id)
            for prefecture in record.prefectures {
                XCTAssertEqual(prefecture.region, record.region, "\(record.id) \(prefecture)")
            }
        }
    }

    func testRomajiUsesTheBenForm() {
        for record in catalogue.dialects where record.name.hasSuffix("弁") {
            XCTAssertTrue(record.romaji.hasSuffix("-ben"), record.id)
            XCTAssertTrue(record.kana.hasSuffix("べん"), record.id)
        }
    }

    func testWellKnownDialects() throws {
        let hida = try XCTUnwrap(catalogue.dialects.first { $0.name == "飛騨弁" })
        XCTAssertTrue(hida.aliases.contains("高山弁"))
        XCTAssertEqual(hida.prefectures, [.gifu])
        let kansai = try XCTUnwrap(catalogue.dialects.first { $0.name == "関西弁" })
        XCTAssertEqual(kansai.region, .kansai)
        XCTAssertGreaterThan(kansai.prefectures.count, 1)
        let tohoku = try XCTUnwrap(catalogue.dialects.first { $0.name == "東北弁" })
        XCTAssertEqual(Set(tohoku.prefectures), Set(Region.tohoku.prefectures))
        for name in ["大阪弁", "京都弁", "神戸弁", "河内弁", "博多弁", "名古屋弁", "津軽弁", "沖縄方言", "美濃弁", "出雲弁"] {
            XCTAssertNotNil(catalogue.dialects.first { $0.name == name }, name)
        }
    }

    func testRegionLookup() {
        let kansai = catalogue.dialects(in: .kansai)
        XCTAssertTrue(kansai.contains { $0.name == "大阪弁" })
        XCTAssertFalse(kansai.contains { $0.name == "博多弁" })
    }
}
