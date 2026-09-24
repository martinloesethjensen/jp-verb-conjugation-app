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
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, session: makeSession())

        let manifest = try await fetcher.fetchManifest()
        XCTAssertEqual(manifest, VerbManifest(version: "1.0.0", sha256: "abc"))
    }

    func testFetchManifestMapsServerErrorToServerUnreachable() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, session: makeSession())

        do {
            _ = try await fetcher.fetchManifest()
            XCTFail("expected serverUnreachable")
        } catch VerbSyncError.serverUnreachable {
            // expected
        }
    }

    func testFetchManifestMapsOfflineURLErrorToOffline() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let fetcher = GitHubVerbFetcher(manifestURL: manifestURL, verbsURL: verbsURL, session: makeSession())

        do {
            _ = try await fetcher.fetchManifest()
            XCTFail("expected offline")
        } catch VerbSyncError.offline {
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
