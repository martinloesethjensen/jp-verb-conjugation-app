import Foundation
@testable import VerbKit

/// The 25 verbs in the real `data/verbs.json`, for tests that run over real data.
enum RealVerbs {
    static func load() throws -> [Verb] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // VerbKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // VerbKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("data")
            .appendingPathComponent("verbs.json")
        return try JSONDecoder().decode(VerbDataFile.self, from: Data(contentsOf: url)).verbs
    }
}
