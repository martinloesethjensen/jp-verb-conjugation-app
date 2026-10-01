import XCTest
@testable import VerbKit

final class RealRomajiSearchTests: XCTestCase {
    /// Dictionary form and polite form of each of the 25 verbs in data/verbs.json, in romaji.
    private let romaji: [String: (dict: String, polite: String)] = [
        "する": ("suru", "shimasu"), "くる": ("kuru", "kimasu"), "たべる": ("taberu", "tabemasu"),
        "みる": ("miru", "mimasu"), "ねる": ("neru", "nemasu"), "おきる": ("okiru", "okimasu"),
        "みせる": ("miseru", "misemasu"), "かりる": ("kariru", "karimasu"), "かう": ("kau", "kaimasu"),
        "あう": ("au", "aimasu"), "まつ": ("matsu", "machimasu"), "とる": ("toru", "torimasu"),
        "ある": ("aru", "arimasu"), "もつ": ("motsu", "mochimasu"), "よむ": ("yomu", "yomimasu"),
        "のむ": ("nomu", "nomimasu"), "あそぶ": ("asobu", "asobimasu"), "しぬ": ("shinu", "shinimasu"),
        "かく": ("kaku", "kakimasu"), "きく": ("kiku", "kikimasu"), "いく": ("iku", "ikimasu"),
        "いそぐ": ("isogu", "isogimasu"), "およぐ": ("oyogu", "oyogimasu"),
        "はなす": ("hanasu", "hanashimasu"), "かえす": ("kaesu", "kaeshimasu"),
    ]

    func testEveryRealVerbIsFoundByRomaji() throws {
        let verbs = try RealVerbs.load()
        XCTAssertEqual(verbs.count, romaji.count)
        for verb in verbs {
            let spelling = try XCTUnwrap(romaji[verb.dict], "no romaji for \(verb.dict)")
            XCTAssertTrue(matchesSearch(verb, query: spelling.dict), "\(spelling.dict) should find \(verb.dict)")
            XCTAssertTrue(matchesSearch(verb, query: spelling.polite), "\(spelling.polite) should find \(verb.dict)")
        }
    }
}
