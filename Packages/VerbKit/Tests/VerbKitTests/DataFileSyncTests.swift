import XCTest
@testable import VerbKit

/// The shared store flow: save first, confirm only then, and report every outcome.
@MainActor
final class DataFileSyncTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "DataFileSyncTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeStatus() -> DataSyncStatus {
        DataSyncStatus(defaults: defaults)
    }

    func testASuccessfulSaveConfirmsAndReportsTheVersion() async {
        let status = makeStatus()
        var confirmed = false

        let saved = await DataFileSync.run(
            for: .words,
            status: status,
            fetch: { PendingDataFile(version: "2.0.0", payload: 42) { confirmed = true } },
            persist: { XCTAssertEqual($0, 42) }
        )

        XCTAssertEqual(saved, 42)
        XCTAssertTrue(confirmed)
        XCTAssertEqual(status.status(for: .words).version, "2.0.0")
        XCTAssertNotNil(status.status(for: .words).lastUpdated)
        XCTAssertNil(status.status(for: .words).problem)
    }

    func testAFailedSaveDoesNotConfirmAndIsReportedAsCouldNotSave() async {
        let status = makeStatus()
        var confirmed = false

        let saved = await DataFileSync.run(
            for: .words,
            status: status,
            fetch: { PendingDataFile(version: "2.0.0", payload: 42) { confirmed = true } },
            persist: { _ in throw SaveFailed() }
        )

        XCTAssertNil(saved)
        XCTAssertFalse(confirmed)
        XCTAssertEqual(status.status(for: .words).problem, .couldNotSave)
        XCTAssertNil(status.status(for: .words).version)
    }

    func testAFailedFetchIsReportedAndConfirmsNothing() async {
        let status = makeStatus()

        let saved = await DataFileSync.run(
            for: .counters,
            status: status,
            fetch: { () async throws -> PendingDataFile<Int>? in
                throw VerbSyncError.offline
            },
            persist: { _ in XCTFail("nothing to save") }
        )

        XCTAssertNil(saved)
        XCTAssertEqual(status.status(for: .counters).problem, .offline)
        XCTAssertNil(status.status(for: .counters).version)
    }

    func testUpToDateOnlyRecordsTheCheck() async {
        let status = makeStatus()
        let before = Date.now

        let saved = await DataFileSync.run(
            for: .furigana,
            status: status,
            fetch: { () async throws -> PendingDataFile<Int>? in nil },
            persist: { _ in XCTFail("nothing fetched") }
        )

        XCTAssertNil(saved)
        XCTAssertNil(status.status(for: .furigana).version)
        XCTAssertNil(status.status(for: .furigana).problem)
        XCTAssertGreaterThanOrEqual(status.status(for: .furigana).lastChecked ?? .distantPast, before)
    }
}

private struct SaveFailed: Error {}
