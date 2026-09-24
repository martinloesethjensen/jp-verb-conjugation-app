import Foundation

public protocol VerbDataFetching: Sendable {
    func fetchManifest() async throws -> VerbManifest
    func fetchVerbData() async throws -> Data
}
