import XCTest
@testable import VerbKit

final class KanjiSpellingTests: XCTestCase {
    func testTheSharedOkuriganaSplitsTheStems() throws {
        let taberu = try XCTUnwrap(KanjiSpelling(kanji: "食べる", dict: "たべる"))
        XCTAssertEqual(taberu.kanjiStem, "食")
        XCTAssertEqual(taberu.readingStems, ["た"])
        XCTAssertEqual(taberu.spell("たべさせられる"), "食べさせられる")
        XCTAssertEqual(taberu.spell("たべさせられ"), "食べさせられ")
        XCTAssertNil(taberu.spell("のむ"))

        let hikkosu = try XCTUnwrap(KanjiSpelling(kanji: "引っ越す", dict: "ひっこす"))
        XCTAssertEqual(hikkosu.kanjiStem, "引っ越")
        XCTAssertEqual(hikkosu.spell("ひっこしました"), "引っ越しました")
    }

    func testKuruReadsItsStemThreeWays() throws {
        let kuru = try XCTUnwrap(KanjiSpelling(kanji: "来る", dict: "くる"))
        XCTAssertEqual(kuru.readingStems, ["く", "き", "こ"])
        XCTAssertEqual(kuru.spell("くれば"), "来れば")
        XCTAssertEqual(kuru.spell("きました"), "来ました")
        XCTAssertEqual(kuru.spell("こられる"), "来られる")
        XCTAssertEqual(KanjiSpelling(kanji: "持って来る", dict: "もってくる")?.spell("もってきた"), "持って来た")
    }

    func testAVerbWithoutKanjiHasNoSpelling() {
        XCTAssertNil(KanjiSpelling(kanji: nil, dict: "する"))
        XCTAssertNil(KanjiSpelling(kanji: "ある", dict: "ある"))
    }

    /// The research spelled every form with no failure (4,315 forms of the 61 verbs with a
    /// `kanji`; the other 255 are kana only). This keeps it that way.
    func testEveryRealFormHasAKanjiSpellingWhenItsVerbHasKanji() throws {
        var spelled = 0
        for verb in try RealVerbs.load() {
            guard let spelling = KanjiSpelling(verb) else { continue }
            for (spec, kana) in FormCatalogue.bundled.available(in: Word(verb).forms, for: .verb) {
                XCTAssertNotNil(spelling.spell(kana), "\(verb.id) \(spec.id) \(kana)")
                spelled += 1
            }
        }
        XCTAssertEqual(spelled, 4_315)
    }
}
