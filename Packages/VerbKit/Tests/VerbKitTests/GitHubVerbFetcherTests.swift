import CryptoKit
import XCTest
@testable import VerbKit

final class GitHubVerbFetcherTests: XCTestCase {
    private let key = Curve25519.Signing.PrivateKey()
    private let root = "https://raw.githubusercontent.com/example/repo/"

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeFetcher(verifier: ManifestSignatureVerifier? = nil) -> GitHubVerbFetcher {
        let root = self.root
        return GitHubVerbFetcher(
            manifestBaseURL: URL(string: root + "main/data/")!,
            dataBaseURL: { ref in URL(string: root + (ref ?? "main") + "/data/")! },
            verifier: verifier ?? ManifestSignatureVerifier(publicKeys: [key.publicKey.rawRepresentation]),
            session: makeSession()
        )
    }

    /// Serves `manifest` with a valid signature, and `files` by URL path suffix (e.g. "main/data/verbs.json").
    private func serve(manifest: String, signWith signer: Curve25519.Signing.PrivateKey? = nil, files: [String: Data] = [:]) throws {
        let manifestData = Data(manifest.utf8)
        let signature = try (signer ?? key).signature(for: manifestData).base64EncodedString() + "\n"
        let prefix = root
        StubURLProtocol.handler = { request in
            let path = String(request.url!.absoluteString.dropFirst(prefix.count))
            if path == "main/data/manifest.json" { return stubOK(request, manifestData) }
            if path == "main/data/manifest.sig" { return stubOK(request, Data(signature.utf8)) }
            if let body = files[path] { return stubOK(request, body) }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - Manifest decoding

    func testFetchManifestDecodesSuccessfulResponse() async throws {
        try serve(manifest: #"{"version": "1.0.0", "sha256": "abc"}"#)
        let manifest = try await makeFetcher().fetchManifest()
        XCTAssertEqual(manifest, VerbManifest(version: "1.0.0", sha256: "abc"))
    }

    func testFetchManifestMapsServerErrorToServerUnreachable() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        do {
            _ = try await makeFetcher().fetchManifest()
            XCTFail("expected serverUnreachable")
        } catch VerbSyncError.serverUnreachable {
            // expected
        }
    }

    func testFetchManifestMapsOfflineURLErrorToOffline() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeFetcher().fetchManifest()
            XCTFail("expected offline")
        } catch VerbSyncError.offline {
            // expected
        }
    }

