import Foundation

/// Fetches the published data files and refuses anything that is not signed.
///
/// `manifest.json` is fetched together with `manifest.sig`, an Ed25519 signature over
/// the manifest's exact bytes, and verified against `verifier` before a single field is
/// read. Each file's hash in the manifest is then what the data must match, so the
/// signature covers the data too.
///
/// A manifest entry may carry a `ref` (a release tag); that file is then fetched from
/// that tag instead of `main`, so a later push to `main` cannot change what the
/// signed manifest points at.
public struct GitHubVerbFetcher: VerbDataFetching {
    private let manifestBaseURL: URL
    private let dataBaseURL: @Sendable (String?) -> URL
    private let verifier: ManifestSignatureVerifier
    private let session: URLSession

    /// - Parameters:
    ///   - manifestBaseURL: folder holding `manifest.json` and `manifest.sig`.
    ///   - dataBaseURL: folder holding the data files for a (validated) ref; `nil` means the default branch.
    public init(
        manifestBaseURL: URL,
        dataBaseURL: @escaping @Sendable (String?) -> URL,
        verifier: ManifestSignatureVerifier,
        session: URLSession = .shared
    ) {
        self.manifestBaseURL = manifestBaseURL
        self.dataBaseURL = dataBaseURL
        self.verifier = verifier
        self.session = session
    }

    public func fetchManifest() async throws -> VerbManifest {
        let (data, _) = try await fetchVerifiedManifest()
        do {
            return try JSONDecoder().decode(VerbManifest.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }
    }

    public func fetchVerbData() async throws -> Data {
        let (_, file) = try await fetchVerifiedManifest()
        return try await fetchData(named: "verbs.json", ref: file.ref)
    }

    public func fetchGrammarManifest() async throws -> GrammarManifest? {
        try await fetchVerifiedManifest().file.grammar
    }

    public func fetchGrammarData() async throws -> Data {
        let (_, file) = try await fetchVerifiedManifest()
        return try await fetchData(named: "grammar.json", ref: file.grammarRef)
    }

    public func fetchFuriganaManifest() async throws -> FuriganaManifest? {
        try await fetchVerifiedManifest().file.furigana
    }

    public func fetchFuriganaData() async throws -> Data {
        let (_, file) = try await fetchVerifiedManifest()
        return try await fetchData(named: "furigana.json", ref: file.furiganaRef)
    }

    /// The parts of `manifest.json` beyond the verbs entry. Each entry's `ref` is read
    /// separately from its `GrammarManifest`/`FuriganaManifest`, which stay version + hash only.
    private struct ManifestFile: Decodable {
        struct RefOnly: Decodable { let ref: String? }
        let ref: String?
        let grammar: GrammarManifest?
        let furigana: FuriganaManifest?
        private let grammarEntry: RefOnly?
        private let furiganaEntry: RefOnly?

        var grammarRef: String? { grammarEntry?.ref }
        var furiganaRef: String? { furiganaEntry?.ref }

        private enum CodingKeys: String, CodingKey {
            case ref, grammar, furigana
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ref = try c.decodeIfPresent(String.self, forKey: .ref)
            grammar = try c.decodeIfPresent(GrammarManifest.self, forKey: .grammar)
            furigana = try c.decodeIfPresent(FuriganaManifest.self, forKey: .furigana)
            grammarEntry = try c.decodeIfPresent(RefOnly.self, forKey: .grammar)
            furiganaEntry = try c.decodeIfPresent(RefOnly.self, forKey: .furigana)
        }
    }

    /// The manifest bytes and their decoded refs/entries, only if the signature checks out.
    private func fetchVerifiedManifest() async throws -> (data: Data, file: ManifestFile) {
        let manifestData = try await fetchData(from: manifestBaseURL.appendingPathComponent("manifest.json"))
        // A missing signature (404) is an answer about the data, not a network problem.
        let signatureData = try await fetchData(
            from: manifestBaseURL.appendingPathComponent("manifest.sig"), notFound: .untrusted
        )
        guard let text = String(data: signatureData, encoding: .utf8),
              let signature = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              verifier.isValid(signature: signature, for: manifestData)
        else {
            throw VerbSyncError.untrusted
        }
        do {
            return (manifestData, try JSONDecoder().decode(ManifestFile.self, from: manifestData))
        } catch {
            throw VerbSyncError.malformedData
        }
    }

    /// Release tags only: letters, digits, `.`, `_`, `-`, starting with a letter or digit. The
    /// ref ends up in a URL path, so nothing else (no `/`, `..`, `?`, `#`) is let through.
    static func isValidRef(_ ref: String) -> Bool {
        guard let first = ref.unicodeScalars.first, ref.unicodeScalars.count <= 64,
              CharacterSet.alphanumerics.contains(first), first.isASCII else { return false }
        return ref.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0))
        }
    }

    private func fetchData(named name: String, ref: String?) async throws -> Data {
        if let ref, !Self.isValidRef(ref) { throw VerbSyncError.malformedData }
        return try await fetchData(from: dataBaseURL(ref).appendingPathComponent(name))
    }

    /// The data files are under 100 KB; anything near this is not one of ours.
    static let maxResponseBytes = 5 * 1024 * 1024

    /// `notFound` is thrown for a 404; any other non-2xx status is `.serverUnreachable`.
    private func fetchData(from url: URL, notFound: VerbSyncError = .serverUnreachable) async throws -> Data {
        var data = Data()
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse else { throw VerbSyncError.serverUnreachable }
            if http.statusCode == 404 { throw notFound }
            guard (200..<300).contains(http.statusCode) else { throw VerbSyncError.serverUnreachable }
            if response.expectedContentLength > Int64(Self.maxResponseBytes) {
                throw VerbSyncError.malformedData
            }
            for try await byte in bytes {
                data.append(byte)
                if data.count > Self.maxResponseBytes { throw VerbSyncError.malformedData }
            }
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw VerbSyncError.offline
            default:
                throw VerbSyncError.serverUnreachable
            }
        }
        return data
    }
}

public extension GitHubVerbFetcher {
    /// This repo's `data/` folder. The manifest and its signature always come from `main`;
    /// each data file comes from the release tag its manifest entry names, or `main` when it names none.
    static func githubMain(
        verifier: ManifestSignatureVerifier = .production,
        session: URLSession = .shared
    ) -> GitHubVerbFetcher {
        let root = "https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/"
        return GitHubVerbFetcher(
            manifestBaseURL: URL(string: root + "main/data/")!,
            dataBaseURL: { ref in URL(string: root + (ref ?? "main") + "/data/")! },
            verifier: verifier,
            session: session
        )
    }
}
