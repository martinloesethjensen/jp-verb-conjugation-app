import XCTest
@testable import VerbKit

final class ThemePersonalityTests: XCTestCase {
    private func endPoints(_ elements: [SVGPathElement]) -> [SVGPoint] {
        elements.compactMap { element in
            switch element {
            case let .move(p), let .line(p): return p
            case let .quad(p, _): return p
            case let .cubic(p, _, _): return p
            case .close: return nil
            }
        }
    }

    func testEveryMotifParsesAndStaysInItsBox() {
        for motif in TitleMotif.allCases {
            XCTAssertFalse(motif.strokes.isEmpty, "\(motif)")
            for stroke in motif.strokes {
                let elements = SVGPathData.parse(stroke.d)
                XCTAssertFalse(elements.isEmpty, "\(motif): \(stroke.d)")
                for p in endPoints(elements) {
                    XCTAssertTrue((0...64).contains(p.x) && (0...40).contains(p.y), "\(motif): \(p)")
                }
                XCTAssertGreaterThan(stroke.width, 0)
            }
        }
    }

    func testBubblesAndSprinklesUseTheBoardsFixedColours() {
        XCTAssertEqual(TitleMotif.bubbles.strokes.map(\.color), [.fixed(0x7CD4FD), .fixed(0xFDCA3E), .fixed(0xF87166)])
        XCTAssertEqual(Set(TitleMotif.sprinkles.strokes.map(\.color)), [.fixed(0xE07AA0), .fixed(0x4FB393), .fixed(0xE0A92E)])
        XCTAssertEqual(TitleMotif.aurora.strokes.map(\.color), [.first, .second, .third])
        XCTAssertEqual(TitleMotif.rake.strokes.count, 3)
        XCTAssertEqual(TitleMotif.steam.strokes.count, 3)
    }

    func testIconNames() {
        XCTAssertNil(AppIconMatching.iconName(for: .light))
        XCTAssertEqual(AppIconMatching.iconName(for: .latte), "AppIcon-latte")
        XCTAssertEqual(Set(ThemeID.allCases.compactMap(AppIconMatching.iconName)).count, 9)
    }

    func testTappingAThemeChangesTheIconOnlyWhenMatching() {
        XCTAssertEqual(AppIconMatching.change(tapped: .matcha, matches: true, current: nil), IconChange(name: "AppIcon-matcha"))
        XCTAssertNil(AppIconMatching.change(tapped: .matcha, matches: false, current: nil))
        XCTAssertEqual(AppIconMatching.change(tapped: .light, matches: true, current: "AppIcon-matcha"), IconChange(name: nil))
    }

    func testNoChangeWhenTheIconAlreadyMatches() {
        XCTAssertNil(AppIconMatching.change(tapped: .matcha, matches: true, current: "AppIcon-matcha"))
        XCTAssertNil(AppIconMatching.change(switchedOn: false, chosen: .matcha, current: nil))
    }

    func testSwitchingOnAppliesTheChosenThemeAndOffRestoresThePrimary() {
        XCTAssertEqual(AppIconMatching.change(switchedOn: true, chosen: .sand, current: nil), IconChange(name: "AppIcon-sand"))
        XCTAssertEqual(AppIconMatching.change(switchedOn: false, chosen: .sand, current: "AppIcon-sand"), IconChange(name: nil))
    }

    func testSeasonalOverrideNeverPicksTheIcon() {
        // The rule only ever sees the theme someone tapped, never ThemeChoice.effectiveTheme.
        let october = ThemeChoice(theme: .light, appearance: .automatic, seasonal: true)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!
        XCTAssertEqual(october.effectiveTheme(on: date), .halloween)
        XCTAssertNil(AppIconMatching.change(switchedOn: true, chosen: october.theme, current: nil))
        XCTAssertNil(AppIconMatching.change(tapped: october.theme, matches: true, current: nil))
    }
}
