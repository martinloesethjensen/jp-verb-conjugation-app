import Foundation
import SwiftData

/// The cached word list: a single row holding the words as JSON, like `FuriganaEntity`,
/// so adding a field never needs a store migration.
@Model
public final class WordsEntity {
    @Attribute(.unique) public var key: String
    private var payload: Data

    public static let rowKey = "words"

    public init(_ words: [Word]) {
        self.key = Self.rowKey
        self.payload = (try? JSONEncoder().encode(words.map(StoredWord.init))) ?? Data()
    }

    /// `nil` if the stored payload can't be decoded by this build.
    public func toWords() -> [Word]? {
        (try? JSONDecoder().decode([StoredWord].self, from: payload))?.map(\.word)
    }
}
