import XCTest
@testable import VerbKit

final class GitHubVerbFetcherTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private let manifestURL = URL(string: "https://raw.githubusercontent.com/example/repo/main/data/manifest.json")!
    private let verbsURL = URL(string: "https://raw.githubusercontent.com/example/repo/main/data/verbs.json")!
    private let grammarURL = URL(string: "https://raw.githubusercontent.com/example/repo/main/data/grammar.json")!

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchManifestDecodesSuccessfulResponse() async throws {
        let json = Data(#"{"version": "1.0.0", "sha256": "abc"}"#.utf8)
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())

        let manifest = try await fetcher.fetchManifest()
        XCTAssertEqual(manifest, VerbManifest(version: "1.0.0", sha256: "abc"))
    }

    func testFetchManifestMapsServerErrorToServerUnreachable() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())

        do {
            _ = try await fetcher.fetchManifest()
            XCTFail("expected serverUnreachable")
        } catch VerbSyncError.serverUnreachable {
            // expected
        }
    }

    func testFetchManifestMapsOfflineURLErrorToOffline() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())

        do {
            _ = try await fetcher.fetchManifest()
            XCTFail("expected offline")
        } catch VerbSyncError.offline {
            // expected
        }
    }

    func testFetchGrammarManifestReadsTheGrammarBlock() async throws {
        let json = Data(#"{"version": "1.1.0", "sha256": "abc", "grammar": {"version": "2.0.0", "sha256": "def"}}"#.utf8)
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())

        let grammar = try await fetcher.fetchGrammarManifest()
        XCTAssertEqual(grammar, GrammarManifest(version: "2.0.0", sha256: "def"))
    }

    func testFetchGrammarManifestIsNilWithoutAGrammarBlock() async throws {
        let json = Data(#"{"version": "1.0.0", "sha256": "abc"}"#.utf8)
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())

        let grammar = try await fetcher.fetchGrammarManifest()
        XCTAssertNil(grammar)
    }

    /// Builds already installed must keep working once the manifest gains a grammar block.
    func testVerbManifestStillDecodesWhenGrammarBlockIsPresent() async throws {
        let json = Data(#"{"version": "1.1.0", "sha256": "abc", "grammar": {"version": "2.0.0", "sha256": "def"}}"#.utf8)
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())

        let manifest = try await fetcher.fetchManifest()
        XCTAssertEqual(manifest, VerbManifest(version: "1.1.0", sha256: "abc"))
    }

    func testFetchGrammarDataRequestsTheGrammarURL() async throws {
        let body = Data("grammar-bytes".utf8)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.lastPathComponent, "grammar.json")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())

        let data = try await fetcher.fetchGrammarData()
        XCTAssertEqual(data, body)
    }

    func testFetchGrammarManifestMapsMalformedManifestToMalformedData() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("nope".utf8))
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, grammarURL: grammarURL, session: makeSession())

        do {
            _ = try await fetcher.fetchGrammarManifest()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
