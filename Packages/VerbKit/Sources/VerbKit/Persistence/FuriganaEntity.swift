import Foundation
import SwiftData

/// The cached reading dictionary: a single row holding the readings as JSON.
/// Stored as `Data`, like `VerbEntity.forms` and `GrammarEntity`, so adding a
/// field to the dictionary never needs a store migration.
@Model
public final class FuriganaEntity {
    /// A fixed key makes "there is exactly one dictionary" explicit, and lets
    /// the unique constraint catch an accidental second row.
    @Attribute(.unique) public var key: String
    private var payload: Data

    public static let rowKey = "dictionary"

    public init(_ dictionary: FuriganaDictionary) {
        self.key = Self.rowKey
        self.payload = (try? JSONEncoder().encode(dictionary.readings)) ?? Data()
    }

    /// `nil` if the stored payload can't be decoded by this build.
    public func toDictionary() -> FuriganaDictionary? {
        guard let readings = try? JSONDecoder().decode([String: String].self, from: payload) else { return nil }
        return FuriganaDictionary(readings: readings)
    }
}
