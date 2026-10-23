import XCTest
@testable import VerbKit

/// Guards the real `data/counters.json` the app fetches.
final class RealCountersDataTests: XCTestCase {
    private var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    private func load() throws -> CountersDataFile {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("data/counters.json"))
        return try JSONDecoder().decode(CountersDataFile.self, from: data)
    }

    private func counter(_ id: String, in file: CountersDataFile) throws -> Counter {
        try XCTUnwrap(file.counters.first { $0.id == id }, id)
    }

    func testEveryCounterHasAllElevenReadings() throws {
        for counter in try load().counters {
            for number in CounterNumber.allCases {
                XCTAssertFalse(counter.readings(for: number).isEmpty, "\(counter.id) \(number.key)")
                XCTAssertFalse(counter.readings(for: number).contains(""), "\(counter.id) \(number.key)")
            }
        }
    }

    func testIdsAreUniqueAndRelatedResolve() throws {
        let file = try load()
        let ids = file.counters.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.count, 28)
        for counter in file.counters {
            for related in counter.related { XCTAssertTrue(ids.contains(related), "\(counter.id) → \(related)") }
        }
    }

    func testChangedKeysAreValid() throws {
        let keys = Set(CounterNumber.allCases.map(\.key))
        for counter in try load().counters {
            XCTAssertTrue(Set(counter.changed).isSubset(of: keys), counter.id)
        }
    }

    func testDistractorsAreWrongReadingsNeverAcceptedOnes() throws {
        let file = try load()
        XCTAssertEqual(try counter("hon", in: file).distractors(for: .n(3)), ["さんほん", "さんぽん", "さっぽん"])
        for counter in file.counters {
            for number in CounterNumber.allCases {
                let wrong = counter.distractors(for: number)
                XCTAssertLessThanOrEqual(wrong.count, 3, "\(counter.id) \(number.key)")
                XCTAssertTrue(Set(wrong).isDisjoint(with: counter.readings(for: number)), "\(counter.id) \(number.key)")
            }
        }
    }

    func testKnownReadings() throws {
        let file = try load()
        XCTAssertEqual(try counter("hon", in: file).readings(for: .n(3)).first, "さんぼん")
        XCTAssertEqual(try counter("nin", in: file).readings(for: .n(1)).first, "ひとり")
        XCTAssertEqual(try counter("ji", in: file).readings(for: .n(4)).first, "よじ")
        XCTAssertEqual(try counter("nichi-date", in: file).readings(for: .n(1)).first, "ついたち")
        XCTAssertEqual(try counter("nichi-days", in: file).readings(for: .n(1)).first, "いちにち")
    }

    func testGroupsAreUniqueResolveAndCoverEveryCounter() throws {
        let file = try load()
        let ids = Set(file.counters.map(\.id))
        let groupIDs = file.groups.map(\.id)
        XCTAssertEqual(Set(groupIDs).count, groupIDs.count)
        XCTAssertEqual(groupIDs.count, 17)
        var grouped = Set<String>()
        for group in file.groups {
            for member in group.members {
                XCTAssertTrue(ids.contains(member.counter), "\(group.id) → \(member.counter)")
                grouped.insert(member.counter)
            }
        }
        XCTAssertEqual(grouped, ids)
    }

    func testTheHomeSectionsCoverEveryCounterInTheChosenOrder() throws {
        let file = try load()
        let home = homeSections(file.sections, counters: file.counters)
        XCTAssertEqual(home.map(\.id), [
            "drinks", "people-animals", "things", "clothes-shoes", "how-long", "time-dates-age",
            "when-or-how-long", "money-events",
        ])
        XCTAssertEqual(home.map(\.rows.count), [3, 4, 6, 2, 5, 6, 6, 4])
        XCTAssertEqual(Set(home.flatMap(\.rows).map(\.counter.id)), Set(file.counters.map(\.id)))
    }

    func testTheNewCountersReadAsTheSpecSays() throws {
        let file = try load()
        func preferred(_ id: String, _ number: CounterNumber) throws -> String? {
            try counter(id, in: file).readings(for: number).first
        }
        XCTAssertEqual(try preferred("jikan", .n(4)), "よじかん")
        XCTAssertEqual(try preferred("jikan", .n(7)), "ななじかん")
        XCTAssertEqual(try preferred("jikan", .n(9)), "くじかん")
        XCTAssertEqual(try preferred("shuukan", .n(8)), "はっしゅうかん")
        XCTAssertEqual(try preferred("kagetsu", .n(6)), "ろっかげつ")
        XCTAssertEqual(try preferred("nenkan", .n(4)), "よねんかん")
        XCTAssertEqual(try preferred("nichikan", .n(2)), "ふつかかん")
        XCTAssertEqual(try preferred("soku", .n(3)), "さんぞく")
        XCTAssertEqual(try preferred("soku", .what), "なんぞく")
        XCTAssertEqual(try preferred("chaku", .n(8)), "はっちゃく")
        XCTAssertEqual(try preferred("wa", .n(3)), "さんば")
        XCTAssertEqual(try preferred("wa", .n(6)), "ろっぱ")
        XCTAssertEqual(try preferred("tou", .n(3)), "さんとう")
        XCTAssertEqual(try preferred("ban", .what), "なんばん")
        XCTAssertEqual(try counter("wa", in: file).things.first { $0.word == "うさぎ" }?.fit, .primary)
        for id in ["jikan", "shuukan", "kagetsu", "nenkan", "nichikan", "ban"] {
            XCTAssertFalse(try counter(id, in: file).countsObjects, id)
        }
    }

    func testEveryCounterButTsuHasAWhatQuestionAndAskItBuildsThemAll() throws {
        let file = try load()
        XCTAssertEqual(file.counters.filter { $0.askings.isEmpty }.map(\.id), ["tsu"])
        let questions = buildCounterQuestions(
            counters: file.counters, groups: file.groups, kind: .counterAsk, count: 1000
        )
        XCTAssertEqual(questions.count, file.counters.reduce(0) { $0 + $1.askings.count })
        for question in questions {
            XCTAssertTrue(question.correct.hasPrefix("何"), question.prompt)
            XCTAssertTrue(question.choices.contains(question.correct), question.prompt)
            XCTAssertEqual(Set(question.choices).count, question.choices.count, question.prompt)
            XCTAssertGreaterThanOrEqual(question.choices.count, 3, question.prompt)
        }
    }

    /// The pipeline checks counted runs in Python; this checks the app's own matcher on the same text,
    /// so a run the dictionary would split (三時 + 間, 三 + か + 月) cannot get the wrong ruby on screen.
    func testEveryCountedRunInTheExamplesReadsAsItsCounterSaysInTheApp() throws {
        let file = try load()
        let furiganaFile = try JSONDecoder().decode(
            FuriganaDataFile.self, from: Data(contentsOf: repoRoot.appendingPathComponent("data/furigana.json"))
        )
        let dictionary = FuriganaDictionary(file: furiganaFile)
        let numerals = Set("一二三四五六七八九十百千万")
        var checked = 0
        for counter in file.counters {
            for example in counter.examples + counter.pitfalls.flatMap(\.examples) {
                let sentence = Array(example.jp)
                let reading = dictionary.merging(example.readings).reading(of: example.jp)
                for number in CounterNumber.allCases {
                    let run = Array(counter.written(number))
                    var start = 0
                    while start + run.count <= sentence.count {
                        defer { start += 1 }
                        guard Array(sentence[start..<(start + run.count)]) == run else { continue }
                        if start > 0, numerals.contains(sentence[start - 1]) { continue }
                        let next = start + run.count
                        if next < sentence.count, sentence[next] == "間", !counter.counter.hasSuffix("間") { continue }
                        let accepted = counter.readings(for: number)
                        XCTAssertTrue(
                            accepted.contains { reading.contains($0) },
                            "\(counter.id) \(String(run)) in \(example.jp) reads \(reading), expected \(accepted)"
                        )
                        checked += 1
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 80)
    }
}
