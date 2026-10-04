import XCTest
import SwiftData
@testable import VerbKit

@MainActor
final class VerbModelContainerTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func sampleVerb() throws -> Verb {
        try XCTUnwrap(try RealVerbs.load().first)
    }

    func testInMemoryHoldsVerbsAndWordBankInOneContext() throws {
        let context = ModelContext(try VerbModelContainer.makeInMemory())
        context.insert(VerbEntity(try sampleVerb()))
        context.insert(WordBankEntryEntity(WordBankEntryValue(text: "おおきに")))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<VerbEntity>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WordBankEntryEntity>()), 1)
    }

    func testVerbSyncRewriteLeavesWordBankRowsAlone() throws {
        let context = ModelContext(try VerbModelContainer.makeInMemory())
        let bank = SwiftDataWordBankPersisting(modelContext: context)
        let entry = WordBankEntryValue(text: "おおきに", createdAt: Date(timeIntervalSince1970: 1))
        try bank.upsert(entry: entry)

        let verbs = SwiftDataVerbPersisting(modelContext: context)
        try verbs.replaceAllVerbs(with: try RealVerbs.load())
        try verbs.replaceAllVerbs(with: [])

        XCTAssertEqual(try bank.load().entries, [entry])
    }

    func testTheTwoConfigurationsWriteTwoFiles() throws {
        let context = ModelContext(try VerbModelContainer.make(directory: directory))
        context.insert(VerbEntity(try sampleVerb()))
        context.insert(WordBankEntryEntity(WordBankEntryValue(text: "おおきに")))
        try context.save()

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains("VerbKit.sqlite"), "\(names)")
        XCTAssertTrue(names.contains("WordBank.sqlite"), "\(names)")
    }

    /// An existing install's store (one unnamed configuration, the four original
    /// models) opens through the new two-file container with its rows intact.
    func testAnExistingStoreKeepsItsDataInTheNewContainer() throws {
        let verb = try sampleVerb()
        do {
            let schema = Schema([VerbEntity.self, GrammarEntity.self, FuriganaEntity.self, QuizAttemptEntity.self])
            let old = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("VerbKit.sqlite"))
            let context = ModelContext(try ModelContainer(for: schema, configurations: [old]))
            context.insert(VerbEntity(verb))
            context.insert(QuizAttemptEntity(QuizAttempt(verb: verb.dict, formID: "te", kind: .conjugate, outcome: .correct, date: Date())))
            try context.save()
        }

        let context = ModelContext(try VerbModelContainer.make(directory: directory))
        XCTAssertEqual(try context.fetch(FetchDescriptor<VerbEntity>()).map(\.dict), [verb.dict])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuizAttemptEntity>()), 1)
        context.insert(WordBankEntryEntity(WordBankEntryValue(text: "おおきに")))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WordBankEntryEntity>()), 1)
    }
}
