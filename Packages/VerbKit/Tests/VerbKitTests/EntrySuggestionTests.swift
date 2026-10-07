import XCTest
@testable import VerbKit

@MainActor
final class EntrySuggestionModelTests: XCTestCase {
    private struct Boom: Error {}

    /// Records what it was asked and answers from `reply`; can be held until `release()`.
    private final class FakeSuggester: EntrySuggesting, @unchecked Sendable {
        var calls: [String] = []
        var reply: (String) throws -> EntrySuggestion = { _ in EntrySuggestion(meanings: ["x"]) }
        var available = true
        var gate: CheckedContinuation<Void, Never>?
        var holding = false

        var isAvailable: Bool { available }

        func suggest(for text: String) async throws -> EntrySuggestion {
            calls.append(text)
            if holding {
                await withCheckedContinuation { gate = $0 }
            }
            return try reply(text)
        }

        func release() { gate?.resume(); gate = nil }
    }

    private func model(_ fake: FakeSuggester?) -> EntrySuggestionModel {
        EntrySuggestionModel(suggester: fake, sleep: { _ in })
    }

    /// Lets the model's task run to completion.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func testNoSuggesterOrAnUnavailableOneMeansUnavailable() async {
        let none = model(nil)
        none.textChanged("おおきに")
        XCTAssertEqual(none.state, .unavailable)

        let fake = FakeSuggester()
        fake.available = false
        let off = model(fake)
        off.textChanged("おおきに")
        XCTAssertEqual(off.state, .unavailable)
        XCTAssertEqual(fake.calls, [])
    }

    func testShortOrBlankTextStaysIdle() async {
        let fake = FakeSuggester()
        let model = model(fake)
        model.textChanged("")
        model.textChanged(" あ ")
        await settle()
        XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(fake.calls, [])
    }

    func testASuggestionArrivesAfterThePause() async {
        let fake = FakeSuggester()
        fake.reply = { _ in EntrySuggestion(standardForms: [StandardEquivalent(written: "ありがとう")], meanings: ["thank you"]) }
        let model = model(fake)
        model.textChanged("おおきに")
        XCTAssertEqual(model.state, .loading)
        await settle()
        XCTAssertEqual(fake.calls, ["おおきに"])
        XCTAssertEqual(model.state, .ready(EntrySuggestion(standardForms: [StandardEquivalent(written: "ありがとう")], meanings: ["thank you"])))
    }

    func testTypingAgainBeforeThePauseEndsAsksOnlyOnce() async {
        let fake = FakeSuggester()
        let model = EntrySuggestionModel(suggester: fake, sleep: { _ in try await Task.sleep(for: .milliseconds(150)) })
        model.textChanged("おお")
        model.textChanged("おおき")
        model.textChanged("おおきに")
        try? await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(fake.calls, ["おおきに"])
    }

    func testAnAnswerForOldTextIsDiscarded() async {
        let fake = FakeSuggester()
        fake.holding = true
        let model = model(fake)
        model.textChanged("おおきに")
        await settle()
        XCTAssertEqual(fake.calls, ["おおきに"])
        model.textChanged("")          // the user cleared the field while the model was thinking
        fake.release()
        await settle()
        XCTAssertEqual(model.state, .idle)
    }

    func testAnEmptyAnswerAndAnErrorAreNotShownAsSuggestions() async {
        let fake = FakeSuggester()
        fake.reply = { _ in EntrySuggestion() }
        let model = model(fake)
        model.textChanged("おおきに")
        await settle()
        XCTAssertEqual(model.state, .nothing)

        fake.reply = { _ in throw Boom() }
        model.textChanged("だんだん")
        await settle()
        XCTAssertEqual(model.state, .failed)
    }

    /// The model said it wasn't sure and had nothing: a state of its own, so the editor can say
    /// so instead of showing a spinner that ends in nothing.
    func testAnUnsureEmptyAnswerIsItsOwnState() async {
        let fake = FakeSuggester()
        fake.reply = { _ in EntrySuggestion(isUnsure: true) }
        let model = model(fake)
        model.textChanged("おおきに")
        await settle()
        XCTAssertEqual(model.state, .unsure)
    }

    /// An unsure answer with content is still shown (dialect words are often unsure), marked
    /// so the editor can label the chips as guesses.
    func testAnUnsureAnswerWithContentIsShownMarked() async {
        let fake = FakeSuggester()
        let guess = EntrySuggestion(meanings: ["thank you"], isUnsure: true)
        fake.reply = { _ in guess }
        let model = model(fake)
        model.textChanged("おおきに")
        await settle()
        XCTAssertEqual(model.state, .ready(guess))
    }

    func testRetryAsksAgainForTheSameText() async {
        let fake = FakeSuggester()
        fake.reply = { _ in throw Boom() }
        let model = model(fake)
        model.textChanged("おおきに")
        await settle()
        XCTAssertEqual(model.state, .failed)
        fake.reply = { _ in EntrySuggestion(meanings: ["thank you"]) }
        model.retry()
        await settle()
        XCTAssertEqual(model.state, .ready(EntrySuggestion(meanings: ["thank you"])))
        XCTAssertEqual(fake.calls, ["おおきに", "おおきに"])
    }

    func testTheSameTextIsNotAskedTwiceInARow() async {
        let fake = FakeSuggester()
        let model = model(fake)
        model.textChanged("おおきに")
        await settle()
        model.textChanged("おおきに ")   // only whitespace differs
        await settle()
        XCTAssertEqual(fake.calls, ["おおきに"])
    }
}