    func testFetchGrammarManifestReadsTheGrammarBlock() async throws {
        try serve(manifest: #"{"version": "1.1.0", "sha256": "abc", "grammar": {"version": "2.0.0", "sha256": "def"}}"#)
        let grammar = try await makeFetcher().fetchGrammarManifest()
        XCTAssertEqual(grammar, GrammarManifest(version: "2.0.0", sha256: "def"))
    }

    func testFetchGrammarManifestIsNilWithoutAGrammarBlock() async throws {
        try serve(manifest: #"{"version": "1.0.0", "sha256": "abc"}"#)
        let grammar = try await makeFetcher().fetchGrammarManifest()
        XCTAssertNil(grammar)
    }

    /// Builds already installed must keep working once the manifest gains a grammar block.
    func testVerbManifestStillDecodesWhenGrammarBlockIsPresent() async throws {
        try serve(manifest: #"{"version": "1.1.0", "sha256": "abc", "grammar": {"version": "2.0.0", "sha256": "def"}}"#)
        let manifest = try await makeFetcher().fetchManifest()
        XCTAssertEqual(manifest, VerbManifest(version: "1.1.0", sha256: "abc"))
    }

    func testFetchFuriganaManifestReadsTheFuriganaBlock() async throws {
        try serve(manifest: #"{"version": "1.2.0", "sha256": "abc", "grammar": {"version": "1.1.0", "sha256": "g"}, "furigana": {"version": "3.0.0", "sha256": "f"}}"#)
        let fetcher = makeFetcher()
        let furigana = try await fetcher.fetchFuriganaManifest()
        XCTAssertEqual(furigana, FuriganaManifest(version: "3.0.0", sha256: "f"))
        // The other blocks still read as before.
        let grammar = try await fetcher.fetchGrammarManifest()
        XCTAssertEqual(grammar, GrammarManifest(version: "1.1.0", sha256: "g"))
    }

    func testFetchFuriganaManifestIsNilWithoutAFuriganaBlock() async throws {
        try serve(manifest: #"{"version": "1.0.0", "sha256": "abc", "grammar": {"version": "1.0.0", "sha256": "g"}}"#)
        let furigana = try await makeFetcher().fetchFuriganaManifest()
        XCTAssertNil(furigana)
    }

    /// Builds already installed must keep working once the manifest gains a furigana block.
    func testVerbAndGrammarManifestsStillDecodeWhenAFuriganaBlockIsPresent() async throws {
        try serve(manifest: #"{"version": "1.2.0", "sha256": "abc", "grammar": {"version": "1.1.0", "sha256": "g"}, "furigana": {"version": "3.0.0", "sha256": "f"}}"#)
        let manifest = try await makeFetcher().fetchManifest()
        XCTAssertEqual(manifest, VerbManifest(version: "1.2.0", sha256: "abc"))
    }

    func testAMalformedSignedManifestMapsToMalformedData() async throws {
        try serve(manifest: "nope")
        do {
            _ = try await makeFetcher().fetchGrammarManifest()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    // MARK: - Data files

    func testFetchDataRequestsTheRightFile() async throws {
        let empty = #"{"version": "1.0.0", "sha256": "abc"}"#
        try serve(manifest: empty, files: [
            "main/data/verbs.json": Data("verb-bytes".utf8),
            "main/data/grammar.json": Data("grammar-bytes".utf8),
            "main/data/furigana.json": Data("furigana-bytes".utf8),
        ])
        let fetcher = makeFetcher()
        let verbs = try await fetcher.fetchVerbData()
        let grammar = try await fetcher.fetchGrammarData()
        let furigana = try await fetcher.fetchFuriganaData()
        XCTAssertEqual(verbs, Data("verb-bytes".utf8))
        XCTAssertEqual(grammar, Data("grammar-bytes".utf8))
        XCTAssertEqual(furigana, Data("furigana-bytes".utf8))
    }

    func testEachFileIsFetchedFromTheTagItsManifestEntryNames() async throws {
        try serve(
            manifest: #"{"version": "1.0.0", "sha256": "a", "ref": "data-v1", "grammar": {"version": "1.0.0", "sha256": "g", "ref": "data-v2"}, "furigana": {"version": "1.0.0", "sha256": "f"}}"#,
            files: [
                "data-v1/data/verbs.json": Data("verbs-at-v1".utf8),
                "data-v2/data/grammar.json": Data("grammar-at-v2".utf8),
                "main/data/furigana.json": Data("furigana-on-main".utf8),
            ]
        )
        let fetcher = makeFetcher()
        let verbs = try await fetcher.fetchVerbData()
        let grammar = try await fetcher.fetchGrammarData()
        let furigana = try await fetcher.fetchFuriganaData()
        XCTAssertEqual(verbs, Data("verbs-at-v1".utf8))
        XCTAssertEqual(grammar, Data("grammar-at-v2".utf8))
        XCTAssertEqual(furigana, Data("furigana-on-main".utf8))
    }

    func testARefThatCouldChangeTheURLIsRefused() async throws {
        for bad in ["../x", "a/b", "a?b", "a#b", "-x", "", ".hidden", "a b", String(repeating: "a", count: 65)] {
            try serve(manifest: #"{"version": "1.0.0", "sha256": "a", "ref": "\#(bad)"}"#, files: ["main/data/verbs.json": Data("x".utf8)])
            do {
                _ = try await makeFetcher().fetchVerbData()
                XCTFail("expected malformedData for ref '\(bad)'")
            } catch VerbSyncError.malformedData {
                // expected
            }
        }
    }

    func testFetchRejectsAnOversizedResponse() async throws {
        try serve(manifest: #"{"version": "1.0.0", "sha256": "a"}"#, files: [
            "main/data/verbs.json": Data(count: GitHubVerbFetcher.maxResponseBytes + 1),
        ])
        do {
            _ = try await makeFetcher().fetchVerbData()
            XCTFail("expected malformedData")
        } catch VerbSyncError.malformedData {
            // expected
        }
    }

    // MARK: - Signature

    func testAManifestSignedWithAnUnknownKeyIsRefused() async throws {
        try serve(manifest: #"{"version": "9.9.9", "sha256": "evil"}"#, signWith: Curve25519.Signing.PrivateKey())
        do {
            _ = try await makeFetcher().fetchManifest()
            XCTFail("expected untrusted")
        } catch VerbSyncError.untrusted {
            // expected
        }
    }

    func testAManifestChangedAfterSigningIsRefused() async throws {
        let signed = Data(#"{"version": "1.0.0", "sha256": "good"}"#.utf8)
        let signature = try key.signature(for: signed).base64EncodedString()
        let tampered = Data(#"{"version": "1.0.0", "sha256": "evil"}"#.utf8)
        let prefix = root
        StubURLProtocol.handler = { request in
            let path = String(request.url!.absoluteString.dropFirst(prefix.count))
            return stubOK(request, path.hasSuffix("manifest.sig") ? Data(signature.utf8) : tampered)
        }
        do {
            _ = try await makeFetcher().fetchManifest()
            XCTFail("expected untrusted")
        } catch VerbSyncError.untrusted {
            // expected
        }
    }

    func testAMissingSignatureIsRefused() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.lastPathComponent == "manifest.sig" {
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
            }
            return stubOK(request, Data(#"{"version": "1.0.0", "sha256": "abc"}"#.utf8))
        }
        do {
            _ = try await makeFetcher().fetchManifest()
            XCTFail("expected a failure")
        } catch VerbSyncError.untrusted {
            // expected: the server answered, there is just no signature to trust
        }
    }

    func testAnUnreachableSignatureIsStillUnreachable() async throws {
        StubURLProtocol.handler = { request in
            if request.url!.lastPathComponent == "manifest.sig" {
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
            return stubOK(request, Data(#"{"version": "1.0.0", "sha256": "abc"}"#.utf8))
        }
        do {
            _ = try await makeFetcher().fetchManifest()
            XCTFail("expected a failure")
        } catch VerbSyncError.serverUnreachable {
            // expected: a server error is not a verdict on the data
        }
    }

    func testAGarbageSignatureIsRefused() async throws {
        StubURLProtocol.handler = { request in
            stubOK(request, request.url!.lastPathComponent == "manifest.sig" ? Data("not base64 !!".utf8) : Data(#"{"version": "1.0.0", "sha256": "abc"}"#.utf8))
        }
        do {
            _ = try await makeFetcher().fetchManifest()
            XCTFail("expected untrusted")
        } catch VerbSyncError.untrusted {
            // expected
        }
    }

    func testWithNoKeyConfiguredNothingIsTrusted() async throws {
        try serve(manifest: #"{"version": "1.0.0", "sha256": "abc"}"#)
        do {
            _ = try await makeFetcher(verifier: ManifestSignatureVerifier(publicKeys: [])).fetchManifest()
            XCTFail("expected untrusted")
        } catch VerbSyncError.untrusted {
            // expected
        }
    }
}

private func stubOK(_ request: URLRequest, _ body: Data) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
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
