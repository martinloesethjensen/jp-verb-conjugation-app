import Foundation

public struct GitHubVerbFetcher: VerbDataFetching {
    private let manifestURL: URL
    private let verbsURL: URL
    private let session: URLSession

    public init(manifestURL: URL, verbsURL: URL, session: URLSession = .shared) {
        self.manifestURL = manifestURL
        self.verbsURL = verbsURL
        self.session = session
    }

    public func fetchManifest() async throws -> VerbManifest {
        let data = try await fetchData(from: manifestURL)
        do {
            return try JSONDecoder().decode(VerbManifest.self, from: data)
        } catch {
            throw VerbSyncError.malformedData
        }
    }

    public func fetchVerbData() async throws -> Data {
        try await fetchData(from: verbsURL)
    }

    private func fetchData(from url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw VerbSyncError.offline
            default:
                throw VerbSyncError.serverUnreachable
            }
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VerbSyncError.serverUnreachable
        }
        return data
    }
}

public extension GitHubVerbFetcher {
    /// Points at this repo's `data/` files on the `main` branch.
    static func githubMain(session: URLSession = .shared) -> GitHubVerbFetcher {
        let base = "https://raw.githubusercontent.com/martinloesethjensen/jp-verb-conjugation-app/main/data/"
        return GitHubVerbFetcher(
            manifestURL: URL(string: base + "manifest.json")!,
            verbsURL: URL(string: base + "verbs.json")!,
            session: session
        )
    }
}
