import XCTest
@testable import VerbKit

final class QuizLinkTests: XCTestCase {
    func testEveryTopicRoundTrips() {
        for topic in QuizTopic.allCases {
            XCTAssertEqual(QuizLink(url: QuizLink(topic: topic).url), QuizLink(topic: topic))
        }
        XCTAssertEqual(QuizLink(url: QuizLink().url), QuizLink())
    }

    func testURLShape() {
        XCTAssertEqual(QuizLink().url.absoluteString, "verbtable://quiz")
        XCTAssertEqual(QuizLink(topic: .potential).url.absoluteString, "verbtable://quiz/potential")
    }

    func testRejectsOtherLinks() throws {
        XCTAssertNil(QuizLink(url: Route.verb("たべる").url))
        XCTAssertNil(QuizLink(url: try XCTUnwrap(URL(string: "verbtable://quiz/nonsense"))))
        XCTAssertNil(QuizLink(url: try XCTUnwrap(URL(string: "https://quiz/basic"))))
    }

    func testRouteIgnoresQuizLinks() {
        XCTAssertNil(Route(url: QuizLink().url))
    }
}
