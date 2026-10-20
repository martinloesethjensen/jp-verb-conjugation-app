import Foundation
import SwiftData

/// The cached counters: a single row holding the whole `CountersDataFile` as JSON (so the
/// groups are cached with the counters), like `WordsEntity`, so adding a field never needs a
/// store migration.
@Model
public final class CountersEntity {
    @Attribute(.unique) public var key: String
    private var payload: Data

    public static let rowKey = "counters"

    public init(_ file: CountersDataFile) {
        self.key = Self.rowKey
        self.payload = (try? JSONEncoder().encode(file)) ?? Data()
    }

    /// `nil` if the stored payload can't be decoded by this build.
    public func toFile() -> CountersDataFile? {
        try? JSONDecoder().decode(CountersDataFile.self, from: payload)
    }
}
