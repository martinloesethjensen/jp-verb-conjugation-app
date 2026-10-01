import XCTest
@testable import VerbKit

final class IssueReportURLTests: XCTestCase {
    private func items(_ url: URL) throws -> [String: String] {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testPointsAtTheReportFormOfTheRepository() throws {
        let url = IssueReportURL.report(item: "Verb: たべる (食べる)", versions: "v")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/martinloesethjensen/jp-verb-conjugation-app/issues/new")
        let q = try items(url)
        XCTAssertEqual(q["template"], "report-issue.yml")
        XCTAssertEqual(q["labels"], "report")
    }

    func testItemAndTitleAreFilled() throws {
        let q = try items(IssueReportURL.report(item: "Verb: たべる (食べる)", versions: "v"))
        XCTAssertEqual(q["item"], "Verb: たべる (食べる)")
        XCTAssertEqual(q["title"], "[REPORT] Verb: たべる (食べる)")
    }

    func testBlankItemLeavesTheFieldOutAndTheTitleBare() throws {
        for blank in ["", "   ", "\n"] {
            let q = try items(IssueReportURL.report(item: blank, versions: "v"))
            XCTAssertNil(q["item"])
            XCTAssertEqual(q["title"], "[REPORT]")
        }
    }

    func testCharactersThatCouldSplitTheQueryAreEscaped() throws {
        let nasty = "a&b=c#d?e%f g+h/i"
        let url = IssueReportURL.report(item: nasty, versions: nasty)
        let q = try items(url)
        XCTAssertEqual(q["item"], nasty)
        XCTAssertEqual(q["versions"], nasty)
        XCTAssertEqual(url.fragment, nil)
        XCTAssertEqual(Set(q.keys), ["template", "labels", "title", "item", "versions"])
    }

    func testVersionsLine() {
        XCTAssertEqual(
            IssueReportURL.versions(app: "0.1.0 (1)", verbs: "1.3.0", grammar: "1.3.0", furigana: "1.2.0"),
            "app 0.1.0 (1) · verbs 1.3.0 · grammar 1.3.0 · furigana 1.2.0"
        )
        XCTAssertEqual(
            IssueReportURL.versions(app: "0.1.0 (1)", verbs: nil, grammar: "1.3.0", furigana: nil),
            "app 0.1.0 (1) · verbs unknown · grammar 1.3.0 · furigana unknown"
        )
    }
}
