import XCTest
@testable import VerbKit

@MainActor
final class DataSyncStatusTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "DataSyncStatusTests"
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        clock = Date(timeIntervalSince1970: 1_000_000)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeStatus() -> DataSyncStatus {
        DataSyncStatus(defaults: defaults, now: { [unowned self] in self.clock })
    }

    func testEveryFileStartsWithNoData() {
        let status = makeStatus()
        for file in DataFile.allCases {
            XCTAssertEqual(status.status(for: file), DataFileStatus(file: file))
            XCTAssertFalse(status.status(for: file).hasData)
        }
    }

    func testAnUpdateRecordsVersionAndDates() {
        let status = makeStatus()
        status.recordUpdated(.verbs, version: "1.2.0")

        let verbs = status.status(for: .verbs)
        XCTAssertEqual(verbs.version, "1.2.0")
        XCTAssertEqual(verbs.lastUpdated, clock)
        XCTAssertEqual(verbs.lastChecked, clock)
        XCTAssertNil(verbs.problem)
        XCTAssertNil(status.status(for: .grammar).version)
    }

    func testASameVersionRedownloadKeepsTheLastUpdatedDate() {
        let status = makeStatus()
        status.recordUpdated(.verbs, version: "1.2.0")
        let first = clock
        clock += 3600
        status.recordUpdated(.verbs, version: "1.2.0")

        XCTAssertEqual(status.status(for: .verbs).lastUpdated, first)
        XCTAssertEqual(status.status(for: .verbs).lastChecked, clock)

        clock += 3600
        status.recordUpdated(.verbs, version: "1.3.0")
        XCTAssertEqual(status.status(for: .verbs).lastUpdated, clock)
    }

    func testUpToDateOnlyMovesLastChecked() {
        let status = makeStatus()
        status.recordUpdated(.grammar, version: "2.0.0")
        let updated = clock
        clock += 60
        status.recordUpToDate(.grammar)

        let grammar = status.status(for: .grammar)
        XCTAssertEqual(grammar.version, "2.0.0")
        XCTAssertEqual(grammar.lastUpdated, updated)
        XCTAssertEqual(grammar.lastChecked, clock)
    }

    func testLastCheckedIsTheMostRecentOfAnyFile() {
        let status = makeStatus()
        XCTAssertNil(status.lastChecked)
        status.recordUpToDate(.verbs)
        clock += 60
        status.recordUpToDate(.counters)
        XCTAssertEqual(status.lastChecked, clock)
    }

    func testVersionAndDatesSurviveARelaunch() {
        makeStatus().recordUpdated(.furigana, version: "1.0.1")

        let relaunched = makeStatus().status(for: .furigana)
        XCTAssertEqual(relaunched.version, "1.0.1")
        XCTAssertEqual(relaunched.lastUpdated, clock)
        XCTAssertEqual(relaunched.lastChecked, clock)
    }

    func testAFailureKeepsTheDataAndIsNotPersisted() {
        let status = makeStatus()
        status.recordUpdated(.verbs, version: "1.2.0")
        clock += 60
        status.recordFailure(.verbs, VerbSyncError.offline)

        let verbs = status.status(for: .verbs)
        XCTAssertEqual(verbs.problem, .offline)
        XCTAssertEqual(verbs.version, "1.2.0")
        XCTAssertEqual(verbs.lastChecked, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertNil(makeStatus().status(for: .verbs).problem)
    }

    func testASuccessfulCheckClearsTheProblem() {
        let status = makeStatus()
        status.recordFailure(.counters, VerbSyncError.serverUnreachable)
        status.recordUpToDate(.counters)
        XCTAssertNil(status.status(for: .counters).problem)
    }

    func testErrorsMapToProblems() {
        XCTAssertEqual(DataSyncProblem(syncError: VerbSyncError.offline), .offline)
        XCTAssertEqual(DataSyncProblem(syncError: VerbSyncError.serverUnreachable), .serverUnreachable)
        XCTAssertEqual(DataSyncProblem(syncError: VerbSyncError.malformedData), .damaged)
        XCTAssertEqual(DataSyncProblem(syncError: VerbSyncError.untrusted), .untrusted)
        XCTAssertEqual(DataSyncProblem(syncError: CancellationError()), .serverUnreachable)

        let status = makeStatus()
        status.recordFailure(.words, VerbSyncError.malformedData, whileSaving: true)
        XCTAssertEqual(status.status(for: .words).problem, .couldNotSave)
    }

    func testProblemMessagesSayWhetherCurrentDataIsStillInUse() {
        var withData = DataFileStatus(file: .verbs, version: "1.0.0")
        withData.problem = .untrusted
        XCTAssertEqual(
            withData.problemMessage,
            "The download couldn't be verified, so it wasn't used. The data on this device is still in use."
        )

        var withoutData = DataFileStatus(file: .grammar)
        withoutData.problem = .offline
        XCTAssertEqual(withoutData.problemMessage, "You're offline. Try again later.")

        XCTAssertNil(DataFileStatus(file: .verbs, version: "1.0.0").problemMessage)
    }

    func testRefreshRunsTheHandlerAndReportsProgress() async {
        let status = makeStatus()
        var seenRefreshing: Bool?
        var runs = 0
        status.refreshHandler = { [unowned status] in
            runs += 1
            seenRefreshing = status.isRefreshing
        }

        await status.refresh()

        XCTAssertEqual(runs, 1)
        XCTAssertEqual(seenRefreshing, true)
        XCTAssertFalse(status.isRefreshing)
    }

    func testRefreshWhileRefreshingDoesNothing() async {
        let status = makeStatus()
        var runs = 0
        status.refreshHandler = { [unowned status] in
            runs += 1
            // A second tap while the first refresh is still running.
            await status.refresh()
        }

        await status.refresh()

        XCTAssertEqual(runs, 1)
        XCTAssertFalse(status.isRefreshing)
    }

    func testRefreshWithoutAHandlerIsANoOp() async {
        let status = makeStatus()
        await status.refresh()
        XCTAssertFalse(status.isRefreshing)
    }
}