final class EntrySuggestionContentTests: XCTestCase {
    func testEmptiness() {
        XCTAssertTrue(EntrySuggestion(isUnsure: true).isEmpty)
        XCTAssertTrue(EntrySuggestion().isEmpty)
        XCTAssertFalse(EntrySuggestion(reading: "あ").isEmpty)
        XCTAssertFalse(EntrySuggestion(kind: .phrase).isEmpty)
    }

    func testRemovingWhatTheEntryAlreadyHas() {
        let entry = WordBankEntryValue(
            text: "おおきに", reading: "おおきに", kind: .word,
            senses: [Sense(meaning: "Thank you")], equivalents: [StandardEquivalent(written: "ありがとう")],
            dialectTagIDs: []
        )
        let suggestion = EntrySuggestion(
            reading: "おおきに",
            standardForms: [StandardEquivalent(written: "ありがとう"), StandardEquivalent(written: "感謝")],
            meanings: ["thank you", "many thanks"], kind: .word, dialectCatalogueID: "osaka-ben"
        )
        let remaining = suggestion.removing(whatIsIn: entry, appliedDialectCatalogueIDs: [])
        XCTAssertNil(remaining.reading, "the reading is already there")
        XCTAssertEqual(remaining.standardForms.map(\.written), ["感謝"])
        XCTAssertEqual(remaining.meanings, ["many thanks"], "compared without case")
        XCTAssertNil(remaining.kind, "the kind is already word")
        XCTAssertEqual(remaining.dialectCatalogueID, "osaka-ben")

        let tagged = suggestion.removing(whatIsIn: entry, appliedDialectCatalogueIDs: ["osaka-ben"])
        XCTAssertNil(tagged.dialectCatalogueID)

        let unsure = EntrySuggestion(meanings: ["many thanks"], isUnsure: true)
        XCTAssertTrue(unsure.removing(whatIsIn: entry, appliedDialectCatalogueIDs: []).isUnsure, "the guess stays marked")
    }

    func testAReadingThatIsTheTextAgainIsDropped() {
        let entry = WordBankEntryValue(text: "しんどい")
        let rest = EntrySuggestion(reading: "しんどい", meanings: ["tired"]).removing(whatIsIn: entry, appliedDialectCatalogueIDs: [])
        XCTAssertNil(rest.reading)
        XCTAssertEqual(rest.meanings, ["tired"])
        let kanji = EntrySuggestion(reading: "しんどい").removing(whatIsIn: WordBankEntryValue(text: "辛い"), appliedDialectCatalogueIDs: [])
        XCTAssertEqual(kanji.reading, "しんどい")
    }

    func testApplyingFillsOnlyWhatIsAsked() {
        var entry = WordBankEntryValue(text: "おおきに")
        entry.apply(reading: "おおきに")
        entry.apply(standardForm: StandardEquivalent(written: "ありがとう"))
        entry.apply(standardForm: StandardEquivalent(written: "ありがとう"))   // duplicate
        entry.apply(meaning: "thank you")
        entry.apply(meaning: " Thank you ")   // duplicate, ignoring case and spaces
        entry.apply(kind: .phrase)
        XCTAssertEqual(entry.reading, "おおきに")
        XCTAssertEqual(entry.equivalents.map(\.written), ["ありがとう"])
        XCTAssertEqual(entry.senses.map(\.meaning), ["thank you"])
        XCTAssertEqual(entry.kind, .phrase)
        XCTAssertNil(entry.wordClass)
    }

    func testApplyingAReadingDoesNotOverwriteATypedOne() {
        var entry = WordBankEntryValue(text: "大きに", reading: "おおきに")
        entry.apply(reading: "だいきに")
        XCTAssertEqual(entry.reading, "おおきに")
    }
}
