import XCTest
@testable import VerbKit

final class TagSuggesterTests: XCTestCase {
    private let suggester = TagSuggester()
    private let catalogue = DialectCatalogue.bundled

    private func record(_ name: String) -> DialectRecord {
        catalogue.dialects.first { $0.name == name }!
    }

    private func dialectNames(_ suggestions: [TagSuggestion]) -> [String] {
        suggestions.compactMap {
            if case .dialect(let record) = $0 { return record.name }
            return nil
        }
    }

    private func suggest(
        _ query: String, dialectTags: [DialectTagValue] = [], customTags: [CustomTagValue] = [],
        applied: Set<UUID> = []
    ) -> TagSuggestions {
        suggester.suggestions(for: query, dialectTags: dialectTags, customTags: customTags, excluding: applied)
    }

    // MARK: dialects

    func testTakayamaFindsHidaFirst() {
        XCTAssertEqual(dialectNames(suggest("takayama").dialects).first, "飛騨弁")
    }

    func testKumaFindsKumamoto() {
        XCTAssertEqual(dialectNames(suggest("kuma").dialects).first, "熊本弁")
    }

    func testAPrefectureListsItsDialectsThenThePrefecture() {
        let dialects = suggest("gifu").dialects
        XCTAssertEqual(dialectNames(dialects), ["飛騨弁", "美濃弁"])
        XCTAssertEqual(dialects.last, .prefecture(.gifu))
    }

    func testOsakaIsFoundEveryWay() {
        for query in ["osaka", "おおさか", "Osaka-ben", "大阪弁", "オオサカ"] {
            XCTAssertTrue(dialectNames(suggest(query).dialects).contains("大阪弁"), query)
        }
        XCTAssertEqual(dialectNames(suggest("Osaka-ben").dialects).first, "大阪弁")
    }

    func testOkinawaKanaFindsTheHogenRecord() {
        XCTAssertEqual(dialectNames(suggest("おきなわほうげん").dialects).first, "沖縄方言")
    }

    func testEmptyQuerySuggestsNothing() {
        XCTAssertEqual(suggest("  "), TagSuggestions(yours: [], dialects: [], ideas: [], create: [], isDuplicate: false))
    }

    // MARK: own tags first

    func testAnExistingTagIsYoursNotADialect() {
        let kansai = DialectTagValue(name: "関西弁", romaji: "Kansai-ben", prefectures: [.osaka], region: .kansai, catalogueID: "kansai-ben")
        let result = suggest("kansai", dialectTags: [kansai])
        XCTAssertEqual(result.yours, [.existingDialect(kansai)])
        XCTAssertFalse(dialectNames(result.dialects).contains("関西弁"))
    }

    func testAnExactDuplicateBlocksCreating() {
        let kansai = DialectTagValue(name: "関西弁", romaji: "Kansai-ben", region: .kansai)
        let result = suggest("Kansai-ben", dialectTags: [kansai])
        XCTAssertTrue(result.isDuplicate)
        XCTAssertEqual(result.create, [])

        let food = CustomTagValue(name: "Food")
        let custom = suggest("food", customTags: [food])
        XCTAssertTrue(custom.isDuplicate)
        XCTAssertEqual(custom.yours, [.existingCustom(food)])
    }

    func testAppliedTagsAreNotSuggested() {
        let food = CustomTagValue(name: "food")
        let result = suggest("foo", customTags: [food], applied: [food.id])
        XCTAssertEqual(result.yours, [])
    }

    // MARK: ideas and create

    func testIdeasComeWithAColourAndCreateIsOffered() {
        let result = suggest("food")
        XCTAssertEqual(result.ideas.count, 1)
        guard case .customIdea(let name, let color)? = result.ideas.first else { return XCTFail("no idea") }
        XCTAssertEqual(name, "food")
        XCTAssertEqual(TagSuggester.defaultIdeas.first { $0.0 == "food" }?.1, color)
        XCTAssertEqual(result.create.first, .createCustom("food"))
    }

    func testCreateDialectPreselectsANamedPrefecture() {
        let result = suggest("kumamoto")
        XCTAssertTrue(result.create.contains(.createDialect("kumamoto", preselected: .kumamoto)))
        XCTAssertTrue(suggest("zzz").create.contains(.createDialect("zzz", preselected: nil)))
    }

    // MARK: related (empty field)

    func testRelatedSuggestsNeighbouringDialects() {
        let osaka = DialectTagValue(name: "大阪弁", prefectures: [.osaka], region: .kansai, catalogueID: "osaka-ben")
        let related = suggester.related(to: [], recent: [], allDialectTags: [osaka], allCustomTags: [])
        let names = dialectNames(related)
        for expected in ["河内弁", "京都弁", "神戸弁"] {
            XCTAssertTrue(names.contains(expected), expected)
        }
        XCTAssertFalse(names.contains("大阪弁"), "already a tag")
        // Same prefecture before the rest of the region; nothing from other regions.
        XCTAssertLessThan(names.firstIndex(of: "河内弁")!, names.firstIndex(of: "京都弁")!)
        let regions = Set(related.compactMap { suggestion -> Region? in
            if case .dialect(let record) = suggestion { return record.region }
            return nil
        })
        XCTAssertEqual(regions, [.kansai])
    }

    func testRelatedPutsRecentTagsFirstAndSkipsApplied() {
        let osaka = DialectTagValue(name: "大阪弁", prefectures: [.osaka], region: .kansai, catalogueID: "osaka-ben")
        let food = CustomTagValue(name: "food")
        let slang = CustomTagValue(name: "slang")
        let related = suggester.related(
            to: [osaka], recent: [slang.id, osaka.id, food.id], allDialectTags: [osaka], allCustomTags: [food, slang]
        )
        XCTAssertEqual(Array(related.prefix(2)), [.existingCustom(slang), .existingCustom(food)])
        XCTAssertFalse(related.contains(.existingDialect(osaka)))
    }

    func testRelatedIsEmptyWithNoTags() {
        XCTAssertEqual(suggester.related(to: [], recent: [], allDialectTags: [], allCustomTags: []), [])
    }

    func testRecordFixture() {
        XCTAssertEqual(record("熊本弁").prefectures, [.kumamoto])
    }
}
